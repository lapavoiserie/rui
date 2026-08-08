/** A persistent structure: `push` returns a new list, so the field is
	replaced rather than mutated. **/
class ImmutableCollection extends viewrule.App {
	var items:rui.structures.ImmutableList<String> = new rui.structures.ImmutableList();

	static function main() {}

	override public function body():viewrule.View {
		return new viewrule.View().text('${items.length} elements');
	}
}
