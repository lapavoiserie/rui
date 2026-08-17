package rui;

/**
	Things to undo, and one moment to undo them.

	```haxe
	var life = new Lifetime();
	life.own(() -> timer.stop());
	life.ownEffect(watcher);
	…
	life.release();          // both, once, in reverse
	```

	`Effect.onCleanup` answers "undo what *this effect* did, before it runs
	again". This answers the other half: "undo everything, because whatever owned
	it is over". They compose — an effect handed to `ownEffect` is disposed here,
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

	/** The common case: an effect whose life is this owner's life. **/
	public function ownEffect(effect:Signal.Effect):Void {
		if (effect != null) own(() -> effect.dispose());
	}

	/** Undo everything, last first. Safe to call more than once. **/
	public function release():Void {
		if (_released) return;
		_released = true;

		var pending = _owned;
		_owned = [];
		var i = pending.length;
		while (i-- > 0) {
			try pending[i]() catch (e:Dynamic) trace("Error releasing a Lifetime: " + e);
		}
	}
}
