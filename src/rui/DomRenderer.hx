package rui;

#if js
import rui.VirtualDom;
import rui.Signal;
import js.html.Element;
import js.html.Node;
import js.html.Text;
import js.Browser;

class DomRenderer {
	public static function render(vnode:VNode, container:Element) {
		container.innerHTML = "";
		var dom = createNode(vnode);
		container.appendChild(dom);
	}

	static function createNode(vnode:VNode):Node {
		switch (vnode.type) {
			case Text(content):
				var node = Browser.document.createTextNode(content);
				vnode.dom = node;
				return node;

			case Element(tag, props, children):
				var el = Browser.document.createElement(tag);
				vnode.dom = el;
				updateProps(el, null, props);
				for (child in children) {
					el.appendChild(createNode(child));
				}
				return el;

			case ComponentNode(cls, props, children):
				// Instantiate component
				var instance = Type.createInstance(cls, [props, children]);
				vnode.componentInstance = instance;
				instance._vnode = vnode; // Link current vnode

				var hook:Node = Browser.document.createComment("component-placeholder");
				vnode.dom = hook;

				var renderLogic = () -> {
					var newRoot = instance.render();
					if (newRoot == null) {
						newRoot = new VNode(Text(""));
					}
					if (instance._rootVNode == null) {
						// First mount
						var node = createNode(newRoot);
						instance._rootVNode = newRoot;
						instance._vnode.dom = node;
						try {
							js.Browser.console.log("Renderer: Calling mount on " + Type.getClassName(cls));
							instance.mount();
						} catch (e:Dynamic) {
							js.Browser.console.error("Error in mount: " + e);
						}
					} else {
						// Update
						patch(instance._rootVNode, newRoot, cast instance._vnode.dom.parentNode);
						instance._rootVNode = newRoot;
						instance._vnode.dom = newRoot.dom;
					}
				};

				instance._forceUpdate = renderLogic;

				new Effect(renderLogic);

				return instance._vnode.dom;

			case Fragment(children):
				var el = Browser.document.createDivElement();
				el.style.display = "contents";
				vnode.dom = el;
				for (child in children) {
					el.appendChild(createNode(child));
				}
				return el;
		}
	}

	static function patch(oldVNode:VNode, newVNode:VNode, parent:Node) {
		if (oldVNode == null)
			return;

		if (oldVNode.type.getIndex() != newVNode.type.getIndex()) {
			// Different types, replace completely
			var newNode = createNode(newVNode);
			parent.replaceChild(newNode, oldVNode.dom);
			return;
		}

		switch (newVNode.type) {
			case Text(content):
				if (oldVNode.dom.textContent != content) {
					oldVNode.dom.textContent = content;
				}
				newVNode.dom = oldVNode.dom;

			case Element(tag, props, children):
				// Check tag match
				switch (oldVNode.type) {
					case Element(oldTag, oldProps, oldChildren):
						if (tag != oldTag) {
							var newNode = createNode(newVNode);
							parent.replaceChild(newNode, oldVNode.dom);
						} else {
							newVNode.dom = oldVNode.dom;
							var el:Element = cast oldVNode.dom;
							updateProps(el, oldProps, props);
							patchChildren(el, oldChildren, children);
						}
					case _:
				}

			case ComponentNode(cls, props, children):
				// Reuse instance if same class
				switch (oldVNode.type) {
					case ComponentNode(oldCls, _, _):
						if (cls == oldCls) {
							// Reuse
							var instance = oldVNode.componentInstance;
							newVNode.componentInstance = instance;
							instance._vnode = newVNode; // Handover vnode reference
							newVNode.dom = oldVNode.dom; // Carry over DOM

							// Update props and children
							instance.props = props;
							instance.children = children;

							// Force update
							instance._forceUpdate();
						} else {
							// Different component class
							var newNode = createNode(newVNode);
							parent.replaceChild(newNode, oldVNode.dom);
						}
					case _:
						// Should not match due to index check above
				}

			case Fragment(children):
				switch (oldVNode.type) {
					case Fragment(oldChildren):
						newVNode.dom = oldVNode.dom;
						var el:Element = cast oldVNode.dom;
						patchChildren(el, oldChildren, children);
					case _:
				}
		}
	}

	static function patchChildren(parent:Element, oldChildren:Array<VNode>, newChildren:Array<VNode>) {
		var len = oldChildren.length > newChildren.length ? oldChildren.length : newChildren.length;
		for (i in 0...len) {
			if (i >= oldChildren.length) {
				parent.appendChild(createNode(newChildren[i]));
			} else if (i >= newChildren.length) {
				parent.removeChild(oldChildren[i].dom);
			} else {
				patch(oldChildren[i], newChildren[i], parent);
			}
		}
	}

	static function updateProps(el:Element, oldProps:Map<String, Dynamic>, newProps:Map<String, Dynamic>) {
		if (oldProps != null) {
			for (key in oldProps.keys()) {
				if (!newProps.exists(key)) {
					removeProp(el, key);
				}
			}
		}
		for (key in newProps.keys()) {
			var val = newProps.get(key);
			var oldVal = oldProps != null ? oldProps.get(key) : null;
			if (val != oldVal) {
				setProp(el, key, val);
			}
		}
	}

	static function setProp(el:Element, key:String, val:Dynamic) {
		if (key.substr(0, 2) == "on") {
			// Event listener
			var event = key.substr(2);
			Reflect.setField(el, key, val);
		} else if (key == "className") {
			el.className = val;
		} else if (key == "value" && (el.tagName == "INPUT" || el.tagName == "TEXTAREA")) {
			el.setAttribute("value", val);
			Reflect.setField(el, "value", val);
		} else if (key == "disabled" || key == "checked") {
			if (val == true)
				el.setAttribute(key, "");
			else
				el.removeAttribute(key);
		} else {
			el.setAttribute(key, Std.string(val));
		}
	}

	static function removeProp(el:Element, key:String) {
		if (key.substr(0, 2) == "on") {
			Reflect.setField(el, key, null);
		} else {
			el.removeAttribute(key);
		}
	}
}
#end
