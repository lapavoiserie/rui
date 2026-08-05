# Observable

`Signal<T>` makes a *cell* reactive. `Observable` makes an *object* reactive:
writing a field notifies subscribers.

```haxe
import rui.Observable;

class Todo implements Observable {
    public var text:String;
    public var done:Bool;

    public function new(text:String) {
        this.text = text;
        this.done = false;
    }
}
```

That's the whole declaration — no boilerplate, no manual notification.

## Use `implements Observable` alone

`Observable` carries `@:autoBuild(rui.ObservableMacro.build())`, so implementing
the interface *is* what runs the macro.

```haxe
class Todo implements Observable {}                    // correct

@:build(rui.ObservableMacro.build())
class Todo implements Observable {}                    // WRONG — runs twice
```

Adding `@:build` on top runs the macro a second time and the build fails on
duplicate fields. This is the one mistake worth remembering.

## What the macro generates

For every **non-static, non-function** field, the macro rewrites the field into a
property whose setter notifies — guarded by `!=`, exactly like a signal write, so
re-assigning the same value is silent. It also injects:

| Member | |
|---|---|
| `uuid:String` | lazily generated identity, stable for the object's lifetime |
| `subscribe(listener:Void->Void)` | called on any field change |
| `unsubscribe(listener:Void->Void)` | |
| `onPropChange(listener:(String, Dynamic) -> Void)` | called with the field name and its new value |

```haxe
var todo = new Todo("Write docs");

todo.subscribe(() -> trace("something changed"));
todo.onPropChange((name, value) -> trace(name + " -> " + value));

todo.done = true;
// -> something changed
// -> done -> true
```

`uuid` is useful as a stable key when rendering lists, where positional
indices are not enough to identify a row across updates.

## With signals

A signal holding an observable subscribes to it, so field writes propagate to
the signal's effects without replacing the object:

```haxe
var current = new Signal(new Todo("a"));
new Effect(() -> trace(current.value.text));

current.value.text = "b";   // -> b
```

## Observable or ImmutableList?

Both make change detectable; they answer different questions.

| | Use |
|---|---|
| `Observable` | a **long-lived entity** whose fields change in place, and you want the identity preserved (a row being edited, a session, a document) |
| [`ImmutableList`](immutable-list.md) | a **collection** whose shape changes, and you want each version to be a distinct value comparable by reference |

They compose: an `ImmutableList<Todo>` of `Observable` todos gives you
reference-comparable list versions whose items still notify individually.
