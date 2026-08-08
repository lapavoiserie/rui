/** Observable: a write notifies, so the view can re-run. **/
class ObservableState extends viewrule.App {
	var count:rui.state.State<Int> = new rui.state.State(0);

	static function main() {}

	override public function body():viewrule.View {
		return new viewrule.View().text('clics : ${count.value}');
	}
}
