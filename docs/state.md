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

## The `@:state` property

An application rarely holds a `State` by hand. It declares a field, and the
backend's macro builds the cell:

```haxe
@:state var count:Int = 0;

count += 1;                 // writes the cell, which notifies
new Text('$count');         // reads the cell, which subscribes
Toggle("dark", dark_);      // the cell itself, for a control that binds
count_.peek();              // an untracked read, said out loud
```

The field becomes two: the **cell** — the backend's `State<T>` — under the
field's name with a trailing underscore, and a **property** under the field's
own name that forwards to it. `get_count()` is `count_.get()`, so a read still
subscribes; `set_count(v)` is `count_.set(v)`, so a write still notifies, still
reaches the platform sink, still reaches the durable one. Nothing about *when*
anything happens moved; only the spelling did.

The trailing underscore is the convention for "the cell of": Swift writes
`$dark` for the same thing, and Haxe has no `$` in an identifier. A control
that binds, a durable store, an untracked read — anything that needs the cell
rather than its value — takes `dark_`.

The split lives in `rui.macros.StateProperty`, shared by the six backend
macros the way `DurableState` beside it is. The property carries
`@:stateProperty`, which is how `rui.macros.ViewRule` knows that a read
of a plain-looking `Int` field is a subscribing read and accepts it.

## Shared cells: one owner each

A cell may also be **shared** with another device running the same
application — a phone and its watch, a Mac and a tablet — under one rule:
every shared cell has exactly one owner, and only the owner writes it.

```haxe
@:state(shared(Phone)) var goal:Int = 10000;   // the phone writes it; a watch write is an intent
@:state(shared(Watch)) var steps:Int = 0;      // the watch owns it; the phone reads it
```

The rule lives in `rui.state.Shared`, and it rests on a third slot on the
cell, `setShareHook`, which is **not a sink**: it runs *before* the signal
moves and may consume the write. On an owned cell the hook stamps the value
`(incarnation, sequence)`, carries it, and lets the write land. On a cell
another party owns it carries the value as an intent and the local cell
does not move — a peer never shows a value the owner did not stamp. What
arrives from the owner is applied through `applyForeign`, like a durable
value from another process: the platform mirror updates, nothing is written
back.

`rui` knows the rule and not the wire: `Shared` speaks to a `SharedCarrier`,
and `dui.state.Share` is one. The four kinds are `Durable`'s, packed by the
same codec, and the refusals are the same discipline — a foreign write with
no owner reachable, a frame for an unknown cell or the wrong kind, all say
so through `Shared.onRefused` rather than queue or guess.

Verified by `test/SharedCheck.hx`; the wire by `dui/test/Check.hx`; the
design by `dui`'s [owned state](https://lapavoiserie.github.io/dui/#/owned-state).

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
| `setShareHook(hook:Null<T->Bool>)` | asked before the signal moves; `true` consumes the write (a foreign shared cell) |
| `setPlatformSink(sink:Null<T->Void>)` | register the sink; `null` detaches |
| `name:String` | `""` when unnamed |
| `dispose()` | drop subscribers and sink |

Verified by `test/StateCheck.hx`:

```bash
haxe -cp src -cp test -main StateCheck --interp
```
