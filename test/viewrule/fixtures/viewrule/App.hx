package viewrule;

/**
	A stand-in for a backend's app base class.

	The rule is parameterised by the app type and the view method precisely so
	it can be tested without any backend: `mui.App`/`view`, `cui.App`/`body` and
	this are the same shape.
**/
class App {
	public function new() {}

	public function body():View {
		return new View();
	}
}
