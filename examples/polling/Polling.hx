import rui.Signal;

/**
	A resource an effect owns, re-created when what it depends on changes.

	    haxe -cp ../../src -cp . --main Polling --interp

	## Why this example and not a counter

	A counter shows an effect re-running, which is the easy half. This shows the
	half that is easy to get wrong: the effect holds something **live** — here a
	timer — and it re-runs when the interval changes. Without a cleanup the old
	timer keeps ticking beside the new one, and the failure grows with use: two
	pollers, then three, each still firing, none reachable to be stopped.

	The output makes it visible. Watch the tag on each poll: after the interval
	changes, only the new one speaks.
**/
class Polling {
	static var interval = new Signal(300);
	static var polls = 0;
	static var live = 0;

	static function main() {
		var effect = new Effect(() -> {
			var everyMs = interval.value;
			var tag = 'poller@${everyMs}ms';

			var timer = new haxe.Timer(everyMs);
			live++;
			timer.run = () -> {
				polls++;
				Sys.println('  $tag polled (live pollers: $live)');
			};

			// The whole point. Without this line the program still runs, still
			// looks right for a second, and leaks a timer per interval change.
			Effect.onCleanup(() -> {
				timer.stop();
				live--;
				Sys.println('  $tag stopped');
			});

			Sys.println('$tag started');
		});

		// Change what the effect depends on: the old timer must go.
		haxe.Timer.delay(() -> interval.value = 120, 1000);

		// And end it: the last timer must go too, or the program never exits.
		haxe.Timer.delay(() -> {
			effect.dispose();
			Sys.println('disposed — $polls polls in total, $live pollers left');
			if (live != 0) {
				Sys.println("LEAK: a poller outlived the effect that made it");
				Sys.exit(1);
			}
			Sys.exit(0);
		}, 2000);

		#if (sys && !interp)
		while (true) {}
		#end
	}
}
