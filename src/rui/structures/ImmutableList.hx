package rui.structures;

// @:generic
class ImmutableList<T> {
	final _data:Array<T>;

	public function new(initialData:Array<T> = null) {
		if (initialData != null) {
			_data = initialData.copy();
		} else {
			_data = [];
		}
	}

	public var length(get, never):Int;

	function get_length():Int
		return _data.length;

	public function get(index:Int):T {
		return _data[index];
	}

	public function push(item:T):ImmutableList<T> {
		var newData = _data.copy();
		newData.push(item);
		return new ImmutableList(newData);
	}

	public function filter(f:T->Bool):ImmutableList<T> {
		return new ImmutableList(_data.filter(f));
	}

	public function map<S>(f:T->S):ImmutableList<S> {
		return new ImmutableList(_data.map(f));
	}

	public function iterator():Iterator<T> {
		return _data.iterator();
	}

	public function toArray():Array<T> {
		return _data.copy();
	}
}
