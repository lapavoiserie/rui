# rui

**rui** is the fine-grained reactive core shared by the La Pavoiserie UI
libraries — [`sui`](https://github.com/Pign/sui) (Apple/SwiftUI),
`aui` (Android/Compose), `wui` (Windows/WinUI 3), `cui` (terminal),
`qui` (Sailfish/Qt-Silica) — and by `mui`, the layer that unifies them.

It is deliberately small. rui owns **state and change propagation**; rendering
belongs to each platform library.

```haxe
import rui.Signal;

var count = new Signal(0);

new Effect(() -> trace("count = " + count.value)); // prints 0 immediately

count.value = 1;                                   // prints 1
count.value = 1;                                   // prints nothing: unchanged
```

## What's in it

| | |
|---|---|
| [`Signal<T>` / `Effect` / `Scheduler`](signals.md) | Reading a signal inside an effect registers a dependency; writing re-runs only the effects that read it, batched. |
| [`Observable`](observable.md) | Model classes whose field writes notify subscribers, via `implements Observable`. |
| [`structures.ImmutableList<T>`](immutable-list.md) | Persistent list: `push`/`filter`/`map` return a new instance, so changes are visible by reference. |

## Why a shared core

Each platform library rendered natively but reimplemented its own notion of
reactive state — a dirty flag here, a listener list there, a platform-native
observable elsewhere. Sharing that layer means one semantics of *what changed*
across every target.

**All five backends now build on it.** `sui`, `aui`, `wui`, `cui` and `qui` each
have a `State<T>` extending [`rui.state.State`](state.md), so the same reads,
writes and untracked peeks behave identically everywhere, and `mui` can document
one contract instead of five. Each backend keeps only its *platform half* — the
sink that pushes a new value to the native side.

See [Integrating rui](integrating.md) for what a platform library has to provide.

**Rendering is not here, by design.** What a view tree node *is* — and the two
contracts a renderer consumes it through — lives in
[`nui`](https://lapavoiserie.github.io/nui/), a separate library that depends on
`rui`. Keeping them apart keeps this one to state and change propagation, which
is the whole point of the trim it went through.

## Install

Most of the time you get it transitively: every La Pavoiserie backend declares it
as a dependency, so `-lib cui` (or `sui`, `aui`, `wui`) already brings it in.
Standalone:

```bash
haxelib git rui https://github.com/lapavoiserie/rui
```

Then add `-lib rui` to your build. rui has no dependencies and no target
requirement — it is plain Haxe, and it runs interpreted as happily as compiled
(`qui` uses it under the CPPIA interpreter on-device).

## Provenance

Extracted from [`epikframework`](https://github.com/epikowa)'s `epikDX`. Only
the target-agnostic reactive core was kept — see
[Scope](integrating.md#scope-what-rui-deliberately-does-not-do).
