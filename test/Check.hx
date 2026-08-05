import rui.Signal;
import rui.structures.ImmutableList;
import rui.Observable;

class Todo implements Observable {
	public var text:String;
	public var done:Bool;
	public function new(text:String) { this.text = text; this.done = false; }
}

class Check {
	static function main() {
		var s = new Signal(0);
		var e = new Effect(() -> { s.value; });
		var list = new ImmutableList<Todo>([]).push(new Todo("a")).push(new Todo("b"));
		var t = new Todo("x");
		t.subscribe(() -> trace("todo changed"));
		s.value = list.length;
		trace("len=" + list.length + " uuid=" + (t.uuid != null));
	}
}
