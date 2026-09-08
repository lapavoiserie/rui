package rui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	The property half of `@:state`, in one place for six macros.

	```haxe
	@:state var count:Int = 0;

	count += 1;                 // writes the cell, which notifies
	new Text('$count');         // reads the cell, which subscribes
	Toggle("dark", dark_);      // the CELL itself, for a control that binds
	count_.peek();              // an untracked read, said out loud
	```

	## What the field becomes

	Two fields where there was one. The **cell** keeps the reactive object —
	the backend's `State<T>` — under the field's name with a trailing
	underscore: `count_`. The **property** takes the field's own name and its
	declared type, and does nothing but forward: `get_count()` is
	`count_.get()`, so a read still subscribes; `set_count(v)` is
	`count_.set(v)`, so a write still notifies, still reaches the platform
	sink, still reaches the durable one. Nothing about *when* anything happens
	moved. Only the spelling did.

	## Why a trailing underscore, and not a sigil

	A control that binds — a toggle, a text field, a slider — needs the cell,
	not its value; so does anything that attaches to it, like the durable
	store. Swift writes `$dark` for that. Haxe has no `$` in an identifier, so
	the cell is one character away from its value: `dark_`. Visible enough to
	read as "the cell of", short enough not to be typed with a sigh, and a
	naming convention rather than a second macro to learn.

	## What the view rule needs to know

	The property is typed `Int`, and `rui.macros.ViewRule` judges a view by
	what it reads: a plain mutable field is refused because nothing can tell
	the view when it changes. This one can — its getter subscribes — and the
	rule cannot see that from the type. So the property carries
	`@:stateProperty`, and the rule accepts a field that says so. The metadata
	is the whole contract between the two: a macro that generated a property
	without it would be refused, correctly.

	## Why this lives in `rui`

	Under the same argument as `DurableState` beside it: six independent
	macros build `@:state` fields, and `rui` is the one library every one of
	them already depends on. Each backend keeps its own constructor-ordering
	rules and its own `State` subclass; this returns fields, and each macro
	pushes them where it was already pushing one.
**/
class StateProperty {
	#if macro
	/** The name of the cell behind a `@:state` field: the field's own, with a
		trailing underscore. One place, so a backend that needs it -- to bind
		a durable store, to qualify a reference -- spells it the same way. **/
	public static inline function cellName(fieldName:String):String
		return fieldName + "_";

	/**
		The fields that replace `field`.

		`declared` is the type the application wrote (`Int`), `cellType` the
		backend's cell for it (`aui.state.State<Int>`). The property keeps the
		field's access, position and documentation; the cell is public, because
		bindings pass it, and documented as what it is.

		The cell has no initialiser: every backend constructs it in the
		constructor for reasons of its own, and this does not get in the way.
	**/
	public static function split(field:Field, declared:ComplexType, cellType:ComplexType):Array<Field> {
		var name = field.name;
		var cell = cellName(name);
		var pos = field.pos;

		var cellField:Field = {
			name: cell,
			access: [APublic],
			kind: FVar(cellType, null),
			pos: pos,
			meta: [{name: ":stateCell", params: [macro $v{name}], pos: pos}],
			doc: 'The cell behind `$name`: pass this where a control binds, or for `peek()`.',
		};

		var property:Field = {
			name: name,
			access: field.access,
			kind: FProp("get", "set", declared, null),
			pos: pos,
			meta: [{name: ":stateProperty", params: [], pos: pos}],
			doc: field.doc,
		};

		var getter:Field = {
			name: "get_" + name,
			access: [APrivate],
			kind: FFun({
				args: [],
				ret: declared,
				expr: macro return this.$cell.get(),
			}),
			pos: pos,
			meta: [{name: ":noCompletion", params: [], pos: pos}],
		};

		var setter:Field = {
			name: "set_" + name,
			access: [APrivate],
			kind: FFun({
				args: [{name: "v", type: declared}],
				ret: declared,
				expr: macro {
					this.$cell.set(v);
					return v;
				},
			}),
			pos: pos,
			meta: [{name: ":noCompletion", params: [], pos: pos}],
		};

		return [cellField, property, getter, setter];
	}
	#end
}
