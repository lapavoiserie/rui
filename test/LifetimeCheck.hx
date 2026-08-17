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

		trace(failures == 0 ? "\nall checks passed" : '\n$failures failed');
		#if sys
		Sys.exit(failures == 0 ? 0 : 1);
		#end
	}
}
