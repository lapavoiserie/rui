# State

`rui.state.State<T>` is a signal wrapped in the shape a UI library actually
needs. It is what the La Pavoiserie backends build their own `State<T>` on, so
that one semantics of *what changed* is shared across every target.

You do not have to use it — [signals and effects](signals.md) are the primitive.
`State` exists because every platform library was writing the same wrapper.

```haxe
import rui.state.State;

var count = new State(0);

count.get();     // tracked read
count.set(1);    // write: re-runs dependent effects
count.peek();    // untracked read
count.value;     // alias for get() / set()
```

## The sink: talking to the platform

A UI library has to push new values somewhere native — a Swift `AppState`, a
Compose `MutableState`, a Qt property, a listener list. That is the **sink**,
registered once:

```haxe
var text = new State("");
text.setPlatformSink(v -> nativeField.setText(v));
```

The sink runs on **application** writes only:

| | effects re-run | sink runs |
|---|---|---|
| `set(v)` — the app writes | yes | yes |
| `applyExternal(v)` — the platform writes | yes | **no** |
| write with an unchanged value | no | no |

## Why `applyExternal` exists

A two-way control writes back: the user types in a native text field, and that
value has to reach Haxe. It must reach effects — an action closure reading the
state should see fresh text. But it must **not** be pushed back to the platform,
which already has it. Echoing it back is how a binding starts looping, or
fights the caret while the user types.

```haxe
// wiring a native field, both directions
text.setPlatformSink(v -> field.setText(v));       // Haxe  -> platform
field.onTextChanged(() -> text.applyExternal(field.getText())); // platform -> Haxe
```

This is the one asymmetry in the API, and the reason the sink is a plain
callback rather than an `Effect`: an effect could not tell the two directions
apart, so a platform write would immediately bounce back.

## Durable cells

A cell may also be backed by a **device store**, so its value outlives the
process and is shared with the application's own detached surfaces on that
device. `rui` declares the port; it does not know where a store comes from —
the same layering as the platform sink.

```haxe
rui.state.Durable.store = someStore;   // installed once by the host
rui.state.Durable.writer = "app";      // which instance we are

var cell = new State(rui.state.Durable.initial("Counter.count", KInt, 0));
rui.state.Durable.bind(cell, "Counter.count", KInt);
```

An application never writes that; `mui`'s `@:state(durable)` does. What matters
here is the three decisions it rests on.

**A second slot, not the platform sink.** The sink is taken on every backend
already — `cui` marks dirty, `sui` pushes to Swift, `aui` writes a Compose
`MutableState`. So `set()` calls the durable sink first and the platform sink
after, and neither knows about the other.

**Hydration happens at construction.** `initial()` is called as the
constructor's *argument*, not written in afterwards, because several backends
mirror the initial value into their platform as the cell is built. A cell built
with the default and corrected a line later leaves the platform holding the
default while `rui` holds the stored value — an application disagreeing with
its own screen at launch.

**A foreign write is `applyForeign`, not `applyExternal`.** They look
interchangeable and are opposites. `applyExternal` deliberately skips the sink
because the platform is the one that wrote — that is its whole purpose. A value
arriving from the store came from *another process*, and this platform has
never seen it, so it must go through the sink. `applyForeign` calls the
overridden `set()`, so every backend's mirror updates exactly as for an
application write, and only the write back to the store is suppressed. No
backend overrides anything for this.

Four kinds — `KInt`, `KFloat`, `KBool`, `KString` — and the reason is
`Signal.set_value`'s `!=`: a reference type mutated in place compares equal to
itself, so its write would never reach the store. The packing is one codec
here rather than one per platform.

Nothing rehydrates on its own. `Durable.rehydrate()` is called at moments the
host names — an application returning to the foreground, an extension about to
run a closure — and costs one integer read when nothing changed. A background
thread rewriting cells under a running effect is a different and much worse
problem.

## What is deliberately absent

No `setTo`, no `inc`/`dec`/`toggle`, no typed `IntState`/`BoolState` subclasses.
The platform libraries disagree about them — `setTo` returns the state in `cui`
and `qui` but an action value in `wui` and `aui` — so they stay in those
libraries. The shared core carries only what they agree on.

## API

| Member | |
|---|---|
| `new State(initialValue:T, ?name:String)` | `name` is optional; some backends key a bridge on it |
| `get():T` / `value` | tracked read |
| `set(v:T)` / `value = v` | app write: effects, then sink |
| `peek():T` | untracked read |
| `applyExternal(v:T)` | platform write: effects only |
| `applyForeign(v:T)` | write from another process: effects **and** sink, no write back |
| `setDurableSink(sink:Null<T->Void>)` | the store's slot, separate from the platform sink |
| `setPlatformSink(sink:Null<T->Void>)` | register the sink; `null` detaches |
| `name:String` | `""` when unnamed |
| `dispose()` | drop subscribers and sink |

Verified by `test/StateCheck.hx`:

```bash
haxe -cp src -cp test -main StateCheck --interp
```
