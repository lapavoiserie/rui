/** A mutable field read inside a **view builder**.

	The closure returns a view, so it runs as part of rendering: this is a real
	view dependency and must still be refused. It guards the narrowing that
	`ActionClosure` asks for -- without this fixture, skipping every closure
	would pass unnoticed. **/
class BuilderClosure extends viewrule.App {
	var hidden:Int = 0;

	static function main() {}

	override public function body():viewrule.View {
		return new viewrule.View().children(function():viewrule.View {
			return new viewrule.View().text('caché : $hidden');
		});
	}
}
