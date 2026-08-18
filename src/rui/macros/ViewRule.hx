package rui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.Tools;
#end

/**
	**A view may only read things that are immutable or observable.**

	The rule MVCoconut is built on, checked here rather than hoped for.

	## Why it is a rule and not advice

	A view is a function of state, and the framework re-runs it when that state
	changes. It can only do that for state it can *observe*. A view that reads a
	plain mutable field is not wrong-looking — it compiles, it renders once, and
	it then goes quietly stale, because nothing can tell it to run again.

	That is exactly what happened here before this check existed: an example read
	a plain `static var`, nothing could observe it, and the gap was filled by
	calling the backend's `rerenderNui()` by hand — framework plumbing in
	application code, on a backend the application is not supposed to name. The
	symptom was a manual call; the cause was a view depending on something
	unobservable.

	## What counts

	- **Observable** — `rui.state.State<T>`, or anything implementing
	  `rui.Observable`. A write notifies, so the view can re-run.
	- **Immutable** — a `final` field, or a persistent structure like
	  `rui.structures.ImmutableList`. It cannot change under the view, so there
	  is nothing to observe.
	- **Local** — a variable or parameter inside the view. It is recomputed on
	  every run by definition.

	Anything else is a compile error naming the field.

	## What this does not check

	Mutation *through* an observable: `state.value.push(x)` changes an array in
	place, notifies nobody, and reads as a legal observable access. That is what
	`ImmutableList` is for — a structure whose `push` returns a new list makes
	the mistake unwriteable rather than merely detectable.
**/
class ViewRule {
	#if macro
	static var registered = false;

	/**
		Add to build.hxml, naming the app base class and its view method:

		```
		--macro rui.macros.ViewRule.register("mui.App", "view")
		--macro rui.macros.ViewRule.register("cui.App", "body")
		```

		It lives here because **every backend has views** and none of them may
		import `mui` -- so a rule about views could not be adopted by a second
		backend from there. It is also where it belongs on its own terms: the rule
		is about state, not about nodes, and `rui` owns `Observable` and
		`ImmutableList`, the two things it accepts.
	**/
	static var targets:Array<{name:String, pack:String, method:String, rawCells:Bool}> = [];

	/**
		Register a base class whose subclasses' views the rule judges.

		Call it with the **real** class path — the backend's own `pui.mui.App` —
		never an alias. `mui.App` is a macro-made alias since the binding
		inversion, and it fails to resolve from `onAfterTyping`, so a literal
		pack/name match against it matches nothing: the rule silently stopped
		checking every mui application, found when a raw-Signal witness that
		should have failed compiled clean. `mui.macros.Bind` passes the resolved
		backend base itself; stale `register("mui.App", …)` lines in old build
		files are harmless — they simply never match.

		May be called several times; each target is checked.

		`rawCells` additionally refuses reading a raw `rui.Signal` or
		`rui.state.State` in the view. Pass `true` for a portable surface --
		`mui.macros.Bind` does -- where the application cannot know whether the
		backend underneath rebuilds from a dirty flag. Leave it off for a
		backend author's own App: they wire the platform sink themselves, and a
		raw cell in their hands is the documented idiom.
	**/
	public static function register(appType:String, viewMethod:String, rawCells = false):Void {
		var pack = appType.split(".");
		var name = pack.pop();
		targets.push({name: name, pack: pack.join("."), method: viewMethod, rawCells: rawCells});
		if (registered) return;
		registered = true;

		Context.onAfterTyping(function(types:Array<ModuleType>) {
			for (mt in types) {
				switch (mt) {
					case TClassDecl(ref):
						var cls = ref.get();
						if (isFramework(cls)) continue;
						for (t in targets)
							if (isApp(cls, t.name, t.pack)) {
								checkView(cls, t.method, t.rawCells);
								break;
							}
					default:
				}
			}
		});
	}

	static function isApp(cls:ClassType, appName:String, appPack:String):Bool {
		var current = cls.superClass == null ? null : cls.superClass.t.get();
		while (current != null) {
			if (current.name == appName && current.pack.join(".") == appPack) return true;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return false;
	}

	/**
		The framework's own classes.

		Kept apart from `isLibrary` on purpose: an app class usually sits in the
		root package, and so does `Array`. One predicate answering both questions
		either excused the app's own fields or accused the standard library --
		both of which happened before the two were separated.
	**/
	static function isFramework(cls:ClassType):Bool {
		var root = cls.pack.length == 0 ? "" : cls.pack[0];
		return switch (root) {
			case "rui" | "nui" | "mui" | "wui" | "cui" | "sui" | "aui" | "qui" | "pui" | "kui": true;
			case _: false;
		};
	}

	/**
		Code the application did not write, and is not answerable for.

		The standard library counts: `Array.length` is a mutable field, and
		reading it flagged every view that measured a list -- pointing at
		`Array.hx` in the Haxe distribution rather than at the app. What matters
		is the *collection* the view read, which is judged on its own.
	**/
	static function isLibrary(cls:ClassType):Bool {
		var root = cls.pack.length == 0 ? "" : cls.pack[0];

		return switch (root) {
			// The framework.
			case "rui" | "nui" | "mui" | "wui" | "cui" | "sui" | "aui" | "qui" | "pui" | "kui": true;
			// The standard library and the targets. Top-level types -- Array,
			// String, Math -- have no package at all.
			case "" | "haxe" | "sys" | "cpp" | "js" | "python" | "neko" | "php" | "lua" | "eval": true;
			case _: false;
		};
	}

	static function checkView(cls:ClassType, viewMethod:String, rawCells:Bool):Void {
		for (field in cls.fields.get()) {
			if (field.name != viewMethod) continue;
			var e = field.expr();
			if (e != null) walk(e, cls, rawCells);
		}
	}

	static function walk(e:TypedExpr, owner:ClassType, rawCells:Bool):Void {
		if (e == null) return;

		// An **action** is not a view.
		//
		// A closure written inside `body()` but returning `Void` is a command --
		// a Button's handler -- and it runs on an event, long after the view was
		// built. What it reads cannot be something the display depends on, so
		// judging it accuses code that is doing nothing wrong. `sui`'s
		// dynamic-hello was the case: a tap counter incremented in a handler and
		// only ever printed.
		//
		// A closure that *returns* something is the other kind -- a view builder
		// (`ForEach(items, item -> new Text(item))`) -- and it runs as part of
		// rendering, so it is judged like the rest of the view.
		//
		// This narrows where the rule looks, never what it accepts: a read at
		// event time cannot be a view dependency, and the same field read by the
		// view itself is still caught, right where it is read.
		switch (e.expr) {
			case TFunction(fn) if (isVoid(fn.t)):
				return;
			case _:
		}

		if (rawCells) switch (e.expr) {
			// A raw reactive cell, read where only a backend's own state counts.
			//
			// `rui.Signal` and `rui.state.State` notify their *subscribers* --
			// and on the backends that rebuild from their own dirty flag (`cui`,
			// `pui`), nothing subscribes the tree to them. The read compiles,
			// the value is right, and the screen quietly never updates: paid for
			// on a device, as an application that answered on stderr and never
			// redrew. The exact classes only -- their backend subclasses are
			// what `@:state` produces, and those carry the platform sink.
			case TField(o, _):
				switch (haxe.macro.TypeTools.follow(o.t)) {
					case TInst(c, _) if (c.toString() == "rui.Signal" || c.toString() == "rui.state.State"):
						var cell = switch (o.expr) {
							case TLocal(v): v.name;
							case TField(_, fa): fieldOf(fa) == null ? "it" : fieldOf(fa).name;
							case _: "it";
						};
						Context.error('A view may not read a raw ${c.toString()}.\n'
							+ '  "$cell" notifies its subscribers, and on backends that rebuild from\n'
							+ '  their own dirty flag nothing subscribes the tree: the screen would\n'
							+ '  quietly never update. Declare "$cell" @:state instead.', e.pos);
					case _:
				}
			case _:
		}

		switch (e.expr) {
			// A field *read*. A call through a field is code, not state.
			case TField(_, fa):
				var cf = fieldOf(fa);
				if (cf != null && declaredBy(fa, owner) && !isCallable(cf)) {
					if (!acceptable(cf)) {
						Context.error('A view may only read what is immutable or observable.\n'
							+ '  "${cf.name}" is a plain mutable field, so nothing can tell the view\n'
							+ '  when it changes: what is on screen would quietly go stale.\n'
							+ '  Make it `final`, declare it @:state, or use ImmutableList.',
							cf.pos);
					}
				}
			case _:
		}

		e.iter(function(sub) walk(sub, owner, rawCells));
	}

	static function isVoid(t:Type):Bool {
		return switch (t.follow()) {
			case TAbstract(ref, _): ref.get().name == "Void" && ref.get().pack.length == 0;
			case _: false;
		};
	}

	static function fieldOf(fa:FieldAccess):Null<ClassField> {
		return switch (fa) {
			case FInstance(_, _, cf): cf.get();
			case FStatic(_, cf): cf.get();
			case FClosure(_, cf): cf.get();
			case _: null;
		};
	}

	/**
		Judge a field only if the app itself declares it.

		Not "is it outside the framework": an app class usually sits in the root
		package, and so does `Array` -- excluding the empty package to skip
		`Array.length` silently excused the very fields this rule exists for, and
		a view reading a mutable array compiled clean.

		Asking whether the *app* declares it answers both: `Array.length` belongs
		to `Array`, `todos` belongs to the app.
	**/
	static function declaredBy(fa:FieldAccess, owner:ClassType):Bool {
		var holder = switch (fa) {
			case FInstance(ref, _, _): ref.get();
			case FStatic(ref, _): ref.get();
			case FClosure(_, _): owner;
			case _: null;
		};
		if (holder == null) return false;

		var current = owner;
		while (current != null) {
			if (isFramework(current)) return false;
			if (current.name == holder.name && current.pack.join(".") == holder.pack.join(".")) return true;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return false;
	}

	static function isCallable(cf:ClassField):Bool {
		return switch (cf.type.follow()) {
			case TFun(_, _): true;
			case _: false;
		};
	}

	static function acceptable(cf:ClassField):Bool {
		if (cf.isFinal) return true;

		return switch (cf.type.follow()) {
			case TInst(ref, _): isReactive(ref.get());
			case _: false;
		};
	}

	/**
		Structural, not nominal.

		This first asked whether the class was *named* `State`, and refused
		`cui`'s perfectly good `IntState` -- a specialised subclass its `@:state`
		macro generates. Judging a type by its name is the same mistake this
		ecosystem removed from `qui`'s markup the same week: ask what it *is*.
	**/
	static function isReactive(cls:ClassType):Bool {
		var current = cls;
		while (current != null) {
			var path = current.pack.join(".") + "." + current.name;
			if (path == "rui.state.State") return true;
			if (path == "rui.structures.ImmutableList") return true;

			for (i in current.interfaces) {
				if (implementsObservable(i.t.get())) return true;
			}
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return false;
	}

	/** `rui.Observable`, or an interface extending it. **/
	static function implementsObservable(iface:ClassType):Bool {
		if (iface.pack.join(".") + "." + iface.name == "rui.Observable") return true;
		for (i in iface.interfaces) {
			if (implementsObservable(i.t.get())) return true;
		}
		return false;
	}
	#end
}
