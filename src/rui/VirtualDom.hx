package rui;

enum VNodeType {
	Element(tag:String, props:Map<String, Dynamic>, children:Array<VNode>);
	Text(content:String);
	ComponentNode(type:Class<Component<Dynamic>>, props:Dynamic, children:Array<VNode>);
	Fragment(children:Array<VNode>);
}

#if js
typedef NativeNode = js.html.Node;
#else
typedef NativeNode = Dynamic;
#end

class VNode {
	public var type:VNodeType;
	public var dom:NativeNode;
	public var componentInstance:Component<Dynamic>;

	public function new(type:VNodeType) {
		this.type = type;
	}

	public static function h(tag:String, props:Dynamic, children:Array<Dynamic>):VNode {
		var mapProps = new Map<String, Dynamic>();
		if (props != null) {
			for (field in Reflect.fields(props)) {
				mapProps.set(field, Reflect.field(props, field));
			}
		}

		var flatChildren = flattenChildren(children);
		return new VNode(Element(tag, mapProps, flatChildren));
	}

	public static function c(type:Class<Component<Dynamic>>, props:Dynamic, children:Array<Dynamic>):VNode {
		return new VNode(ComponentNode(type, props, flattenChildren(children)));
	}

	public static function fragment(children:Array<Dynamic>):VNode {
		return new VNode(Fragment(flattenChildren(children)));
	}

	static function flattenChildren(children:Array<Dynamic>):Array<VNode> {
		var flatChildren:Array<VNode> = [];
		for (child in children) {
			if (Std.isOfType(child, VNode)) {
				flatChildren.push(child);
			} else if (Std.isOfType(child, Array)) {
				var arr:Array<Dynamic> = child;
				for (c in arr) {
					if (Std.isOfType(c, VNode))
						flatChildren.push(c);
					else if (c != null)
						flatChildren.push(new VNode(Text(Std.string(c))));
				}
			} else if (child != null) {
				flatChildren.push(new VNode(Text(Std.string(child))));
			}
		}
		return flatChildren;
	}
}
