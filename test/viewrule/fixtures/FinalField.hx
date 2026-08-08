/** Immutable: it cannot change under the view. **/
class FinalField extends viewrule.App {
	final title:String = "Titre";

	static function main() {}

	override public function body():viewrule.View {
		return new viewrule.View().text(title);
	}
}
