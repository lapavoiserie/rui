package rui;

import haxe.macro.Context;
import haxe.macro.Expr;

class ObservableMacro {
	public static function build():Array<Field> {
		#if macro
		// trace("ObservableMacro: Running build for " + haxe.macro.Context.getLocalClass().toString());
		var fields = Context.getBuildFields();
		var newFields:Array<Field> = [];

		var pos = Context.currentPos();

		// Check if already implements Observable
		// (Actually, the build macro runs before interface check usually, but we inject the fields anyway)

		// 0. Inject uuid
		newFields.push({
			name: "__uuid",
			access: [APrivate],
			kind: FVar(macro :String, null),
			pos: pos
		});

		newFields.push({
			name: "get_uuid",
			access: [APublic],
			kind: FFun({
				args: [],
				ret: macro :String,
				expr: macro {
					if (__uuid == null) {
						// Simple random UUID v4-like generation
						var chars = "0123456789abcdef";
						var s = [];
						for (i in 0...36) {
							if (i == 8 || i == 13 || i == 18 || i == 23) {
								s.push("-");
							} else if (i == 14) {
								s.push("4");
							} else {
								var r = Std.random(16);
								if (i == 19)
									r = (r & 0x3) | 0x8;
								s.push(chars.charAt(r));
							}
						}
						__uuid = s.join("");
					}
					return __uuid;
				}
			}),
			pos: pos
		});

		newFields.push({
			name: "uuid",
			access: [APublic],
			kind: FProp("get", "never", macro :String),
			pos: pos
		});

		// 1. Inject listeners array
		newFields.push({
			name: "__listeners",
			access: [APrivate],
			kind: FVar(macro :Array<Void->Void>, macro []),
			pos: pos
		});

		newFields.push({
			name: "__propListeners",
			access: [APrivate],
			kind: FVar(macro :Array<(String, Dynamic) -> Void>, macro []),
			pos: pos
		});

		// 2. Inject subscribe
		newFields.push({
			name: "subscribe",
			access: [APublic],
			kind: FFun({
				args: [{name: "listener", type: macro :Void->Void}],
				ret: macro :Void,
				expr: macro {
					if (listener != null)
						__listeners.push(listener);
				}
			}),
			pos: pos
		});

		// 3. Inject unsubscribe
		newFields.push({
			name: "unsubscribe",
			access: [APublic],
			kind: FFun({
				args: [{name: "listener", type: macro :Void->Void}],
				ret: macro :Void,
				expr: macro {
					__listeners.remove(listener);
				}
			}),
			pos: pos
		});

		// Inject onPropChange
		newFields.push({
			name: "onPropChange",
			access: [APublic],
			kind: FFun({
				args: [{name: "listener", type: macro :(String, Dynamic) -> Void}],
				ret: macro :Void,
				expr: macro {
					if (listener != null)
						__propListeners.push(listener);
				}
			}),
			pos: pos
		});

		// 4. Inject notifyListeners
		newFields.push({
			name: "notifyListeners",
			access: [APrivate],
			kind: FFun({
				args: [],
				ret: macro :Void,
				expr: macro {
					for (l in __listeners)
						l();
				}
			}),
			pos: pos
		});

		newFields.push({
			name: "notifyPropListeners",
			access: [APrivate],
			kind: FFun({
				args: [{name: "prop", type: macro :String}, {name: "val", type: macro :Dynamic}],
				ret: macro :Void,
				expr: macro {
					for (l in __propListeners)
						l(prop, val);
				}
			}),
			pos: pos
		});

		// 5. Convert vars to properties
		for (field in fields) {
			// Skip functions and static fields
			if (field.access != null && field.access.contains(AStatic))
				continue;

			switch (field.kind) {
				case FVar(t, e):
					// It's a variable. Convert to (default, set) property with @:isVar

					// Add @:isVar metadata
					if (field.meta == null)
						field.meta = [];
					field.meta.push({name: ":isVar", pos: field.pos});

					// Change original to property
					field.kind = FProp("default", "set", t, e);

					// We do NOT need a backing field, @:isVar handles it.
					// We do NOT need a getter, 'default' handles it.

					// Setter
					var fieldName = field.name;
					newFields.push({
						name: "set_" + field.name,
						access: [APublic], // Setter PUBLIC for better Reflection support
						kind: FFun({
							args: [{name: "v", type: t}],
							ret: t,
							expr: macro {
								if ($i{fieldName} != v) {
									$i{fieldName} = v;
									notifyListeners();
									notifyPropListeners($v{fieldName}, v);
								}
								return v;
							}
						}),
						pos: field.pos
					});

				case _:
					// Ignore methods/props
			}
		}

		return fields.concat(newFields);
		#else
		return null;
		#end
	}
}
