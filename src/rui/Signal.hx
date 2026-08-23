package rui;

import rui.Observable;
#if js
import js.Browser;
#end

/**
	When effects run.

	Every target but JS runs them **synchronously**: `schedule` flushes on the
	spot, so a write re-runs what reads it before `set` returns. That is a
	contract, checked by `test/StateCheck.hx`, and several backends depend on
	it — a terminal app has no event loop to hand the work to, and a Sailfish
	process reaches Haxe from a Qt callback that will not come back.

	## Why a batch exists anyway

	Synchronous is right for *one* write and wasteful for several. A button
	handler that writes three cells re-runs everything reading them three
	times, and the last two pictures are the only ones anybody sees. On a
	surface that publishes rather than draws — a widget, a companion on
	another machine — the intermediate pictures are not merely wasted work,
	they are a reload budget spent on frames nobody asked for.

	`batch` is a scope where scheduling accumulates instead of running:

	```haxe
	Scheduler.batch(() -> {
		first.set(1);
		second.set(2);   // an effect reading both runs once, below
	});
	```

	Effects deduplicate themselves (`Effect.schedule` refuses to queue twice),
	so the effect runs once no matter how many of its cells moved.

	## What batching deliberately does not touch

	**State sinks.** `rui.state.State.set` calls the platform sink and the
	durable sink directly, not through here, so a batch never delays the
	screen or the store — only the effects. That is what makes this scope
	cheap to adopt: on four of six backends nothing about drawing goes
	through the scheduler at all.

	**Anything outside a scope.** A write with no batch around it behaves
	exactly as before. Batching is opt-in per call site, and the call sites
	that want it are the ones that dispatch an action — where "several writes,
	one gesture" is the shape by construction.
**/
class Scheduler {
	static var tasks:Array<Void->Void> = [];
	static var pending = false;

	/** How many batches are open. Only leaving the outermost one flushes. **/
	static var depth = 0;

	/**
		Run `body`, holding back every effect it schedules until it returns.

		Nests: an inner batch inside an outer one adds to the same queue, and
		the outer one is what flushes. That matters because a call site cannot
		know whether it is already inside somebody else's gesture.

		**An exception does not swallow the effects.** The writes that happened
		before it happened, and effects that do not run leave the screen
		showing state nobody holds. So the queue is flushed on the way out and
		the exception continues.
	**/
	public static function batch(body:Void->Void):Void {
		depth++;
		try {
			body();
		} catch (e:Dynamic) {
			depth--;
			drain();
			throw e;
		}
		depth--;
		drain();
	}

	/** Whether a batch is open, for code that must know it is coalescing. **/
	public static var batching(get, never):Bool;

	static function get_batching():Bool
		return depth > 0;

	public static function schedule(task:Void->Void) {
		tasks.push(task);
		if (!pending) {
			pending = true;
			#if js
			Browser.window.requestAnimationFrame(flush);
			#else
			// Synchronous execution for TUI to avoid blocking issues with MainLoop/Timer vs Sys.getChar
			if (depth == 0)
				flush(0);
			#end
		}
	}

	/**
		Leaving the outermost batch.

		Nothing on JS: a frame was already requested when the first task was
		scheduled, and `requestAnimationFrame` is that target's own batch —
		forcing a flush here would make effects run *earlier* on JS than they
		do today, which is not what this scope is for.
	**/
	static function drain() {
		#if !js
		if (depth == 0 && pending)
			flush(0);
		#end
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
