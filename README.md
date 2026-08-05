# rui — Reactive core for La Pavoiserie

The fine-grained reactive core shared by the La Pavoiserie UI libraries
(`sui`, `aui`, `wui`, `cui`, `qui`) and by `mui`, the layer that unifies them.
Extracted from `epikframework`'s `epikDX`.

Target-agnostic and dependency-free: it holds *state* and *change propagation*,
nothing else. Rendering belongs to each platform library.

- **`Signal<T>` / `Effect` / `Scheduler`** — fine-grained reactivity: reading a
  signal inside an effect tracks it as a dependency; only dependent effects
  re-run (batched) when it changes.
- **`Observable` (`@:autoBuild ObservableMacro`)** — model classes get reactive
  fields (`uuid`, subscribe/onPropChange). Use `implements Observable` **alone**:
  its `@:autoBuild` runs the macro, and adding `@:build` on top runs it twice.
- **`structures.ImmutableList<T>`** — persistent list (`push`/`filter`/`map`
  return a new instance), so changes are detectable by reference.

Note that `Effect` lives in the `rui.Signal` module — `import rui.Signal;`
brings both.

**Documentation:** `docs/` (docsify — serve it with `docsify serve docs`, or any
static server).

## Usage

```haxe
var count = new Signal(0);
new Effect(() -> trace("count = " + count.value)); // runs now, and on change
count.value = 1;                                   // re-runs the effect
```

A platform library wires this to its own rendering: `qui` (Sailfish/Qt-Silica)
gives each reactive binding its own `Effect`, so a signal write re-applies just
that binding instead of re-rendering a tree.

## Scope

Only the reactive core is published here. The virtual-DOM half of the original
epikDX extraction (`VirtualDom`, `Component`, `Macro`, `DomRenderer`, `UI`,
`StyleManager`) and its networking layer were removed: nothing consumed them,
and the component macro was still hard-wired to `epikowa.epikUI`. A shared
render model, if it comes, will be designed against the real needs of the
backends rather than inherited. The removed code stays in this repository's
history.

## Status

Used by `qui` and validated on a Sailfish device: signals, effects and immutable
lists drive native Silica widgets under the CPPIA interpreter.

`Scheduler` flushes synchronously outside JS (a choice inherited from the TUI
target, so as not to block on blocking reads); that suits imperative targets,
but revisit it before driving one that can re-enter from a native callback.

`test/Check.hx` type-checks and runs the core standalone:

```bash
haxe -cp src -cp test -main Check --interp
```

## License

MIT.
