/** A mutable field touched **only inside an action**.

	The closure returns `Void` and runs on a tap, long after the view was built,
	so nothing on screen depends on `taps`. Accusing this was a false positive
	found by `sui`'s dynamic-hello example. **/
class ActionClosure extends viewrule.App {
	var taps:Int = 0;

	static function main() {}

	override public function body():viewrule.View {
		return new viewrule.View().text("appuyez").onTap(function():Void {
			taps++;
			trace('tap $taps');
		});
	}
}
