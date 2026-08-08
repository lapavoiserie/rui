package viewrule;

/** A stand-in for a backend's view type. **/
class View {
	public var label:String = "";

	public function new() {}

	public function text(s:String):View {
		label = s;
		return this;
	}

	/** An action: a command, run on an event, returning nothing. **/
	public function onTap(f:Void->Void):View {
		return this;
	}

	/** A builder: part of rendering, run to produce a view. **/
	public function children(build:Void->View):View {
		return this;
	}
}
