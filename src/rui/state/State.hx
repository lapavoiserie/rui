package rui.state;

import rui.Signal;

/**
	A reactive state cell, backed by a `Signal`.

	This is the shared implementation the platform UI libraries build their own
	`State<T>` on. It gives them the reactive half for free — reads register a
	dependency, writes re-run the effects that read them — and leaves the
	platform half to a **sink**: a callback invoked when the *application*
	writes, so the library can push the new value to its native widget, bridge
	or observable.

	```haxe
	var count = new State(0);
	count.setPlatformSink(v -> pushToPlatform(v)); // the library wires this once

	count.set(1);           // effects re-run, sink fires  (app write)
	count.applyExternal(2); // effects re-run, sink SILENT (platform write)
	```

	The `applyExternal` distinction is what keeps a two-way binding from
	looping. A value arriving *from* the platform — a SwiftUI `TextField`, a
	Compose recomposition, a Qt signal — must still reach Haxe effects, but must
	not be pushed back where it came from.

	Deliberately minimal: `setTo`, `inc`/`dec`/`tog` and typed subclasses differ
	across the platform libraries (some return the state, others an action
	value), so they belong to those libraries, not here.
**/
class State<T> {
	final _sig:Signal<T>;
	final _name:String;

	var _sink:Null<T->Void>;

	// The durable store's write-through, and the flag that suppresses it while
	// a value coming FROM the store is being applied — see `applyForeign`.
	var _durable:Null<T->Void>;
	var _foreign:Bool = false;

	/** Optional identifier. Some backends key their platform bridge on it. **/
	public var name(get, never):String;

	function get_name():String
		return _name;

	/** Tracked read / notifying write. Same semantics as `get()` and `set()`. **/
	public var value(get, set):T;

	function get_value():T
		return _sig.value;

	function set_value(v:T):T {
		set(v);
		return v;
	}

	public function new(initialValue:T, ?name:String) {
		_sig = new Signal(initialValue);
		_name = name != null ? name : "";
	}

	/** Read through the signal: inside an effect, this registers a dependency. **/
	public function get():T
		return _sig.value;

	/** Read without registering a dependency. **/
	public function peek():T
		return _sig.peek();

	/**
		Write from application code: notifies dependent effects, the durable
		store if this cell has one, then the platform sink. All are skipped if
		the value is unchanged.

		The durable write comes *before* the platform sink so that a sink which
		synchronously re-samples a detached surface — a widget publishing a new
		picture — publishes one the store already agrees with.
	**/
	public function set(v:T):Void {
		if (_sig.peek() == v)
			return;
		_sig.value = v;
		if (_durable != null && !_foreign)
			_durable(v);
		if (_sink != null)
			_sink(v);
	}

	/**
		Write originating from the platform. Notifies dependent effects like any
		other write, but does NOT run the sink — the platform already has this
		value, and echoing it back is how two-way bindings loop.
	**/
	public function applyExternal(v:T):Void {
		_sig.value = v;
	}

	/**
		Write originating from **another process** that shares this cell's
		durable store — the application's own widget extension, say.

		Not `applyExternal`. That one exists for a value the *platform* already
		holds and must therefore not be told about again; here the platform
		holds nothing of the sort, because the value was written by a different
		process entirely. Using `applyExternal` would move the signal and leave
		the visible number stale: on `sui` the Swift mirror is only written by
		`set`, and on `aui` a read returns the Compose value, not the signal's.

		So this goes through `set` — the *overridden* one, whichever backend is
		compiled — and every platform mirror is updated exactly as it would be
		for an application write. Only the write back to the store is
		suppressed, because that is where this value just came from.
	**/
	public function applyForeign(v:T):Void {
		_foreign = true;
		set(v);
		_foreign = false;
	}

	/**
		Register the platform sink. One per state: registering again replaces
		it. Pass `null` to detach.
	**/
	public function setPlatformSink(sink:Null<T->Void>):Void {
		_sink = sink;
	}

	/**
		Register the durable sink — a **second** slot, because the platform
		sink is already taken on every backend. Installed by
		`rui.state.Durable.bind`, not by an application.
	**/
	public function setDurableSink(sink:Null<T->Void>):Void {
		_durable = sink;
	}

	/** Drop the signal's subscribers and both sinks. **/
	public function dispose():Void {
		_sig.dispose();
		_sink = null;
		_durable = null;
	}

	public function toString():String
		return Std.string(peek());
}
