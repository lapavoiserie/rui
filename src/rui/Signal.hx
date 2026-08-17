package rui;

import rui.Observable;
#if js
import js.Browser;
#end

class Scheduler {
	static var tasks:Array<Void->Void> = [];
	static var pending = false;

	public static function schedule(task:Void->Void) {
		tasks.push(task);
		if (!pending) {
			pending = true;
			#if js
			Browser.window.requestAnimationFrame(flush);
			#else
			// Synchronous execution for TUI to avoid blocking issues with MainLoop/Timer vs Sys.getChar
			flush(0);
			#end
		}
	}

	static function flush(_) {
		pending = false;
		// Copy tasks to handle recursive scheduling safely
		var currentTasks = tasks.copy();
		tasks = [];
		for (task in currentTasks) {
			task();
		}
	}
}

class Effect {
	public static var contextStack:Array<Effect> = [];
	public static var current(get, never):Effect;

	static function get_current()
		return contextStack.length > 0 ? contextStack[contextStack.length - 1] : null;

	var _fn:Void->Void;
	var _cleanups:Array<Void->Void> = [];
	var _dependencies:Array<Signal<Dynamic>> = [];
	var _isScheduled = false;
	var _disposed = false;

	/**
		Undo something this effect did, before it runs again or when it is
		disposed.

		```haxe
		new Effect(() -> {
			var timer = new haxe.Timer(1000);
			timer.run = () -> tick.value++;
			Effect.onCleanup(() -> timer.stop());
		});
		```

		**Why a call from inside, and not a returned function.** A returned
		cleanup would mean `Void->Null<Void->Void>`, and every existing caller
		passes `Void->Void` — including `nui.NodeSink.bindReactive`, which is how
		three backends bind a property. Haxe would reject all of them. Reading
		the current effect off the context stack costs nothing and breaks
		nothing, and it allows more than one cleanup where a return allows one.

		**Outside an effect this throws**, rather than registering nowhere. A
		cleanup that will never run is a resource that will never be released,
		and silence is the one outcome that cannot be noticed.
	**/
	public static function onCleanup(fn:Void->Void):Void {
		var effect = current;
		if (effect == null)
			throw "rui: Effect.onCleanup was called outside an effect, so nothing would ever run it. "
				+ "Call it from inside the function given to new Effect(...).";
		effect._cleanups.push(fn);
	}

	public function new(fn:Void->Void) {
		_fn = fn;
		run();
	}

	public function run() {
		if (_disposed) return;
		_isScheduled = false;
		// Before the new run, not after: what the last run opened is undone
		// before anything opens it again, so an effect that re-runs on every
		// keystroke cannot stack a timer per keystroke.
		runCleanups();
		cleanupDeps();
		contextStack.push(this);
		try {
			_fn();
		} catch (e:Dynamic) {
			trace("Error in Effect: " + e);
		}
		contextStack.pop();
	}

	public function schedule() {
		if (!_isScheduled) {
			_isScheduled = true;
			Scheduler.schedule(run);
		}
	}

	function cleanupDeps() {
		for (sig in _dependencies) {
			sig.unsubscribe(this);
		}
		_dependencies = [];
	}

	public function addDependency(sig:Signal<Dynamic>) {
		if (_dependencies.indexOf(sig) == -1) {
			_dependencies.push(sig);
		}
	}

	/**
		Stop, and undo.

		Idempotent: disposing twice must not run a cleanup twice, because the
		second run would be undoing something already undone — closing a handle
		that has been closed, or worse, one that has been reused.
	**/
	public function dispose() {
		if (_disposed) return;
		_disposed = true;
		runCleanups();
		cleanupDeps();
	}

	function runCleanups() {
		if (_cleanups.length == 0) return;
		// Taken first: a cleanup that registers another must not extend the list
		// being walked, and one that throws must not keep the rest from running.
		var pending = _cleanups;
		_cleanups = [];
		for (fn in pending) {
			try fn() catch (e:Dynamic) trace("Error in Effect cleanup: " + e);
		}
	}
}

class Signal<T> {
	var _value:T;
	var _subscribers:Array<Effect> = [];

	public function new(initialValue:T) {
		_value = initialValue;
		checkObservable(_value);
	}

	public var value(get, set):T;

	function get_value():T {
		if (Effect.current != null) {
			Effect.current.addDependency(cast this);
			subscribe(Effect.current);
		}
		return _value;
	}

	function set_value(newValue:T):T {
		if (_value != newValue) {
			cleanupObservable(_value); // Clean up old observable
			_value = newValue;
			checkObservable(_value); // Check and subscribe to new observable
			notifySubscribers();
		}
		return _value;
	}

	function checkObservable(v:Dynamic) {
		if (Std.isOfType(v, Observable)) {
			var obs:Observable = cast v;
			obs.subscribe(notifySubscribers); // Subscribe to the observable's changes
		}
	}

	function cleanupObservable(v:Dynamic) {
		if (Std.isOfType(v, Observable)) {
			var obs:Observable = cast v;
			obs.unsubscribe(notifySubscribers); // Unsubscribe from the observable's changes
		}
	}

	public function peek():T {
		return _value;
	}

	public function subscribe(effect:Effect) {
		if (_subscribers.indexOf(effect) == -1) {
			_subscribers.push(effect);
		}
	}

	public function unsubscribe(effect:Effect) {
		_subscribers.remove(effect);
	}

	public function dispose() {
		cleanupObservable(_value);
		_subscribers = [];
	}

	/**
		Wake every subscriber.

		**Not called `notify`.** `java.lang.Object.notify()` is final, so a Haxe
		method by that name makes the class impossible to load on the JVM:
		`IncompatibleClassChangeError` at the first `new Signal(...)`, which on
		`aui` means the first state an app creates. Nothing catches this at
		compile time — Haxe checks it against no JVM base class — and the four
		other backends never load `rui` on a JVM, so it stayed invisible.
	**/
	function notifySubscribers() {
		// Copy subscribers to avoid issues if listeners modify subscriptions during execution
		var subs = _subscribers.copy();
		for (sub in subs) {
			sub.schedule();
		}
	}
}
