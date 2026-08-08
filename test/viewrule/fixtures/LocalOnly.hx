/** A local: recomputed on every run by definition. **/
class LocalOnly extends viewrule.App {
	static function main() {}

	override public function body():viewrule.View {
		var n = 1 + 1;
		return new viewrule.View().text('$n');
	}
}
