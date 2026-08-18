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
- `dispose()` unsubscribes from every dependency and runs any cleanups (below).
  An effect you never dispose lives as long as the signals it reads.

Effects nest: an effect created inside another is independent, and the inner one
tracks its own reads.

### `Effect.onCleanup` — undoing what the effect did

An effect that only reads needs nothing more. An effect that **opens** something
— a timer, a socket, a subscription to something outside `rui` — has to close
it, and the moment to close it is before the effect runs again, not only when it
is disposed:

```haxe
new Effect(() -> {
    var timer = new haxe.Timer(interval.value);
    timer.run = () -> tick.value++;
    Effect.onCleanup(() -> timer.stop());
});
```

Read from inside the effect, so it registers on the effect currently running.

- Cleanups run **before each re-run**, then again on `dispose()`. Without that
  order, an effect that re-runs on every write stacks one live resource per
  write — a leak that grows with use instead of showing up once.
- `dispose()` is **idempotent**: cleanups run once. A second run would be
  closing a handle already closed, which is quiet until that handle has been
  reused.
- You may register **more than one** per run; all of them run, and one that
  throws does not silence the rest.
- Calling it **outside an effect throws**. Registering nowhere would mean a
  resource never released, and silence is the one outcome nobody notices.

A runnable demonstration is in `examples/polling` — a timer re-created when its
interval changes, where the whole failure mode is visible in the output.

The case this is really for is watching something that changes outside the
program. `kui`'s `examples/network-app` does exactly that: a capability that
answers "is the network reachable" is polled on a timer owned by an effect, and
the application never learns a timer exists — views read a signal. Verified with
the link taken down and brought back:

```
net: start  — online
net: change — offline
net: stopped — offline      # the quit ran the cleanup
```

## `Lifetime` — one moment to undo everything

`Effect.onCleanup` answers "undo what *this effect* did, before it runs again".
`rui.Lifetime` answers the other half: "undo everything, because whatever owned
it is over".

```haxe
var life = new Lifetime();
life.ownEffect(watcher);
life.own(() -> connection.close());
…
life.release();          // both, once, in reverse
```

- **Reverse order.** What was built last is undone first, because a handle
  opened after a connection must close before it.
- **Once.** `release()` is idempotent; a second pass would undo what is already
  undone.
- **Late registration runs at once.** Handing something to an owner that is
  already over would otherwise be a leak wearing the costume of ownership.
- **One failure does not strand the rest.**

### `keep` — vivant tant que c'est déclaré

`own` dure jusqu'à `release()`. `keep` dure **tant que `body()` redemande la
clé** — ce qui est une durée de vie de vue, exprimée du seul côté qui puisse la
connaître :

```haxe
override function body():View {
    if (showDetail) lifetime.keep("detail", () -> {
        var stop = Watch.changes(net, 1000, onChange);
        return stop;                      // comment le défaire
    });
    …
}
```

- **Une clé, pas une vue.** Une reconstruction produit des objets neufs, donc un
  pointeur ne désigne rien d'une passe à l'autre ; et sous le contrat pull
  l'hôte étend et jette les vues à son propre rythme sans prévenir Haxe. La clé
  est la seule identité que l'application est en position d'énoncer, et elle est
  la même sur les six backends.
- **« Déclaré », pas « à l'écran ».** Les deux diffèrent, et c'est le point : une
  vue sortie d'une liste paresseuse au défilement est toujours déclarée, et
  arrêter son guetteur parce que l'utilisateur a scrollé serait un bug qu'on met
  des semaines à attribuer. Un `onDisappear` de l'hôte ne sait pas faire cette
  différence ; `body()` si, parce que déclarer est ce qu'il fait.
- **Défait une passe plus tard.** Le balayage a lieu au *début* d'une passe, pas
  à la fin : sous pull, le `body()` d'un composant s'exécute pendant que l'hôte
  parcourt, donc **après** que celui de l'application a rendu la main. Balayer en
  fin de passe défairait ce qu'un composant vient de déclarer.

`mui.App` en porte un, donc une application en construit rarement — voir
ci-dessous.

### There is no `useEffect` here, and that is deliberate

`useEffect` exists because a React component function is re-called with no
identity of its own, so lifetime has to be attached by a hook. Here a view
builds a tree of objects and a node's identity is its **place in that tree**, so
the problem is not the same one. `Effect` covers "re-run when this changes";
`onCleanup` covers "and undo the last run". Neither is tied to a view's
lifetime *by the host's reckoning*. What `mui.App.lifetime` offers instead is
the application's life (`own`) and a **declaration-scoped** one (`keep`) — which
is what a view's presence means from Haxe's side, and the only one that can be
told the same way on both rendering families. `pui` takes the opposite
approach to time for the same reason: its `anim.Ticker` is asked for one more
frame *per frame* and the request clears itself, so a view thrown away by a
rebuild cannot leave anything running — nothing is ever registered, so nothing
has to be unregistered.

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
