package rui;

#if (epik_functional || epik_network_client)
import rui.VirtualDom;

class UI {
	static function h(tag:String, props:Dynamic, children:Array<Dynamic>):VNode {
		return VNode.h(tag, props, children != null ? children : []);
	}

	public static function div(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("div", props, children);

	public static function span(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("span", props, children);

	public static function h1(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("h1", props, children);

	public static function h2(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("h2", props, children);

	public static function h3(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("h3", props, children);

	public static function p(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("p", props, children);

	public static function button(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("button", props, children);

	public static function input(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("input", props, children);

	public static function label(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("label", props, children);

	public static function table(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("table", props, children);

	public static function thead(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("thead", props, children);

	public static function tbody(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("tbody", props, children);

	public static function tr(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("tr", props, children);

	public static function th(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("th", props, children);

	public static function td(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("td", props, children);

	public static function i(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("i", props, children);

	public static function b(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("b", props, children);

	public static function strong(props:Dynamic = null, children:Array<Dynamic> = null)
		return h("strong", props, children);
}
#end
