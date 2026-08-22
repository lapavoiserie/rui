package rui.state;

/**
	Where a durable cell's value is kept, and how two writers avoid losing
	each other's work.

	Deliberately **untyped**: values cross as a `String` carrying a
	one-character kind tag. Every backing store this has to sit on — a file in
	an App Group container, `SharedPreferences`, a plain file — carries that
	shape identically, so typing and float formatting live here, once, rather
	than in one native implementation per platform.

	## Why writing is a compare-and-set

	Because two processes on one device may both write: an application and a
	widget extension hosting its own instance of that application. `cafos`
	faced the analogous problem across machines and answered it by making one
	agent authoritative per entry, so no conflict is possible. That answer
	cannot be copied here — the widget's button is *meant* to change the number
	the application shows. What copies is the refusal to guess: every entry
	carries a sequence, `put` writes only if the stored sequence is still the
	one the writer last saw, and **a loser does not retry and does not
	clobber**. It re-reads and adopts the winner's value. A race becomes a
	visible convergence instead of a silent overwrite.
**/
interface DurableStore {
	/** The packed value, or `null` when the key has never been written. **/
	function read(key:String):Null<String>;

	/** The sequence of the stored entry; `0` when absent. **/
	function seqOf(key:String):Int;

	/**
		Write if the stored sequence is still `expectedSeq`. Returns `false`
		without writing when someone else moved first — the caller then
		re-reads rather than insisting.
	**/
	function put(key:String, packed:String, expectedSeq:Int, writer:String):Bool;

	/**
		Bumped by any write from any instance. One integer read is what lets a
		resume decide whether anything needs walking at all.
	**/
	function epoch():Int;
}

/** What a durable cell may hold. The four that survive every marshalling
	boundary in this ecosystem, and the four for which `Signal`'s `!=` means
	something — a reference type mutated in place compares equal to itself,
	so its write would never reach the store. **/
enum abstract DurableKind(String) to String {
	var KInt = "i";
	var KFloat = "f";
	var KBool = "b";
	var KString = "s";
}

/**
	The process-wide driver for durable cells.

	Holds the store, the writer's name, and the cells bound to it. Nothing
	here is reactive: rehydration happens at moments the host names — an
	application coming to the foreground, a widget about to act — because a
	background thread writing cells under a running effect is a different
	and much worse problem.

	The store is installed by the host, the way `mui.surface.Describe.impl`
	is: shared code calls a hook, someone else fills it. `rui` does not know
	that `kui` exists.
**/
class Durable {
	/** Installed once by the host. With none, a durable cell is an ordinary
		cell — which is only correct because a build that could not provide a
		store is refused at compile time, not here. **/
	public static var store:Null<DurableStore> = null;

	/** Which instance we are. Used in messages and to recognise "not me",
		never to arbitrate — the sequence does that. **/
	public static var writer:String = "app";

	static var _bound:Array<Bound> = [];
	static var _epoch:Int = -1;

	/**
		The value a cell should be born with: what the store holds, or the
		application's own default.

		Called from the cell's constructor argument rather than written in
		afterwards, and that placement is load-bearing. Several backends mirror
		the initial value into their platform at construction — sui pushes it
		to Swift, aui writes a Compose `MutableState` — so a cell constructed
		with the default and corrected afterwards would leave the platform
		holding the default while Haxe held the stored value: the application
		disagreeing with its own screen.
	**/
	public static function initial<T>(key:String, kind:DurableKind, fallback:T):T {
		var s = store;
		if (s == null) return fallback;
		var packed = s.read(key);
		if (packed == null) return fallback;
		var v:Null<T> = cast decode(packed, kind);
		return v == null ? fallback : v;
	}

	/**
		Make this cell write through to the store, and be rehydrated from it.

		Two things and no more: the durable sink, and a place in the set that
		`rehydrate` walks.
	**/
	public static function bind<T>(cell:State<T>, key:String, kind:DurableKind):Void {
		var s = store;
		if (s == null) return;

		var record:Bound = {key: key, kind: kind, seq: s.seqOf(key), apply: null};
		record.apply = v -> cell.applyForeign(cast v);
		_bound.push(record);

		cell.setDurableSink(v -> {
			var st = store;
			if (st == null) return;
			var packed = encode(v, kind);
			if (packed == null) return;
			if (st.put(key, packed, record.seq, writer)) {
				record.seq = st.seqOf(key);
			} else {
				// Someone else wrote first. Adopt their value rather than
				// insist on ours — see DurableStore's doc.
				var theirs = st.read(key);
				record.seq = st.seqOf(key);
				if (theirs != null) {
					var decoded = decode(theirs, kind);
					if (decoded != null) record.apply(decoded);
				}
			}
		});
	}

	/**
		Take in whatever the other instance wrote.

		Cheap when nothing happened: one integer read. Called at named moments
		by the host — an application resuming, a widget extension about to run
		a closure — never on a timer and never on a thread.
	**/
	public static function rehydrate():Void {
		var s = store;
		if (s == null) return;

		var now = s.epoch();
		if (now == _epoch) return;
		_epoch = now;

		for (b in _bound) {
			var seq = s.seqOf(b.key);
			if (seq == b.seq) continue;
			b.seq = seq;
			var packed = s.read(b.key);
			if (packed == null) continue;
			var v = decode(packed, b.kind);
			if (v != null) b.apply(v);
		}
	}

	/** Forget every binding. For a host tearing an application down. **/
	public static function releaseAll():Void {
		_bound = [];
		_epoch = -1;
	}

	// -- the codec ---------------------------------------------------------
	//
	// One place, rather than one per native implementation. A float is
	// formatted through Std.string, which is POSIX on every target this
	// ships to; a locale that writes "1,5" would round-trip to nothing, and
	// that is worth saying out loud rather than discovering on a phone.

	static function encode(v:Dynamic, kind:DurableKind):Null<String> {
		if (v == null) return null;
		return switch (kind) {
			case KInt: "i:" + Std.string(v);
			case KFloat: "f:" + Std.string(v);
			case KBool: "b:" + (v == true ? "1" : "0");
			case KString: "s:" + Std.string(v);
		}
	}

	/**
		`null` when the stored value does not answer the kind asked for — a
		version that stored an Int where this one wants a Float, say. The
		caller falls back to the default rather than throwing: in a widget
		extension a crash is a blank rectangle nobody can debug.
	**/
	static function decode(packed:String, kind:DurableKind):Null<Dynamic> {
		if (packed == null || packed.length < 2 || packed.charAt(1) != ":") return null;
		if (packed.charAt(0) != (kind : String)) return null;
		var body = packed.substr(2);
		return switch (kind) {
			case KInt: Std.parseInt(body);
			case KFloat:
				var f = Std.parseFloat(body);
				Math.isNaN(f) ? null : f;
			case KBool: body == "1";
			case KString: body;
		}
	}
}

private typedef Bound = {
	var key:String;
	var kind:DurableKind;
	var seq:Int;
	var apply:Null<Dynamic->Void>;
}
