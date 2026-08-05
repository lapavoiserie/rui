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
		Write from application code: notifies dependent effects, then the
		platform sink. Both are skipped if the value is unchanged.
	**/
	public function set(v:T):Void {
		if (_sig.peek() == v)
			return;
		_sig.value = v;
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
		Register the platform sink. One per state: registering again replaces
		it. Pass `null` to detach.
	**/
	public function setPlatformSink(sink:Null<T->Void>):Void {
		_sink = sink;
	}

	/** Drop the signal's subscribers and the sink. **/
	public function dispose():Void {
		_sig.dispose();
		_sink = null;
	}

	public function toString():String
		return Std.string(peek());
}
