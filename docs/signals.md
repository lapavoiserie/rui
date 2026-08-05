# Signals & Effects

Everything reactive in rui is these three types, all in the `rui.Signal` module.

## `Signal<T>`

A single reactive cell.

```haxe
var s = new Signal(0);

s.value        // tracked read  — registers a dependency if inside an effect
s.value = 1    // write         — notifies dependent effects if the value changed
s.peek()       // untracked read — never registers a dependency
```

| Member | |
|---|---|
| `new Signal(initialValue:T)` | |
| `value:T` | tracked read / notifying write |
| `peek():T` | read without subscribing |
| `subscribe(e:Effect)` / `unsubscribe(e:Effect)` | manual wiring; rarely needed |
| `dispose()` | drop all subscribers |

### Writes are compared with `!=`

A write only notifies when the value actually changed:

```haxe
var s = new Signal(1);
new Effect(() -> trace(s.value));  // -> 1
s.value = 1;                       // silent
s.value = 2;                       // -> 2
```

For scalars this is what you want. For **objects and arrays** `!=` compares
*references*, so mutating in place is invisible:

```haxe
var list = new Signal([1, 2]);
list.value.push(3);        // NOT observed — same array instance
list.value = [1, 2, 3];    // observed — new instance
```

This is exactly why [`ImmutableList`](immutable-list.md) exists.

### Signals holding an `Observable`

If a signal's value implements [`Observable`](observable.md), the signal
subscribes to it: changing a field of the held object notifies the signal's
effects, without replacing the object. Swapping the value unsubscribes from the
old one and subscribes to the new one.

```haxe
var current = new Signal(new Todo("a"));
new Effect(() -> trace(current.value.text));

current.value.text = "b";       // -> b   (field write on the held observable)
current.value = new Todo("c");  // -> c   (new object)
```

## `Effect`

A side effect that re-runs when what it read changes.

```haxe
var e = new Effect(() -> trace(count.value));
...
e.dispose();
```

- **It runs once immediately** on construction — that first run is what collects
  its dependencies.
- Dependencies are **re-collected on every run**, so branches are tracked
  honestly: an effect that no longer reads a signal no longer depends on it.
- Re-runs are **scheduled**, not immediate (see below).
- Exceptions thrown inside the function are **caught and traced**, not
  propagated — a failing effect won't take down the write that triggered it, but
  it also won't be loud. Don't rely on an effect to surface errors.
- `dispose()` unsubscribes from every dependency. An effect you never dispose
  lives as long as the signals it reads.

Effects nest: an effect created inside another is independent, and the inner one
tracks its own reads.

## `Scheduler`

Batches effect re-runs so one write doesn't re-run the same effect twice.

```haxe
Scheduler.schedule(fn);   // queue; effects call this for you via Effect.schedule()
```

The flush strategy is per target:

| Target | Flush |
|---|---|
| JS | `requestAnimationFrame` — coalesced to a frame |
| everything else | **synchronous** |

The synchronous flush is inherited from the terminal target, where deferring
through `MainLoop`/`Timer` conflicts with blocking reads such as
`Sys.getChar`. It suits imperative targets, which patch native widgets directly.
Consider it before driving a target that can re-enter from a native callback:
under a synchronous flush, a write made *inside* an effect flushes within that
same effect's run.

## Fine-grained by construction

Nothing here re-renders anything. What an effect covers is what gets re-run — so
the granularity is a design decision made by whoever creates the effects:

```haxe
// coarse: one effect for the whole view
new Effect(() -> render(buildWholeTree()));

// fine: one effect per binding
new Effect(() -> label.text = "Count: " + count.value);
```

`qui` uses the second form: each reactive property in a view gets its own
effect, so a write re-applies exactly that property — no tree walk, no diff.
See [Integrating rui](integrating.md).
