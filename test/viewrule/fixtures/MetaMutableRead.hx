/**
	A metadata-marked view reading a plain mutable field.

	Registered alongside the "body" target on the same base — which is also
	the regression for the loop that used to `break` after the first matching
	target: `body()` here is clean, so only the metadata target can refuse
	this, and under the old loop it never got the chance.
**/
class MetaMutableRead extends viewrule.App {
	var gauge:Int = 0;

	static function main() {}

	override public function body():viewrule.View {
		return new viewrule.View().text("clean");
	}

	@:probe function extra():viewrule.View {
		return new viewrule.View().text('gauge $gauge');
	}
}
