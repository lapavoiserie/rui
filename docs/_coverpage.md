# rui

> The reactive core of La Pavoiserie.

Fine-grained signals, effects and immutable structures — the state layer shared
by the platform UI libraries. No rendering, no dependencies, every target.

- `Signal<T>` / `Effect` with automatic dependency tracking
- Batched, glitch-free updates through a `Scheduler`
- `Observable` model classes via `@:autoBuild`
- Persistent `ImmutableList<T>` for change-by-reference

[GitHub](https://github.com/lapavoiserie/rui)
[Get Started](getting-started.md)
