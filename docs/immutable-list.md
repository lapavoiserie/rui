# ImmutableList

`rui.structures.ImmutableList<T>` is a persistent list: every operation returns a
**new instance** instead of mutating the receiver.

```haxe
import rui.structures.ImmutableList;

var a = new ImmutableList<String>(["x"]);
var b = a.push("y");

a.length   // 1  — unchanged
b.length   // 2
a != b     // true
```

## Why it exists

A `Signal` notifies only when its value changes, compared with `!=` — a
reference comparison for arrays and objects. With a plain array:

```haxe
var todos = new Signal([]);
new Effect(() -> trace(todos.value.length + " items"));

todos.value.push(todo);   // silent: same array instance
```

With an `ImmutableList`, every change *is* a new value:

```haxe
var todos = new Signal(new ImmutableList<Todo>([]));
new Effect(() -> trace(todos.value.length + " items"));

todos.value = todos.value.push(todo);   // -> 1 items
```

Change detection stays a reference comparison — no deep equality, no dirty
flags, no bookkeeping.

## API

| Member | Returns | |
|---|---|---|
| `new ImmutableList(?initialData:Array<T>)` | | copies the array it is given |
| `length:Int` | | |
| `get(index:Int)` | `T` | |
| `push(item:T)` | `ImmutableList<T>` | new list with `item` appended |
| `filter(f:T->Bool)` | `ImmutableList<T>` | |
| `map<S>(f:T->S)` | `ImmutableList<S>` | |
| `iterator()` | `Iterator<T>` | usable in `for (x in list)` |
| `toArray()` | `Array<T>` | a copy — mutating it does not affect the list |

The constructor copies its input and `toArray()` copies its output, so a list
can't be mutated through the array you passed in or got out.

## Patterns

**Update one item** — map to a new list, replacing the one that matches:

```haxe
todos.value = todos.value.map(t -> t.id == id ? toggled(t) : t);
```

**Remove** — filter it out:

```haxe
todos.value = todos.value.filter(t -> t.id != id);
```

**Read without subscribing** — `peek()` on the signal:

```haxe
var count = todos.peek().length;   // no dependency registered
```

## Cost

`push`, `filter` and `map` each copy the backing array: O(n) per operation, not
structural sharing. That is the right trade for UI-sized collections — lists of
rows, items, tabs. For a large or hot data set, keep the data outside the signal
and put only a version marker in it.
