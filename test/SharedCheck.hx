import rui.state.Durable.DurableKind;
import rui.state.Shared;
import rui.state.State;

/**
	One owner per cell, without a wire.

	    haxe -cp src -cp test -main SharedCheck --interp

	Two registries in one process — a phone and a watch — joined by a carrier
	that hands frames straight across. What is checked here is the RULE:
	which writes land, which travel, which are refused, and what a stamp does.
	The wire's own framing is dui's to prove.
**/
class SharedCheck {
	static var fails = 0;
	static var checks = 0;

	static function check(label:String, ok:Bool) {
		checks++;
		if (!ok)
			fails++;
		Sys.println((ok ? "ok   " : "FAIL ") + label);
	}

	static function main() {
		var phone = new Shared(10);
		var watch = new Shared(20);
		phone.me = "Phone";
		watch.me = "Watch";

		var goalP = new State(10000);
		var stepsP = new State(0);
		var goalW = new State(10000);
		var stepsW = new State(0);
		// A third cell the phone owns and never writes in this check: the
		// stamp rule is exercised on it with stamps the phone never issued,
		// which would otherwise -- correctly -- outrun the phone's own.
		var modeW = new State(1);
		phone.bindCell(goalP, "goal", KInt, "Phone");
		phone.bindCell(stepsP, "steps", KInt, "Watch");
		watch.bindCell(goalW, "goal", KInt, "Phone");
		watch.bindCell(stepsW, "steps", KInt, "Watch");
		watch.bindCell(modeW, "mode", KInt, "Phone");

		var refusals:Array<String> = [];
		phone.onRefused = w -> refusals.push("phone: " + w);
		watch.onRefused = w -> refusals.push("watch: " + w);

		// --- before any wire: owned writes land, foreign ones do not ---
		goalP.set(11000);
		check("an owned write lands with no wire", goalP.peek() == 11000);
		check("and is stamped with this incarnation", phone.stampOf("goal").i == 10 && phone.stampOf("goal").s == 1);

		stepsP.set(5);
		check("a foreign write does NOT land", stepsP.peek() == 0);
		check("and is refused with a word", refusals.length == 1 && refusals[0].indexOf("Watch") >= 0);

		// --- a carrier: frames straight across ---
		var wire = new Straight(phone, watch);
		phone.carrier = wire.a;
		watch.carrier = wire.b;

		// A sync: what each owns, applied by the other if newer.
		for (c in phone.owned())
			watch.receiveCell(c.k, c.i, c.s, c.v);
		check("a sync carries the owner's earlier write", goalW.peek() == 11000);
		for (c in watch.owned())
			phone.receiveCell(c.k, c.i, c.s, c.v);
		check("a never-written owned cell syncs as (incarnation, 0)", phone.stampOf("steps").i == 20 && phone.stampOf("steps").s == 0);

		// The watch writes what it owns: instant there, a frame later here.
		var seen = 0;
		new rui.Signal.Effect(() -> {
			stepsP.get();
			seen++;
		});
		stepsW.set(100);
		check("an owned write is instant on the owner", stepsW.peek() == 100);
		check("and reaches the peer", stepsP.peek() == 100);
		check("through the signal, so the peer's views wake", seen == 2);

		// The phone writes a cell it does not own: an intent, applied by the
		// owner, coming back with the owner's stamp.
		stepsP.set(0);
		check("a foreign write becomes the owner's write", stepsW.peek() == 0);
		check("and comes back as the owner's value", stepsP.peek() == 0);
		check("stamped by the owner", phone.stampOf("steps").i == 20 && phone.stampOf("steps").s == 2);

		// --- the rule: apply if newer, never otherwise ---
		check("a foreign cell starts unstamped", watch.stampOf("mode").i == 0);
		var first = watch.receiveCell("mode", 10, 4, "i:2");
		check("the first value is applied", first && modeW.peek() == 2);
		var stale = watch.receiveCell("mode", 9, 99, "i:3");
		check("an older incarnation is refused", !stale && modeW.peek() == 2);
		var same = watch.receiveCell("mode", 10, 4, "i:3");
		check("the same stamp is refused", !same && modeW.peek() == 2);
		var later = watch.receiveCell("mode", 10, 5, "i:4");
		check("a later sequence is applied", later && modeW.peek() == 4);
		var reborn = watch.receiveCell("mode", 11, 0, "i:5");
		check("a later incarnation is applied whatever its sequence", reborn && modeW.peek() == 5);

		// --- two ages of one application ---
		var before = refusals.length;
		watch.receiveCell("nothing", 10, 3, "i:1");
		check("an undeclared cell is ignored with a word", refusals.length == before + 1);
		watch.receiveCell("mode", 11, 9, "s:twelve");
		check("a wrong kind is ignored with a word", refusals.length == before + 2 && modeW.peek() == 5);
		watch.receiveIntent("mode", "i:1");
		check("an intent for a cell this party does not own is ignored", refusals.length == before + 3 && modeW.peek() == 5);

		// --- a foreign value does not write back ---
		var carried = wire.count;
		watch.receiveCell("mode", 11, 10, "i:500");
		check("applying a foreign value carries nothing", wire.count == carried && modeW.peek() == 500);

		// --- intents ---
		var ran:Array<Int> = [];
		watch.declareIntent({name: "resetSteps", owner: "Watch", run: a -> { stepsW.set(0); ran.push((a[0] : Int)); }});
		stepsW.set(300);
		var ok = phone.call("resetSteps", "Watch", [7], () -> ran.push(-1));
		check("an intent for another party is carried, not run here", ok && ran.length == 1 && ran[0] == 7);
		check("and ran on the owner", stepsW.peek() == 0 && stepsP.peek() == 0);
		var here = watch.call("resetSteps", "Watch", [8], () -> ran.push(8));
		check("an intent for this party runs here, unserialised", here && ran[ran.length - 1] == 8);
		before = refusals.length;
		phone.receiveCall("resetSteps", []);
		check("a call for an intent this party does not declare is refused", refusals.length == before + 1);

		// --- the link goes: owned writes land, foreign ones are refused ---
		wire.down = true;
		goalP.set(20000);
		check("with the link down an owned write still lands", goalP.peek() == 20000);
		check("and the peer keeps what it last saw", goalW.peek() == 11000);
		before = refusals.length;
		stepsP.set(999);
		check("with the link down a foreign write is refused now, not queued", stepsP.peek() == 0 && refusals.length == before + 1);
		wire.down = false;
		for (c in phone.owned())
			watch.receiveCell(c.k, c.i, c.s, c.v);
		check("a sync after the gap converges", goalW.peek() == 20000);

		// --- an undecided party owns nothing ---
		var nobody = new Shared(1);
		var cell = new State(1);
		nobody.bindCell(cell, "x", KInt, "Phone");
		nobody.onRefused = _ -> {};
		cell.set(2);
		check("an undecided party owns nothing: its write is refused", cell.peek() == 1);

		Sys.println(fails == 0 ? '\nall $checks checks passed' : '\n$fails failed');
		Sys.exit(fails == 0 ? 0 : 1);
	}
}

/** Two carriers, each handing frames to the other registry directly. **/
private class Straight {
	public final a:End;
	public final b:End;
	public var down = false;
	public var count = 0;

	public function new(phone:Shared, watch:Shared) {
		a = new End(this, watch);
		b = new End(this, phone);
	}
}

private class End implements rui.state.Shared.SharedCarrier {
	final wire:Straight;
	final far:Shared;

	public function new(wire:Straight, far:Shared) {
		this.wire = wire;
		this.far = far;
	}

	public function carryCell(key:String, i:Int, s:Int, packed:String):Void {
		if (wire.down)
			return;
		wire.count++;
		far.receiveCell(key, i, s, packed);
	}

	public function carryIntent(key:String, packed:String):Bool {
		if (wire.down)
			return false;
		wire.count++;
		return far.receiveIntent(key, packed);
	}

	public function carryCall(name:String, owner:String, args:Array<Dynamic>):Bool {
		if (wire.down)
			return false;
		wire.count++;
		return far.receiveCall(name, args);
	}
}
