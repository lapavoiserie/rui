import rui.Signal;
import rui.Lifetime;

/**
	Behavioural check for `rui.Lifetime`. Run with:

	    haxe -cp src -cp test -main LifetimeCheck --interp
**/
class LifetimeCheck {
	static var failures = 0;

	static function check(label:String, actual:Dynamic, expected:Dynamic) {
		var ok = Std.string(actual) == Std.string(expected);
		if (!ok) failures++;
		trace((ok ? "ok   " : "FAIL ") + label + " = " + actual + (ok ? "" : " (expected " + expected + ")"));
	}

	static function main() {
		// --- Reverse order -----------------------------------------------
		// What was built last is undone first: a handle opened after a
		// connection must close before it.
		var order = [];
		var life = new Lifetime();
		life.own(() -> order.push("first"));
		life.own(() -> order.push("second"));
		life.release();
		check("undone last-registered first", order.join(","), "second,first");

		// --- Once ----------------------------------------------------------
		life.release();
		check("release is idempotent", order.join(","), "second,first");
		check("and says so", life.released, true);

		// --- Registering after the end -------------------------------------
		// Holding it would be a leak wearing the costume of ownership.
		var late = 0;
		life.own(() -> late++);
		check("a late registration is undone at once", late, 1);

		// --- An effect's life is the owner's life ---------------------------
		var s = new Signal(0);
		var runs = 0;
		var cleaned = 0;
		var owner = new Lifetime();
		var effect = new Effect(() -> {
			s.value;
			runs++;
			Effect.onCleanup(() -> cleaned++);
		});
		owner.ownEffect(effect);

		s.value = 1;
		check("the effect runs while owned", '$runs/$cleaned', "2/1");

		owner.release();
		check("releasing disposes it, running its cleanup", '$runs/$cleaned', "2/2");

		s.value = 2;
		check("and it is deaf afterwards", runs, 2);

		// --- One failure does not strand the rest ---------------------------
		var after = 0;
		var mixed = new Lifetime();
		mixed.own(() -> after++);
		mixed.own(() -> throw "boom");
		mixed.release();
		check("a throwing teardown does not stop the others", after, 1);

		// --- keep(): alive while body() keeps asking --------------------------
		var log = [];
		var life = new Lifetime();

		function pass(declare:Bool) {
			life.beginPass();
			if (declare) life.keep("watcher", function() {
				log.push("start");
				return function() log.push("stop");
			});
			life.endPass();
		}

		pass(true);
		check("started the first time it is declared", log.join(","), "start");

		pass(true);
		check("not restarted while it stays declared", log.join(","), "start");

		// The pass that stops asking is the last one it survives: the sweep runs
		// at the START of a pass, because under pull a component's body() runs
		// while the host walks — after the app's body() has returned.
		// Undone when the pass that stopped asking closes — not one pass later.
		// A backend that only rebuilds on demand might never run another pass.
		pass(false);
		check("undone as soon as that pass ends", log.join(","), "start,stop");
		check("and no longer keyed", life.keeping("watcher"), false);

		// Declared again: a fresh start, not a resurrection of the old one.
		pass(true);
		check("declaring it again starts a new one", log.join(","), "start,stop,start");

		// --- release() takes the kept ones too ---------------------------------
		life.release();
		check("release undoes what is still kept", log.join(","), "start,stop,start,stop");

		// --- keeping after release does nothing --------------------------------
		life.keep("late", function() { log.push("late"); return function() {}; });
		check("keep after release is ignored", log.join(","), "start,stop,start,stop");

		trace(failures == 0 ? "\nall checks passed" : '\n$failures failed');
		#if sys
		Sys.exit(failures == 0 ? 0 : 1);
		#end
	}
}
