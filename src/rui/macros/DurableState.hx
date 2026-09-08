package rui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/** What one `@:state(durable)` / `@:state(shared(Party))` field asked for. **/
typedef DurableRequest = {
	/** The store key. The field's own name, prefixed by its class, unless
		`key = "..."` named one. **/
	var key:String;

	/** The `rui.state.Durable.DurableKind` constructor, by name. **/
	var kind:String;

	/** Whether the cell is backed by the device store. **/
	var durable:Bool;

	/** The party that owns the cell, when it is shared; `null` otherwise.
		The wire identifies the cell by the field's own name. **/
	var shared:Null<String>;
}
#end

/**
	The `durable` half of `@:state`, in one place for six macros.

	Every backend builds its own `@:state` fields — six independent macros, each
	with its own constructor-ordering rules learned the hard way. None of that is
	worth duplicating a seventh time, and none of it needs to change: this
	returns two expressions, and each macro drops them where it was already
	emitting.

	```haxe
	@:state(durable) var count:Int = 0;
	@:state(durable, key = "score") var count:Int = 0;
	@:state(shared(Watch)) var steps:Int = 0;          // one owner per cell
	@:state(shared(Phone), durable) var goal:Int = 0;  // both: the owner keeps it
	```

	`shared(Party)` rides the same request, so the six macros that already
	emit `hydrate` and `bindCall` for `durable` get sharing without a line
	changed: the bind statement carries both binds when both were asked.
	The rule behind a shared cell is `rui.state.Shared`.

	## Why this is in `rui` and names neither `mui` nor `kui`

	It sits under six `StateMacro`s, and those run in builds that have neither.
	`cui` compiles its own examples with `-lib rui -lib nui` and nothing else
	(`cui/build-counter.hxml`), so a reference to `mui.macros.*` here would break
	a plain terminal application that never asked for a surface. `rui` is the one
	library every backend already depends on, and the durable cell it drives
	(`rui.state.Durable`) lives beside it.

	The store's *existence* is a `kui` fact, and this reads it as a define rather
	than by calling `kui.macros.Host`: a backend's `registerWithKui()` publishes
	`kui_platform`, so the platform id is available to any macro without putting
	a capability library underneath the reactive core.

	## Why the default value is wrapped rather than corrected afterwards

	`hydrate` wraps the field's **default expression**, so the cell is
	constructed with what the store holds. Writing the stored value in after
	construction would look equivalent and is not: several backends mirror the
	initial value into their platform as they build the cell — `sui` pushes it to
	Swift, `aui` writes a Compose `MutableState` — so a cell corrected afterwards
	leaves the platform showing the default while Haxe holds the stored value.
	The application would disagree with its own screen at launch.

	Wrapping also means the bind statement rides in the same list of constructor
	initialisers each macro already emits, so **no macro's ordering logic is
	touched** — including `aui`'s careful injection after `super()`, which has a
	documented JVM failure behind it.
**/
class DurableState {
	#if macro

	/**
		What this field asked for, or `null` when it is an ordinary `@:state`.

		Refuses, at the field's own position: an unknown parameter, a type that
		cannot be stored, and a build with no store. All three are knowable here,
		and this house does not let a knowable thing become a surprise at
		runtime — a cell that silently stopped persisting on one platform is
		exactly the kind of quiet that costs a user their data.

		`meta` is the `@:state` entry itself and `type` the field's **declared**
		type, both passed rather than read back off the field. Three backends
		strip the metadata and every one of them replaces the type with
		`State<T>` — pui and qui do it before this could look — so a helper that
		went digging would be right in three macros and wrong in three others,
		depending on where in each it happened to be called. Handing it what the
		caller already holds makes the call order stop mattering.
	**/
	public static function requestOf(field:Field, meta:MetadataEntry, type:Null<ComplexType>):Null<DurableRequest> {
		if (meta.params == null || meta.params.length == 0)
			return null;

		var durable = false;
		var shared:Null<String> = null;
		var key:Null<String> = null;
		for (p in meta.params) {
			switch (p.expr) {
				case EConst(CIdent("durable")):
					durable = true;
				case ECall({expr: EConst(CIdent("shared"))}, [{expr: EConst(CIdent(party))}]):
					shared = party;
				case ECall({expr: EConst(CIdent("shared"))}, _):
					Context.error("@:state(shared(Party)) names ONE party, the cell's owner — an identifier, like `Phone`.", p.pos);
				case EBinop(OpAssign, {expr: EConst(CIdent("key"))}, {expr: EConst(CString(k, _))}):
					key = k;
				case _:
					Context.error("@:state takes `durable`, `shared(Party)`, and optionally `key = \"...\"` — nothing else.", p.pos);
			}
		}
		if (!durable && shared == null) {
			if (key != null)
				Context.error("@:state(key = \"...\") only means something with `durable`.", meta.pos);
			return null;
		}

		var kind = kindOf(field, type, durable ? "durable" : "shared(" + shared + ")");
		if (kind == null)
			return null; // kindOf has already reported it

		if (durable)
			requireStore(field);
		if (shared != null)
			requireCarry(field, shared);

		var owner = Context.getLocalClass();
		var prefix = owner == null ? "" : owner.get().name + ".";
		return {key: key != null ? key : prefix + field.name, kind: kind, durable: durable, shared: shared};
	}

	/** The default expression, replaced by "what the store holds, or this"
		— for a durable cell; a merely shared one is born from its default. **/
	public static function hydrate(req:DurableRequest, defaultExpr:Expr):Expr {
		if (!req.durable)
			return defaultExpr;
		var kind = kindExpr(req.kind, defaultExpr.pos);
		return macro rui.state.Durable.initial($v{req.key}, $kind, $defaultExpr);
	}

	/**
		The statement that makes the cell write through, and be rehydrated.

		Emitted **after** the cell exists, in the same list of initialisers the
		calling macro already builds. `owner` is how that macro refers to the
		instance being constructed — `macro this` everywhere so far.
	**/
	public static function bindCall(req:DurableRequest, owner:Expr, fieldName:String, pos:Position):Expr {
		var kind = kindExpr(req.kind, pos);
		var cell = {expr: EField(owner, fieldName), pos: pos};
		var binds:Array<Expr> = [];
		if (req.durable)
			binds.push(macro rui.state.Durable.bind($cell, $v{req.key}, $kind));
		if (req.shared != null) {
			// Identified by the field's own name on the wire: both ends
			// compile the same class, and the class prefix would only say
			// what they both already know.
			var wireName = fieldName;
			if (StringTools.endsWith(wireName, "_"))
				wireName = wireName.substr(0, wireName.length - 1);
			binds.push(macro rui.state.Shared.bind($cell, $v{wireName}, $kind, $v{req.shared}));
		}
		return binds.length == 1 ? binds[0] : macro $b{binds};
	}

	/**
		Whether this build has a device store at all.

		A compile-time fact, used by `mui.state.Durable.install` to expand to
		nothing rather than fail a build that asked for no durable cell.
	**/
	public static function hasStore():Bool {
		var platform = Context.definedValue("kui_platform");
		if (platform == null)
			return false;
		return try {
			Context.getType("store.platform." + platform + ".Store");
			true;
		} catch (_:Dynamic) false;
	}

	// -- refusals -----------------------------------------------------------

	static function kindOf(field:Field, type:Null<ComplexType>, asked:String):Null<String> {
		var name = switch (type) {
			case TPath({pack: [], name: n}): n;
			case _: null;
		}
		return switch (name) {
			case "Int": "KInt";
			case "Float": "KFloat";
			case "Bool": "KBool";
			case "String": "KString";
			case _:
				Context.error('@:state($asked) carries Int, Float, Bool or String, and "${field.name}" is '
					+ (name == null ? "none of them" : name) + ".\n"
					+ "  A reference type mutated in place compares equal to itself, so its write never\n"
					+ "  reaches the store or the wire, and what the other side shows goes quietly stale.\n"
					+ "  Carry what you can name.", field.pos);
				null;
		}
	}

	/**
		A shared cell leaves the device, which is the concern `-D mui_carry`
		gates for a Companion surface — the same concern, so the same word.
		`mui_cafos` is the older spelling and still opens the gate.
	**/
	static function requireCarry(field:Field, party:String):Void {
		if (Context.defined("mui_carry") || Context.defined("mui_cafos"))
			return;
		Context.error('@:state(shared($party)) sends "${field.name}" off this device — to a machine on the network,\n'
			+ "  or to a paired wearable — and that is off in this build.\n"
			+ "  Turn it on with -D mui_carry (plus dui and a transport), or drop `shared` and keep the cell here.\n"
			+ "  Refused rather than ignored: a cell that silently stopped crossing is a device that lies.", field.pos);
	}

	static function requireStore(field:Field):Void {
		if (hasStore())
			return;

		var platform = Context.definedValue("kui_platform");
		var tail = "  Refused here rather than ignored: a durable cell that silently stopped persisting\n"
			+ "  costs a user their data, and this is knowable now.";

		if (platform == null) {
			Context.error("@:state(durable) needs a device store, and this build declares no platform.\n"
				+ "  A backend declares one from its build file, e.g.\n"
				+ "    --macro cui.kui.Platform.registerWithKui()\n"
				+ '  which `mui init` writes for you. Or drop `durable` from "${field.name}".\n' + tail, field.pos);
			return;
		}

		Context.error('@:state(durable) needs a device store, and this build targets "$platform",\n'
			+ '  for which store.platform.$platform.Store does not exist.\n'
			+ "  Add -lib kui-store if it is missing; write that platform's implementation if it is not;\n"
			+ '  or drop `durable` from "${field.name}" and keep the cell in memory.\n' + tail, field.pos);
	}

	static function kindExpr(kind:String, pos:Position):Expr
		return {expr: EField(macro rui.state.Durable.DurableKind, kind), pos: pos};
	#end
}
