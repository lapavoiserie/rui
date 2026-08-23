import rui.Signal;
import rui.state.State;

/**
	Behavioural check for `rui.Signal.Scheduler.batch` — the coalescing scope.
	Run with:

	    haxe -cp src -cp test -main BatchCheck --interp
**/
class BatchCheck {
	static var failures = 0;

	static function check(label:String, actual:Dynamic, expected:Dynamic) {
		var ok = Std.string(actual) == Std.string(expected);
		if (!ok)
			failures++;
		trace((ok ? "ok   " : "FAIL ") + label + " = " + actual + (ok ? "" : " (expected " + expected + ")"));
	}

	static function main() {
		// The contract a batch must not break: outside one, a write re-runs
		// what read it before `set` returns. Several backends have no event
		// loop to defer to, so this is not a preference.
		var loose = new State(0);
		var looseRuns = 0;
		new Effect(() -> {
			loose.get();
			looseRuns++;
		});
		loose.set(1);
		check("outside a batch, an effect still runs synchronously", looseRuns, 2);

		// Several cells, one effect, one gesture: one run.
		var a = new State(0);
		var b = new State(0);
		var runs = 0;
		new Effect(() -> {
			a.get();
			b.get();
			runs++;
		});
		check("effect ran on creation", runs, 1);
		Scheduler.batch(() -> {
			a.set(1);
			b.set(2);
		});
		check("two cells in one batch run the effect once", runs, 2);

		// The same cell written repeatedly is one run too: an effect refuses
		// to queue itself twice, which only shows once flushing is held back.
		Scheduler.batch(() -> {
			a.set(10);
			a.set(11);
			a.set(12);
		});
		check("three writes to one cell run the effect once", runs, 3);
		check("and the effect sees the last value", a.peek(), 12);

		// Nothing runs while the scope is open: a batch is not a fast loop,
		// it is a held one.
		var seen = -1;
		var inner = new State(0);
		new Effect(() -> seen = inner.get());
		Scheduler.batch(() -> {
			inner.set(7);
			check("inside the scope, the effect has not run yet", seen, 0);
		});
		check("leaving the scope runs it", seen, 7);

		// Nesting: a call site cannot know whether it is already inside
		// somebody else's gesture, so the outermost scope is what flushes.
		var n = new State(0);
		var nestRuns = 0;
		new Effect(() -> {
			n.get();
			nestRuns++;
		});
		Scheduler.batch(() -> {
			n.set(1);
			Scheduler.batch(() -> n.set(2));
			check("an inner batch does not flush the outer queue", nestRuns, 1);
		});
		check("the outermost batch flushes once", nestRuns, 2);

		// An exception must not strand the effects: the writes before it
		// happened, and a screen showing state nobody holds is worse than a
		// thrown error that also updated.
		var boom = new State(0);
		var boomRuns = 0;
		new Effect(() -> {
			boom.get();
			boomRuns++;
		});
		var caught = false;
		try {
			Scheduler.batch(() -> {
				boom.set(1);
				throw "boom";
			});
		} catch (e:Dynamic) {
			caught = true;
		}
		check("the exception continues out of the batch", caught, true);
		check("and the effects still ran", boomRuns, 2);

		// A batch never delays a platform or durable sink: `State.set` calls
		// those directly, which is why adopting this scope cannot make a
		// screen lag behind its state.
		var mirrored = new State("a");
		var sinkSaw = [];
		mirrored.setPlatformSink(v -> sinkSaw.push(v));
		Scheduler.batch(() -> {
			mirrored.set("b");
			mirrored.set("c");
			check("the sink fires inside the scope, not after", sinkSaw.join(","), "b,c");
		});

		// `batching` tells code that must know whether it is coalescing.
		check("no batch open at rest", Scheduler.batching, false);
		Scheduler.batch(() -> check("batching is true inside", Scheduler.batching, true));

		trace(failures == 0 ? "ALL OK" : failures + " FAILURE(S)");
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
