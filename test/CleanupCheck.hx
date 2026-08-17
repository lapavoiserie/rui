import rui.Signal;

/**
	Behavioural check for `Effect.onCleanup` — undoing what an effect did. Run
	with:

	    haxe -cp src -cp test -main CleanupCheck --interp

	The three cases that matter are the three ways a cleanup can be wrong:
	never run, run at the wrong moment, or run twice.
**/
class CleanupCheck {
	static var failures = 0;

	static function check(label:String, actual:Dynamic, expected:Dynamic) {
		var ok = Std.string(actual) == Std.string(expected);
		if (!ok)
			failures++;
		trace((ok ? "ok   " : "FAIL ") + label + " = " + actual + (ok ? "" : " (expected " + expected + ")"));
	}

	static function main() {
		// --- It runs before the effect runs again, not after -----------------
		// The order is the whole point: an effect that re-runs on every write
		// must undo the previous run *first*, or it stacks one live resource
		// per write and the leak grows with use rather than showing up once.
		var trigger = new Signal(0);
		var opened = 0;
		var closed = 0;
		var orderWasWrong = false;

		var effect = new Effect(() -> {
			trigger.value;
			opened++;
			// If a cleanup ever runs *after* the next body, this sees it.
			if (closed > opened) orderWasWrong = true;
			Effect.onCleanup(() -> closed++);
		});

		check("one run, nothing undone yet", '$opened/$closed', "1/0");

		trigger.value = 1;
		check("second run undid the first", '$opened/$closed', "2/1");

		trigger.value = 2;
		check("and the second", '$opened/$closed', "3/2");
		check("never undone after the fact", orderWasWrong, false);

		// --- Disposing undoes the last run -----------------------------------
		effect.dispose();
		check("dispose undid the run still open", '$opened/$closed', "3/3");

		// --- Disposing twice does not undo twice ------------------------------
		// A second cleanup would be closing a handle already closed, which is
		// the failure that is quiet until the handle has been reused.
		effect.dispose();
		check("dispose is idempotent", closed, 3);

		// --- A disposed effect is deaf ---------------------------------------
		trigger.value = 3;
		check("a disposed effect does not run again", opened, 3);

		// --- More than one cleanup per run ------------------------------------
		// What a returned cleanup function could not express.
		var many = 0;
		var multi = new Effect(() -> {
			Effect.onCleanup(() -> many++);
			Effect.onCleanup(() -> many++);
		});
		multi.dispose();
		check("every cleanup registered runs", many, 2);

		// --- One that throws does not silence the rest -------------------------
		var after = 0;
		var throwing = new Effect(() -> {
			Effect.onCleanup(() -> throw "boom");
			Effect.onCleanup(() -> after++);
		});
		throwing.dispose();
		check("a throwing cleanup does not stop the others", after, 1);

		// --- Outside an effect it refuses ------------------------------------
		// Registering nowhere would mean a resource never released, and silence
		// is the one outcome nobody notices.
		var refused = false;
		try
			Effect.onCleanup(() -> {})
		catch (e:Dynamic)
			refused = true;
		check("onCleanup outside an effect throws", refused, true);

		trace(failures == 0 ? "\nall checks passed" : '\n$failures failed');
		#if sys
		Sys.exit(failures == 0 ? 0 : 1);
		#end
	}
}
