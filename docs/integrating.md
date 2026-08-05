# Integrating rui

This page is for someone wiring rui into a UI library — a La Pavoiserie backend,
or anything else that renders.

## The contract

rui asks for nothing. It has no renderer interface to implement, no node type to
provide, no target define to set. A platform library uses it by **creating
effects that write to native widgets**:

```mermaid
graph LR
  W[app writes state] --> S[Signal]
  S --> E[Effect]
  E --> N[native widget setter]
```

That is the entire integration surface. What differs between backends is only
*how much* sits inside one effect.

## Choosing the granularity

**Coarse** — one effect around the whole view. A write re-runs the view function
and the result is diffed against the previous tree:

```haxe
new Effect(() -> {
    var tree = app.body();
    if (mounted) reconcile(tree) else mount(tree);
});
```

Simple, and it matches a declarative `body():View` contract where the app hands
back plain values. This is what `qui.App` does for the `mui`-shaped API.

**Fine** — one effect per reactive binding. A write re-applies exactly that one
property, with no tree walk and no diff:

```haxe
new Effect(() -> label.text = "Count: " + count.value);
```

`qui` does this for its own authoring syntax: each reactive property in the
markup becomes its own effect, and lists get an effect that re-reconciles only
themselves. On-device, adding an item re-runs the list's effect while the
surrounding view is never touched.

Both live side by side in one library — the granularity is a property of *how
the effects are created*, not of rui.

## Backing a `State<T>` with a signal

Most libraries expose their own state cell. Don't rewrite the wrapper — extend
[`rui.state.State<T>`](state.md), which is that wrapper:

```haxe
class State<T> extends rui.state.State<T> {
    public function new(initial:T, ?name:String) super(initial, name);

    // only what your library adds on top
    public function setTo(v:T):State<T> { set(v); return this; }
}
```

Reads inside the render effect now subscribe it automatically, and writes re-run
it. Nothing in the app code changes.

### Pushing to the platform, and taking writes back

Register a **sink** to push application writes outward, and route writes coming
*from* the platform through `applyExternal`, which reaches effects without
echoing back:

```haxe
text.setPlatformSink(v -> field.setText(v));                     // Haxe -> platform
field.onTextChanged(() -> text.applyExternal(field.getText())); // platform -> Haxe
```

This matters most when the target already has its own reactive primitive — a
Compose `MutableState`, a SwiftUI `@State`, a listener list, a dirty flag. Keep
**one** source of truth (the signal), mirror it outward through the sink, and
take writes back through `applyExternal`. Otherwise a value bounces between the
two.

## Interpreted targets

rui is plain Haxe, so it runs interpreted. `qui` loads it under the CPPIA
interpreter on a Sailfish device, with signals and effects driving compiled Qt
widgets across the boundary.

One constraint worth knowing if you do the same: the interpreted guest can only
call what the compiled host exports, so rui's classes must be force-referenced
in the host, and **adding a member to a class the guest already uses requires
rebuilding the host**.

## Scope: what rui deliberately does not do

- **No rendering.** No VNode, no reconciler, no renderer contract.
- **No component model.** No base class, no `@:state` macro — each library
  defines its own authoring surface and lowers it onto effects.
- **No scheduling policy beyond batching.** See the flush note in
  [Signals & Effects](signals.md#scheduler).

The original epikDX extraction did carry a virtual DOM, a component macro, a DOM
renderer and a networking layer. Nothing consumed them, and the component macro
was still hard-wired to `epikowa.epikUI`, so they were removed rather than
maintained as dead weight. They remain in the repository's git history.

**The shared render model exists now, and it lives elsewhere on purpose:**
[`nui`](https://lapavoiserie.github.io/nui/) sits above `rui` and describes what
a view tree node is — type, children, key, typed properties, ordered modifiers,
actions — plus the two contracts a renderer consumes it through. It was designed
against the backends' real needs rather than inherited, and kept out of `rui` so
that this scope stays true.
