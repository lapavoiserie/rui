package rui;

#if js
typedef Renderer = rui.DomRenderer;
#else
class Renderer {
	public static function render(vnode:rui.VirtualDom.VNode, container:Dynamic) {
		trace("Renderer not implemented for this target");
	}
}
#end
