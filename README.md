# rui — Reactive UI core for La Pavoiserie

Fine-grained reactive core shared by the La Pavoiserie UI backends
(`sui`, `aui`, `wui`, `cui`, `qui`). Extracted from `epikframework`'s `epikDX`.

- **`Signal<T>` / `Effect` / `Scheduler`** — fine-grained reactivity: reading a
  signal inside an effect tracks it as a dependency; only dependent effects
  re-run (batched) when it changes.
- **`Observable` (`@:autoBuild ObservableMacro`)** — model classes get reactive
  fields (`uuid`, subscribe/onPropChange). Use `implements Observable`.
- **`structures.ImmutableList<T>`** — persistent list (`push/filter/map` return a
  new instance), so changes are detected by reference.
- **`Component<T>` + `Macro`** — `@:state` fields become `Signal`s; `render():VNode`.
- **`VirtualDom` + `Renderer`** — VNode tree with a pluggable per-target
  `NativeNode` + renderer. `DomRenderer` (js) is the reference target.

## Targets

`NativeNode`/`Renderer` dispatch per target (`#if js` → DOM). Each platform lib
(e.g. `qui` for Sailfish/Silica) plugs in its own `NativeNode` + renderer,
selected by a `-D rui_target=…` define.

## Status / TODO

- Extracted from epikDX; the target-agnostic core type-checks and runs standalone.
- `Macro.hx`'s element-name resolution still points at `epikowa.epikUI.*` — to be
  made target-neutral (the `qui` authoring path uses its own Jsx instead).
- Reference `TuiRenderer` was dropped (depended on the external `epikowa.tui`).
