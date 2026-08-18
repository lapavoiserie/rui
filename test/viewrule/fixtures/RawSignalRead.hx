/**
	A raw reactive cell read in a view.

	The value is right and the write notifies -- but nothing subscribes the tree
	on the backends that rebuild from their own dirty flag, so the screen would
	quietly never update. The rule refuses the read and names the cell.
**/
class RawSignalRead extends viewrule.App {
	final ticks = new rui.Signal(0);

	static function main() {}

	override public function body():viewrule.View {
		return new viewrule.View().text('ticks : ${ticks.value}');
	}
}
