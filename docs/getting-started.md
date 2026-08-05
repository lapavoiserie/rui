# Getting Started

## Install

```bash
haxelib git rui https://github.com/lapavoiserie/rui
```

Add it to your build:

```
-lib rui
```

rui is plain Haxe with no dependencies and no target requirement.

## A first signal

```haxe
import rui.Signal;

class Main {
    static function main() {
        var count = new Signal(0);

        new Effect(() -> trace("count = " + count.value));
        // -> count = 0   (an effect runs once when created)

        count.value = 1;
        // -> count = 1

        count.value = 1;
        // nothing: the value is unchanged, so no effect re-runs
    }
}
```

Two things happened implicitly:

1. Reading `count.value` **inside** the effect registered `count` as one of its
   dependencies. Nothing was wired by hand.
2. Writing a *different* value re-ran the effect — and only the effects that
   actually read that signal.

> `Effect` lives in the `rui.Signal` module, so `import rui.Signal;` brings both.
> There is no `rui.Effect` to import.

## Derived values

An effect can read several signals; it re-runs when any of them changes.

```haxe
var first = new Signal("Ada");
var last  = new Signal("Lovelace");

new Effect(() -> trace(first.value + " " + last.value));
// -> Ada Lovelace

last.value = "Byron";
// -> Ada Byron
```

Dependencies are re-collected on every run, so a conditional read is tracked
correctly: an effect that stops reading a signal stops depending on it.

## Model objects

For a whole object rather than a single cell, make it `Observable` — field
writes then notify subscribers:

```haxe
import rui.Observable;

class Todo implements Observable {
    public var text:String;
    public var done:Bool;
    public function new(text:String) { this.text = text; this.done = false; }
}

var todo = new Todo("Write docs");
todo.subscribe(() -> trace("todo changed"));
todo.done = true;   // -> todo changed
```

See [Observable](observable.md).

## Collections

A signal only notifies when its value *changes*, compared with `!=`. For a class
instance or an array, that is a reference comparison — mutating in place changes
nothing observable. Use [`ImmutableList`](immutable-list.md), whose operations
return a new instance:

```haxe
import rui.structures.ImmutableList;

var todos = new Signal(new ImmutableList<Todo>([]));

new Effect(() -> trace(todos.value.length + " items"));
// -> 0 items

todos.value = todos.value.push(new Todo("Write docs"));
// -> 1 items
```

## Check your setup

The repository ships a standalone check:

```bash
haxe -cp src -cp test -main Check --interp
```

## Next

- [Signals & Effects](signals.md) — tracking, batching, disposal
- [Integrating rui](integrating.md) — wiring rui into a UI library
