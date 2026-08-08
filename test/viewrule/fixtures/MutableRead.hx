/** A view reading a plain mutable field: the defect the rule exists for. **/
class MutableRead extends viewrule.App {
	var count:Int = 0;

	static function main() {}

	override public function body():viewrule.View {
		return new viewrule.View().text('clics : $count');
	}
}
