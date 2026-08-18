package rui;

/**
	Things to undo, and one moment to undo them.

	```haxe
	var life = new Lifetime();
	life.own(() -> timer.stop());
	life.own(watcher.dispose);
	…
	life.release();          // both, once, in reverse
	```

	`Effect.onCleanup` answers "undo what *this effect* did, before it runs
	again". This answers the other half: "undo everything, because whatever owned
	it is over". They compose — `own(effect.dispose)` disposes the effect here,
	which runs its own cleanups.

	## Reverse order

	Undoing runs last-registered first, because that is the order in which
	dependencies were built up. A handle opened after a connection is closed
	before it, which is the only order that cannot close something still in use.

	## Once

	`release()` is idempotent, and empties as it goes. A second release would be
	undoing what has already been undone — closing a handle that has been closed
	or, worse, one that has since been reused.

	## Failures do not stop the queue

	One teardown that throws must not strand the rest. Each is guarded, and the
	failure is traced rather than swallowed silently.
**/
class Lifetime {
	var _owned:Array<Void->Void> = [];
	var _kept:Map<String, {undo:Void->Void, seen:Bool}> = new Map();
	var _released = false;

	public function new() {}

	/** Whether `release()` has already run. **/
	public var released(get, never):Bool;

	function get_released():Bool
		return _released;

	/**
		Take ownership of something to undo.

		Registering after `release()` runs it **immediately**: the owner is
		already over, so anything handed to it now would never be undone at all,
		and holding it would be a leak that looks like ownership.
	**/
	public function own(undo:Void->Void):Void {
		if (undo == null) return;
		if (_released) {
			undo();
			return;
		}
		_owned.push(undo);
	}

	/**
		Keep something alive for as long as `body()` keeps asking for it.

		```haxe
		override function body():View {
		    if (showDetail) lifetime.keep("detail", () -> {
		        var stop = Watch.changes(net, 1000, onChange);
		        return stop;                       // how to undo it
		    });
		    …
		}
		```

		`start` runs the first time the key appears and returns the teardown. The
		key is expected again on every pass; the pass where it stops being asked
		for is the last one it survives.

		## Why a key, and not the view

		Because a view has no identity to hang this on. A `body()` rebuild
		produces **new objects**, so a pointer means nothing across two passes,
		and under the pull contract the host expands and discards views on its own
		schedule without telling Haxe. A key is the one identity the application
		is in a position to state, and it is the same key on every backend.

		## What the lifetime actually is

		"While it is declared" — not "while it is on screen". Those differ, and
		the difference is the point: a view scrolled out of a lazy list is still
		declared, and stopping its watcher because the user scrolled would be a
		bug that takes weeks to attribute. A host's `onDisappear` cannot make that
		distinction; `body()` can, because declaring is what `body()` does.

		## Undone as soon as the pass ends

		A pass is bracketed: `beginPass` before the tree is built, `endPass` once
		it is **fully realised** — which is not the same moment as "body() has
		returned". Under the pull contract a component's `body()` runs lazily
		while the host walks, so the backend forces that expansion inside the
		rebuild (`ViewSource.classify`) and closes the pass after it. A sweep
		before that would undo what a component was about to declare.

		Sweeping at the end rather than at the start of the next pass matters
		more than it looks: a backend that only rebuilds when something asked it
		to — `pui` sleeps otherwise — might never run another pass, and a key
		dropped would then never be undone at all.
	**/
	public function keep(key:String, start:Void->(Void->Void)):Void {
		if (_released) return;

		var existing = _kept.get(key);
		if (existing != null) {
			existing.seen = true;
			return;
		}
		var undo = start();
		_kept.set(key, {undo: undo == null ? function() {} : undo, seen: true});
	}

	/**
		A new pass over the tree is starting.

		Called by the backend immediately before the application's `body()` is
		invoked for a fresh tree. An application never calls it.
	**/
	public function beginPass():Void {
		if (_released) return;
		for (key in _kept.keys()) _kept.get(key).seen = false;
	}

	/**
		The pass is over and the tree is fully realised: undo what it stopped
		asking for.

		Called by the backend once the whole tree exists — **after** any lazy
		expansion has been forced, not merely after `body()` returned. Calling it
		too early undoes what a component was about to declare.
	**/
	public function endPass():Void {
		if (_released) return;

		for (key in _kept.keys()) {
			var entry = _kept.get(key);
			if (entry.seen) continue;
			_kept.remove(key);
			try entry.undo() catch (e:Dynamic) trace("Error releasing \"" + key + "\": " + e);
		}
	}

	/** Whether a key is currently being kept — for tests and diagnostics. **/
	public function keeping(key:String):Bool
		return _kept.exists(key);

	/** Undo everything, last first. Safe to call more than once. **/
	public function release():Void {
		if (_released) return;
		_released = true;

		for (key in _kept.keys()) {
			var entry = _kept.get(key);
			try entry.undo() catch (e:Dynamic) trace("Error releasing \"" + key + "\": " + e);
		}
		_kept = new Map();

		var pending = _owned;
		_owned = [];
		var i = pending.length;
		while (i-- > 0) {
			try pending[i]() catch (e:Dynamic) trace("Error releasing a Lifetime: " + e);
		}
	}
}
