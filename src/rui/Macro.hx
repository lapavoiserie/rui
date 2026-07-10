package rui;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.xml.Parser;

class Macro {
	public static function buildComponentTags():Array<Field> {
		#if macro
		var fields = Context.getBuildFields();
		var pos = Context.currentPos();

		// List of known components in epikUI.
		// ideally we scan the package, but for simplicity here we list them.
		var componentNames = [
			"Button",
			"TextInput",
			"Card",
			"Grid",
			"Calendar",
			"Table",
			"If",
			"Window",
			"Spinner"
		];

		for (name in componentNames) {
			// Check if type exists
			try {
				var typePath = {pack: ["epikowa", "epikUI"], name: name};
				var complexType = TPath(typePath);

				// Construct the helper function:
				// public static function Button(props:Dynamic = null, children:Array<Dynamic> = null) {
				//     return VNode.c(epikowa.epikUI.Button, props, children != null ? children : []);
				// }

				var funcField:Field = {
					name: name,
					access: [APublic, AStatic],
					kind: FFun({
						args: [
							{
								name: "props",
								type: macro :Dynamic,
								opt: true,
								value: macro null
							},
							{
								name: "children",
								type: macro :Array<Dynamic>,
								opt: true,
								value: macro null
							}
						],
						ret: macro :rui.VirtualDom.VNode,
						expr: macro {
							return rui.VirtualDom.VNode.c($p{["epikowa", "epikUI", name]}, props, children != null ? children : []);
						}
					}),
					pos: pos
				};
				fields.push(funcField);
			} catch (e:Dynamic) {
				// Ignore if not found
			}
		}

		return fields;
		#else
		return null;
		#end
	}

	public static function build():Array<Field> {
		#if macro
		trace("Macro: Running build for " + haxe.macro.Context.getLocalClass().toString());
		var fields = Context.getBuildFields();
		var newFields:Array<Field> = [];
		var signalNames:Array<String> = [];

		var localClass = Context.getLocalClass().get();
		var pos = Context.currentPos();

		for (field in fields) {
			var isState = false;
			for (meta in field.meta) {
				if (meta.name == ":state") {
					isState = true;
					break;
				}
			}

			if (isState) {
				switch (field.kind) {
					case FVar(t, e):
						// Check for immutability
						if (t != null) {
							checkImmutable(t, field.pos);
						} else if (e != null) {
							// Try to infer type and check immutability
							try {
								var inferredType = Context.typeof(e);
								checkType(inferredType, field.pos);
							} catch (err:Dynamic) {
								// If inference fails, fall back to simple AST checks
								switch (e.expr) {
									case EArrayDecl(_):
										Context.error("State fields cannot be mutable Arrays. Use ImmutableList.", field.pos);
									case _:
								}
							}
						}

						// 1. Create backing signal field
						var signalName = "_" + field.name + "_signal";
						// Determine type of Signal
						// If t is known, use it. If not, try to infer from e.
						if (t == null && e != null) {
							switch (e.expr) {
								case EConst(CInt(_)): t = macro :Int;
								case EConst(CFloat(_)): t = macro :Float;
								case EConst(CString(_)): t = macro :String;
								case EConst(CIdent("true") | CIdent("false")): t = macro :Bool;
								case _:
									// Fallback or error?
									// For now Dynamic if simpler, or try to keep it null?
									// Haxe requires type for property if no init.
									t = macro :Dynamic;
							}
						}

						var signalType:ComplexType = null;
						if (t != null) {
							signalType = TPath({pack: ["rui"], name: "Signal", params: [TPType(t)]});
						} else {
							signalType = macro :rui.Signal<Dynamic>;
						}

						// Initializer: new Signal(e)
						var initExpr = e != null ? macro new rui.Signal($e) : macro new rui.Signal(null);

						var signalField:Field = {
							name: signalName,
							access: [APrivate],
							kind: FVar(signalType, initExpr),
							pos: field.pos,
							meta: []
						};
						newFields.push(signalField);
						signalNames.push(signalName);

						// 2. Transform original field to property
						field.kind = FProp("get", "set", t, null);
						// Make implicitly public if not specified?
						// Or keep existing access.
						// Usually state is public or private?
						// Let's keep original access mod.

						// 3. Create getter
						var getName = "get_" + field.name;
						var getBody = macro return $i{signalName}.value;
						var getField:Field = {
							name: getName,
							access: [APrivate], // Getter is private usually
							kind: FFun({
								args: [],
								ret: t,
								expr: getBody
							}),
							pos: field.pos
						};
						newFields.push(getField);

						// 4. Create setter
						var setName = "set_" + field.name;
						var setBody = macro return $i{signalName}.value = v;
						var setField:Field = {
							name: setName,
							access: [APrivate],
							kind: FFun({
								args: [{name: "v", type: t}],
								ret: t,
								expr: setBody
							}),
							pos: field.pos
						};
						newFields.push(setField);

					case _:
						// Only works on vars
						Context.warning("@:state only supported on variables", field.pos);
				}
			}
		}

		// Generate unmount to dispose signals
		if (signalNames.length > 0) {
			var disposeExprs = [];
			for (name in signalNames) {
				disposeExprs.push(macro $i{name}.dispose());
			}

			var existingUnmount = null;
			for (f in fields) {
				if (f.name == "unmount") {
					existingUnmount = f;
					break;
				}
			}

			if (existingUnmount != null) {
				switch (existingUnmount.kind) {
					case FFun(f):
						f.expr = macro {
							${f.expr};
							$b{disposeExprs};
						};
					case _:
				}
			} else {
				newFields.push({
					name: "unmount",
					access: [APublic, AOverride],
					kind: FFun({
						args: [],
						ret: macro :Void,
						expr: macro {
							super.unmount();
							$b{disposeExprs};
						}
					}),
					pos: Context.currentPos()
				});
			}
		}

		return fields.concat(newFields);
		#else
		return null;
		#end
	}

	public static macro function xml(e:Expr):Expr {
		#if macro
		var pos = Context.currentPos();

		var flattened = flatten(e);
		var xmlStr = sanitizeJsx(flattened.str);
		trace("XML Input Expr: " + e.expr);
		trace("Flattened XML: " + xmlStr);
		var exprs = flattened.exprs;

		try {
			var xml = Parser.parse(xmlStr);
			var root = xml.firstElement();
			if (root == null)
				return macro null;
			return parseNode(root, pos, exprs);
		} catch (err:Dynamic) {
			Context.error("XML Parse Error: " + err + " (Generated XML: " + xmlStr + ")", pos);
			return macro null;
		}
		#else
		return null;
		#end
	}

	#if macro
	static function flatten(e:Expr):{str:String, exprs:Array<Expr>} {
		var exprs = [];
		var str = flattenExpr(e, exprs);
		return {str: str, exprs: exprs};
	}

	static function flattenExpr(e:Expr, exprs:Array<Expr>):String {
		switch (e.expr) {
			case EConst(CString(s, _)):
				// Manually parse ${...} if Haxe didn't interpolate (e.g. macro arguments)
				var buf = new StringBuf();
				var lastIndex = 0;
				var ereg = ~/\$\{([^}]+)\}/g;
				while (ereg.matchSub(s, lastIndex)) {
					var matchPos = ereg.matchedPos();
					buf.addSub(s, lastIndex, matchPos.pos - lastIndex);
					var code = ereg.matched(1);
					try {
						var expr = Context.parse(code, e.pos);
						exprs.push(expr);
						buf.add('__EXPR_${exprs.length - 1}__');
					} catch (err:Dynamic) {
						Context.error("Failed to parse interpolation: " + code, e.pos);
					}
					lastIndex = matchPos.pos + matchPos.len;
				}
				buf.addSub(s, lastIndex);
				return buf.toString();
			case EBinop(OpAdd, e1, e2):
				return flattenExpr(e1, exprs) + flattenExpr(e2, exprs);
			case EParenthesis(e1):
				return flattenExpr(e1, exprs);
			case ECheckType(e1, _):
				return flattenExpr(e1, exprs);
			case EMeta(meta, e1): // Handle :markup metadata
				if (meta.name == ":markup") {
					return flattenExpr(e1, exprs);
				}
				// Other meta?
				return flattenExpr(e1, exprs);
			case _:
				var id = exprs.length;
				exprs.push(e);
				return "__EXPR_" + id + "__";
		}
	}

	static function parseNode(xml:Xml, pos:Position, exprs:Array<Expr>):Expr {
		if (xml.nodeType == Xml.Element) {
			var tag = xml.nodeName;
			var propsFields:Array<ObjectField> = [];

			for (attr in xml.attributes()) {
				var val = xml.get(attr);
				var exprVal = resolvePlaceholders(val, pos, exprs);
				propsFields.push({field: attr, expr: exprVal});
			}

			var childrenExprs:Array<Expr> = [];
			for (child in xml) {
				if (child.nodeType == Xml.Element) {
					childrenExprs.push(parseNode(child, pos, exprs));
				} else if (child.nodeType == Xml.PCData || child.nodeType == Xml.CData) {
					var text = child.nodeValue;
					var parts = parseTextWithPlaceholders(text, pos, exprs);
					for (p in parts) {
						childrenExprs.push(p);
					}
				}
			}
			var childrenArr = macro $a{childrenExprs};
			var propsObj = {expr: EObjectDecl(propsFields), pos: pos};

			// Check if tag is dynamic
			if (tag.indexOf("__EXPR_") == 0) {
				var tagExpr = resolvePlaceholders(tag, pos, exprs);
				return macro rui.VirtualDom.VNode.c($tagExpr, $propsObj, $childrenArr);
			}

			var firstChar = tag.charAt(0);
			if (firstChar == firstChar.toUpperCase() && firstChar != firstChar.toLowerCase()) {
				return macro rui.VirtualDom.VNode.c($i{tag}, $propsObj, $childrenArr);
			} else {
				return macro rui.VirtualDom.VNode.h($v{tag}, $propsObj, $childrenArr);
			}
		} else {
			return macro null;
		}
	}

	static function resolvePlaceholders(text:String, pos:Position, exprs:Array<Expr>):Expr {
		var exactRegex = ~/^__EXPR_([0-9]+)__$/;
		if (exactRegex.match(text)) {
			var id = Std.parseInt(exactRegex.matched(1));
			return exprs[id];
		}

		// Check for brace interpolation: {expr}
		// This is needed if text comes from :markup string which has un-flattened braces.
		// We only parse brace if it looks like { ... } AND isn't part of bigger string?
		// Or do we treat { } as expression boundary?
		// User example: onclick={increment} -> text="{increment}" from XML parser?
		// Yes, if XML parser sees `onclick={increment}`, attribute value is `{increment}`.
		if (StringTools.startsWith(text, "{") && StringTools.endsWith(text, "}")) {
			// It might be a classic interpolation.
			var content = text.substring(1, text.length - 1);
			// Check if it's NOT an __EXPR_
			if (content.indexOf("__EXPR_") == -1) {
				try {
					return Context.parse(content, pos);
				} catch (e:Dynamic) {} // Fallthrough
			}
		}

		var parts:Array<Expr> = [];
		var start = 0;

		var mixedParts = parseMixedContent(text, pos, exprs);
		if (mixedParts.length == 0)
			return macro $v{""};
		if (mixedParts.length == 1)
			return mixedParts[0];

		// Concatenate for attributes
		var res = mixedParts[0];
		for (k in 1...mixedParts.length) {
			res = macro $res + ${mixedParts[k]};
		}
		return res;
	}

	static function parseTextWithPlaceholders(text:String, pos:Position, exprs:Array<Expr>):Array<Expr> {
		return parseMixedContent(text, pos, exprs);
	}

	static function parseMixedContent(text:String, pos:Position, exprs:Array<Expr>):Array<Expr> {
		var parts:Array<Expr> = [];
		var len = text.length;
		var i = 0;
		var buf = new StringBuf();

		while (i < len) {
			// Check for __EXPR_
			if (text.substr(i, 7) == "__EXPR_") {
				// extract ID
				var remainder = text.substr(i + 7);
				var end = remainder.indexOf("__");
				if (end != -1) {
					if (buf.length > 0) {
						parts.push(macro $v{buf.toString()});
						buf = new StringBuf();
					}
					var idStr = remainder.substring(0, end);
					var id = Std.parseInt(idStr);
					parts.push(exprs[id]);
					i += 7 + end + 2;
					continue;
				}
			}

			// Check for {
			if (text.charAt(i) == "{") {
				// Find closing }
				// Warning: braces nesting?
				// Simple greedy scan for now or recursive counting?
				// Code block in { } is valid Haxe.
				var depth = 1;
				var j = i + 1;
				while (j < len && depth > 0) {
					if (text.charAt(j) == "{")
						depth++;
					else if (text.charAt(j) == "}")
						depth--;
					j++;
				}

				if (depth == 0) {
					// Found block
					if (buf.length > 0) {
						parts.push(macro $v{buf.toString()});
						buf = new StringBuf();
					}
					var content = text.substring(i + 1, j - 1);
					try {
						var parsed = Context.parse(content, pos);
						parts.push(parsed);
						i = j;
						continue;
					} catch (e:Dynamic) {
						// Not valid expr, treat as string
					}
				}
			}

			buf.addChar(text.charCodeAt(i));
			i++;
		}

		if (buf.length > 0)
			parts.push(macro $v{buf.toString()});

		return parts;
	}

	static function sanitizeJsx(str:String):String {
		var buf = new StringBuf();
		var i = 0;
		var len = str.length;

		while (i < len) {
			// fast forward to '='
			var nextEq = str.indexOf("=", i);
			if (nextEq == -1) {
				buf.addSub(str, i, len - i);
				break;
			}

			buf.addSub(str, i, nextEq - i + 1); // include '='
			i = nextEq + 1;

			// Skip whitespace
			while (i < len && (str.charCodeAt(i) == 32 || str.charCodeAt(i) == 9 || str.charCodeAt(i) == 10 || str.charCodeAt(i) == 13)) {
				buf.addChar(str.charCodeAt(i));
				i++;
			}

			if (i < len && str.charAt(i) == "{") {
				// JSX attribute detected!
				buf.addChar(34); // "

				// Find matching }
				var depth = 1;
				var start = i;
				i++;
				while (i < len && depth > 0) {
					if (str.charAt(i) == "{")
						depth++;
					else if (str.charAt(i) == "}")
						depth--;
					if (depth > 0)
						i++;
				}

				// i is now at closing } (or out of bounds)
				if (depth == 0) {
					// Add content including braces
					buf.addSub(str, start, i - start + 1);
					buf.addChar(34); // "
					i++;
				} else {
					// Malformed? Just add what we found
					buf.addSub(str, start, i - start);
				}
			}
		}
		return buf.toString();
	}

	static function checkImmutable(t:ComplexType, pos:Position) {
		try {
			// trace("Checking immutability for: " + t);
			var type = Context.resolveType(t, pos);
			// trace("Resolved type: " + type);
			checkType(type, pos);
		} catch (e:Dynamic) {
			Context.warning("Could not fully resolve type for immutability check: " + e, pos);
		}
	}

	static function checkType(t:haxe.macro.Type, pos:Position) {
		switch (t) {
			case TInst(ref, params):
				var cls = ref.get();
				var name = cls.name;
				var pack = cls.pack.join(".");
				var fullName = (pack.length > 0 ? pack + "." : "") + name;

				// 0. Allow Observables
				for (i in cls.interfaces) {
					var iName = i.t.toString();
					if (iName == "rui.Observable") {
						return;
					}
				}

				// 1. Blacklist mutable containers
				if (fullName == "Array" || fullName == "Map" || fullName == "List" || fullName == "haxe.ds.List" || fullName == "haxe.ds.HashMap") {
					Context.error("State fields cannot be mutable container '" + fullName + "'. Use ImmutableList or other immutable structures.", pos);
					return;
				}

				// 2. Whitelist known immutable types (basic types handled by defaults, but String is class)
				if (fullName == "String" || fullName == "rui.structures.ImmutableList") {
					// Check params if any
					for (p in params)
						checkType(p, pos);
					return;
				}

				// 3. Deep check custom classes
				// Check all PUBLIC fields. If any is mutable, error.
				// We assume private fields are internal implementation details (e.g. ImmutableList has _data array).
				// We only care about public interface immutability.
				var fields = cls.fields.get();
				for (f in fields) {
					if (f.isPublic) {
						// trace("Checking field: " + f.name + " isPublic: " + f.isPublic + " Kind: " + f.kind);
						if (!isFieldImmutable(f)) {
							Context.error("State object '" + fullName + "' has mutable public field '" + f.name
								+ "'. All public fields must be final or read-only.",
								pos);
						}
						// Recurse on field type?
						// Yes, strict deep immutability.
						checkType(f.type, pos);
					}
				}

				// Also check params
				for (p in params)
					checkType(p, pos);

			case TType(ref, params):
				// Typedef: resolve and recurse
				checkType(ref.get().type, pos);
				for (p in params)
					checkType(p, pos);

			case TAnonymous(ref):
				// Structure like { x: Int }
				var fields = ref.get().fields;
				for (f in fields) {
					if (!isFieldImmutable(f)) {
						Context.error("State structure has mutable field '" + f.name + "'. Fields must be final (e.g. { final x: Int; }).", pos);
					}
					checkType(f.type, pos);
				}

			case TAbstract(ref, params):
				// Abstract (like Int, Bool, Float are abstracts in Haxe usually, or handled specially)
				// If it's a core type, it's usually immutable by value semantics.
				var abs = ref.get();
				// Check underlying type if implicit cast?
				// Mostly just check params.
				for (p in params)
					checkType(p, pos);

			case TLazy(f):
				checkType(f(), pos);

			case _:
				// TDynamic, TFun, TEnum usually safe or accepted?
				// TFun (functions) are immutable.
				// TEnum is immutable values.
		}
	}

	static function isFieldImmutable(f:haxe.macro.Type.ClassField):Bool {
		// Check if final
		if (f.kind.match(FVar(AccNormal, AccNormal))) {
			// var x : Int; <- Mutable
			return false;
		}
		if (f.kind.match(FVar(AccNo, AccNo))) {
			// Physical field but no access?
			return true;
		}
		// Check for (default, null) or (get, never)
		// FVar(read, write)
		switch (f.kind) {
			case FVar(read, write):
				if (write == AccNormal || write == AccCall)
					return false;
			// If write is AccNo, AccNever, AccCtor, it's immutable
			case FMethod(_):
				// Methods are fine
		}

		// Also check @:final? Haxe macros don't always expose 'final' keyword as specific kind,
		// it often manifests as write=AccNever or isFinal property.
		if (f.isFinal)
			return true;

		// If it's a variable and we can write to it, it's not immutable.
		// Haxe 4 'final' fields usually appear as isFinal=true.
		return true;
	}
	#end
}
