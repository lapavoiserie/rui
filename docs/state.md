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
| `setPlatformSink(sink:Null<T->Void>)` | register the sink; `null` detaches |
| `name:String` | `""` when unnamed |
| `dispose()` | drop subscribers and sink |

Verified by `test/StateCheck.hx`:

```bash
haxe -cp src -cp test -main StateCheck --interp
```
