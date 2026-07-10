package rui;

import rui.VirtualDom;

@:autoBuild(rui.Macro.build())
class Component<T> {
	public var props:T;
	public var children:Array<VNode>;

	public function new(props:T, children:Array<VNode> = null) {
		this.props = props;
		this.children = children != null ? children : [];
	}

	public function render():VNode {
		return null; // Should be overridden or generated
	}

	public function mount() {}

	public function unmount() {}

	// Internal framework fields
	public var _vnode:VNode;
	public var _rootVNode:VNode;
	public var _forceUpdate:Void->Void;
}
