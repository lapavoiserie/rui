import rui.Signal;
import rui.state.State;

/**
	Behavioural check for `rui.state.State` — the contract the platform UI
	libraries build on. Run with:

	    haxe -cp src -cp test -main StateCheck --interp
**/
class StateCheck {
	static var failures = 0;

	static function check(label:String, actual:Dynamic, expected:Dynamic) {
		var ok = Std.string(actual) == Std.string(expected);
		if (!ok)
			failures++;
		trace((ok ? "ok   " : "FAIL ") + label + " = " + actual + (ok ? "" : " (expected " + expected + ")"));
	}

	static function main() {
		// Reads inside an effect are tracked; writes re-run it.
		var count = new State(0);
		var runs = 0;
		new Effect(() -> {
			count.get();
			runs++;
		});
		check("effect ran on creation", runs, 1);
		count.set(1);
		check("effect re-ran on write", runs, 2);
		count.set(1);
		check("unchanged write is silent", runs, 2);

		// peek() reads without subscribing.
		var p = new State(0);
		var peekRuns = 0;
		new Effect(() -> {
			p.peek();
			peekRuns++;
		});
		p.set(42);
		check("peek() does not subscribe", peekRuns, 1);

		// The sink fires on application writes only.
		var s = new State("a");
		var pushed = [];
		s.setPlatformSink(v -> pushed.push(v));
		s.set("b");
		check("sink fires on app write", pushed, ["b"]);
		s.set("b");
		check("sink silent on unchanged write", pushed, ["b"]);

		// A platform write reaches effects but must not echo back.
		var seen = [];
		new Effect(() -> seen.push(s.get()));
		s.applyExternal("c");
		check("applyExternal notifies effects", seen, ["b", "c"]);
		check("applyExternal does NOT run the sink", pushed, ["b"]);

		// ... and an app write after it still reaches the sink.
		s.set("d");
		check("sink still live after applyExternal", pushed, ["b", "d"]);

		// value is an alias for get()/set(), sink included.
		var v = new State(0);
		var vPushed = [];
		v.setPlatformSink(x -> vPushed.push(x));
		v.value = 7;
		check("value setter writes", v.value, 7);
		check("value setter runs the sink", vPushed, [7]);

		// Detaching the sink.
		v.setPlatformSink(null);
		v.set(8);
		check("detached sink stays silent", vPushed, [7]);

		// name defaults to "".
		check("unnamed state", new State(0).name, "");
		check("named state", new State(0, "count").name, "count");

		// dispose() stops effects from re-running.
		var d = new State(0);
		var dRuns = 0;
		new Effect(() -> {
			d.get();
			dRuns++;
		});
		d.dispose();
		d.set(1);
		check("dispose() drops subscribers", dRuns, 1);

		trace(failures == 0 ? "ALL CHECKS PASSED" : failures + " CHECK(S) FAILED");
		#if sys
		Sys.exit(failures == 0 ? 0 : 1);
		#end
	}
}
