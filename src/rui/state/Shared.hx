package rui.state;

import rui.state.Durable.DurableKind;

/**
	The wire a registry speaks to. Implemented by `dui.state.Share`; `rui`
	knows the rule, not the network.

	Every method is "carry this somewhere": the registry never learns whether
	that is a socket, a Data Layer message or a loop in a test.
**/
interface SharedCarrier {
	/** A cell this party owns was written. Carry it to every peer. **/
	function carryCell(key:String, i:Int, s:Int, packed:String):Void;

	/** A cell another party owns was written *here*. Carry the request to
		its owner. `false` when no owner can be reached right now. **/
	function carryIntent(key:String, packed:String):Bool;

	/** An `@:intent` method meant for another party was called here. **/
	function carryCall(name:String, owner:String, args:Array<Dynamic>):Bool;
}

/** One `@:intent` method, as the application declares it. **/
typedef IntentDecl = {
	var name:String;
	var owner:String;
	var run:Array<Dynamic>->Void;
}

/** A stamped, packed cell: what crosses on a sync. **/
typedef StampedCell = {
	var k:String;
	var i:Int;
	var s:Int;
	var v:String;
}

/**
	One owner per cell.

	A `@:state(shared(Party))` field has exactly one owner. The owner's
	writes replicate to the peers as observable state; a peer's write becomes
	an *intent* the owner applies; a plain `@:state` never leaves the device.
	This class holds the rule; the wire is somebody else's
	(`SharedCarrier`).

	```haxe
	@:state(shared(Phone)) var goal:Int = 10000;   // the phone writes it, the watch asks
	@:state(shared(Watch)) var steps:Int = 0;      // the watch writes it, the phone reads
	```

	## The rule, and why there is no merge

	Only the owner writes a shared cell. A write on an owned cell is local,
	immediate, stamped `(incarnation, sequence)` and carried to the peers. A
	write on a cell this party does not own is **not a write**: nothing
	changes here; the value travels to the owner as an intent, and comes back
	as the owner's write with the owner's stamp. There is never a second
	writer on the wire, so there is nothing to merge — the registry rule of
	`cafos`, borrowed whole: single author, sequence only goes up, apply if
	newer.

	That is also why a foreign write is never optimistic. A peer that showed
	`12000` before the owner said so would be showing a value nobody stamped,
	and would have to take it back if the owner never did.

	## The stamp

	`(i, s)`: the writer's incarnation and its sequence within it. The
	incarnation is bumped at every start, so a restarted device writes
	"newer" than its previous life whatever its clock did — with a durable
	store it is a counter kept there; without one it is the clock in seconds,
	which is honest for a demo and said so.

	## What this refuses, with a word

	A foreign write with no owner reachable is refused now, through
	`onRefused`, rather than queued: replaying "set to 12000" three times
	later is how a person's three taps become three surprises. A frame for a
	cell this build does not declare, or whose kind does not match, is
	ignored with a word — two ages of one application must be able to talk.

	## Instances, and the one the macro uses

	`Shared.current` is the application's registry; the `@:state` macro binds
	cells there. Tests and harnesses make their own, so two parties can live
	in one process.
**/
class Shared {
	/** The application's registry — what `@:state(shared(...))` binds to. **/
	public static var current:Shared = new Shared();

	/** Which party this process is: set by `dui.state.Share.join`, or by the
		application before its first write. Empty means "not decided", and an
		undecided party owns nothing. **/
	public var me:String = "";

	/** The wire. `null` until something joins: owned writes still land and
		are stamped, and a later sync carries them. **/
	public var carrier:Null<SharedCarrier> = null;

	/** This process's incarnation, in every stamp it writes. **/
	public final incarnation:Int;

	/** A refusal, in a sentence the application may show. Defaults to a
		trace, so nothing is silent. **/
	public dynamic function onRefused(word:String):Void
		trace("rui.state.Shared: " + word);

	var seq = 0;
	final cells = new Map<String, SharedCell>();
	final intents = new Map<String, IntentDecl>();

	public function new(?incarnation:Int) {
		this.incarnation = incarnation != null ? incarnation : nextIncarnation();
	}

	/** Whether `owner` is this party. **/
	public function owns(owner:String):Bool
		return me != "" && owner == me;

	// -- binding -----------------------------------------------------------

	/** What the `@:state` macro emits, on the application's registry. **/
	public static function bind<T>(cell:State<T>, key:String, kind:DurableKind, owner:String):Void
		current.bindCell(cell, key, kind, owner);

	/**
		Make `cell` a shared cell owned by `owner`.

		Installs the share hook: a write on an owned cell is stamped and
		carried, then lands; a write on a foreign cell is carried as an intent
		and does **not** land.
	**/
	public function bindCell<T>(cell:State<T>, key:String, kind:DurableKind, owner:String):Void {
		var rec:SharedCell = {
			key: key,
			kind: kind,
			owner: owner,
			i: 0,
			s: 0,
			apply: v -> cell.applyForeign(cast v),
			write: v -> cell.set(cast v),
			read: () -> cell.peek(),
		};
		cells.set(key, rec);
		cell.setShareHook(v -> wrote(rec, v));
	}

	function wrote(rec:SharedCell, v:Dynamic):Bool {
		var packed = Durable.encode(v, rec.kind);
		if (packed == null)
			return false;
		if (owns(rec.owner)) {
			rec.i = incarnation;
			rec.s = ++seq;
			var c = carrier;
			if (c != null)
				c.carryCell(rec.key, rec.i, rec.s, packed);
			return false;
		}
		var c = carrier;
		if (c == null || !c.carryIntent(rec.key, packed))
			onRefused('"${rec.key}" belongs to ${rec.owner}, which cannot be reached: the write was not made.');
		return true;
	}

	// -- what crosses ------------------------------------------------------

	/** Every cell this party owns, stamped and packed. A cell never written
		in this life is stamped `(incarnation, 0)`: newer than any previous
		life, older than any write in this one. **/
	public function owned():Array<StampedCell> {
		return gather(true);
	}

	/**
		Every cell this party **holds** — its own, and the ones it has heard
		from their owners — each carrying the stamp of its real owner. What a
		sync carries.

		Owned is not enough the moment a device relays. A tablet that joins
		through a phone would learn the phone's cells and never the watch's:
		the phone holds the watch's steps, stamped by the watch, and passing
		them on loses nothing about who wrote what. A cell whose owner has
		never been heard from is left out — `(0, 0)` would be refused by
		everyone anyway, and saying nothing is cheaper than saying nothing
		loudly.
	**/
	public function held():Array<StampedCell> {
		return gather(false);
	}

	function gather(mineOnly:Bool):Array<StampedCell> {
		var out:Array<StampedCell> = [];
		for (rec in cells) {
			if (owns(rec.owner)) {
				if (rec.i == 0)
					rec.i = incarnation;
			} else if (mineOnly || rec.i == 0) {
				continue;
			}
			var packed = Durable.encode(rec.read(), rec.kind);
			if (packed != null)
				out.push({k: rec.key, i: rec.i, s: rec.s, v: packed});
		}
		return out;
	}

	/** The stamp this party holds for a cell, `(0, 0)` when it has never
		seen one. **/
	public function stampOf(key:String):{i:Int, s:Int} {
		var rec = cells.get(key);
		return rec == null ? {i: 0, s: 0} : {i: rec.i, s: rec.s};
	}

	/**
		An owner's write arrived. Applied when newer than what this party
		holds, through `applyForeign` — so the platform mirror updates and
		nothing is written back. `true` when it was applied.
	**/
	public function receiveCell(key:String, i:Int, s:Int, packed:String):Bool {
		var rec = cells.get(key);
		if (rec == null) {
			onRefused('a value arrived for "$key", which this build does not declare; ignored.');
			return false;
		}
		// My own cell, coming back to me. Not a refusal and not worth a word:
		// once devices relay what they hold, an owner routinely hears its own
		// value echoed by a peer that is passing on what it has. It is simply
		// not newer than what the owner holds, which is the whole answer.
		if (owns(rec.owner))
			return false;
		var v = Durable.decode(packed, rec.kind);
		if (v == null) {
			onRefused('a value arrived for "$key" with the wrong kind ("$packed", wanted ${rec.kind}); ignored.');
			return false;
		}
		if (!isNewer(i, s, rec.i, rec.s))
			return false;
		rec.i = i;
		rec.s = s;
		rec.apply(v);
		return true;
	}

	/** A peer asked this party to set a cell it owns. Applied through the
		ordinary write, so it is stamped and carried back like any other. **/
	public function receiveIntent(key:String, packed:String):Bool {
		var rec = cells.get(key);
		if (rec == null || !owns(rec.owner)) {
			onRefused('an intent arrived for "$key", which this party does not own; ignored.');
			return false;
		}
		var v = Durable.decode(packed, rec.kind);
		if (v == null) {
			onRefused('an intent arrived for "$key" with the wrong kind ("$packed"); ignored.');
			return false;
		}
		rec.write(v);
		return true;
	}

	// -- intents -----------------------------------------------------------

	/** Declare an `@:intent` method, so a call arriving by name can run. **/
	public function declareIntent(decl:IntentDecl):Void
		intents.set(decl.name, decl);

	/**
		Call an intent: run `local` when this party owns it, carry it
		otherwise. What the generated method does.
	**/
	public function call(name:String, owner:String, args:Array<Dynamic>, local:Void->Void):Bool {
		if (owns(owner)) {
			local();
			return true;
		}
		var c = carrier;
		if (c == null || !c.carryCall(name, owner, args)) {
			onRefused('"$name()" runs on $owner, which cannot be reached: nothing was done.');
			return false;
		}
		return true;
	}

	/** A call arrived for an intent this party owns. **/
	public function receiveCall(name:String, args:Array<Dynamic>):Bool {
		var decl = intents.get(name);
		if (decl == null) {
			onRefused('a call arrived for "$name()", which this build does not declare; ignored.');
			return false;
		}
		if (!owns(decl.owner)) {
			onRefused('a call arrived for "$name()", which runs on ${decl.owner}, not here; ignored.');
			return false;
		}
		decl.run(args);
		return true;
	}

	// -- the rule ----------------------------------------------------------

	/** Strictly newer: a later incarnation, or the same one further along. **/
	public static inline function isNewer(i1:Int, s1:Int, i2:Int, s2:Int):Bool
		return i1 > i2 || (i1 == i2 && s1 > s2);

	/** The incarnation this process starts with: a counter in the durable
		store when there is one, the clock in seconds when there is not. **/
	static function nextIncarnation():Int {
		var s = Durable.store;
		if (s != null) {
			var key = "rui/shared/incarnation";
			var last = Durable.initial(key, KInt, 0);
			var next = last + 1;
			var packed = Durable.encode(next, KInt);
			if (packed != null)
				s.put(key, packed, s.seqOf(key), Durable.writer);
			return next;
		}
		return Std.int(Date.now().getTime() / 1000);
	}
}

private typedef SharedCell = {
	var key:String;
	var kind:DurableKind;
	var owner:String;
	var i:Int;
	var s:Int;
	var apply:Dynamic->Void;
	var write:Dynamic->Void;
	var read:Void->Dynamic;
}
