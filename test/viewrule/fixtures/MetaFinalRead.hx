/** The same shape, reading a `final` — what the rule accepts, via metadata. **/
class MetaFinalRead extends viewrule.App {
	final label:String = "steady";

	static function main() {}

	override public function body():viewrule.View {
		return new viewrule.View().text("clean");
	}

	@:probe function extra():viewrule.View {
		return new viewrule.View().text(label);
	}
}
