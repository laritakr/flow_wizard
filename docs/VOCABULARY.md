# Vocabulary: reading a flow diagram

A flow is written in one vocabulary (the builder DSL) and *drawn* in another (Mermaid
shapes and edge labels). The two deliberately differ — the DSL is for the author, the
diagram is for the reader — so this page maps every term across all three layers: what
you **write**, what the diagram **shows**, and what it **means**.

For where these appear in a real diagram, see [DIAGRAMS.md](DIAGRAMS.md); for wiring a
flow into an app, [INTEGRATION.md](INTEGRATION.md).

## Node shapes

Every step is a node. Its shape tells you its role at a glance:

| Shape | Mermaid | Role |
|-------|---------|------|
| **Rectangle** | `step["name"]` | A plain step — always shown when the walk reaches it. |
| **Hexagon** | `step{{"name<br/>(…)"}}` | A *conditional* step or a *fork* point. The parenthetical says why (a condition) or what it routes on (a variable). |
| **Stadium** (rounded ends) | `step(["name"])` | A *terminal* step — the flow ends here. Declared `terminal: true`. |

## Edges

| Edge | Mermaid | Means |
|------|---------|-------|
| **Solid** | `a --> b` | The forward walk: after step `a`, go to step `b`. |
| **Labeled solid (fork)** | `a -->\|value\| b` | A `branch` or `decision` route: from `a`, the `value` case goes to `b`. |
| **Dashed labeled** | `a -. needs x .-> b` | A **guard, not a route** (see below): step `a` requires `x`; if reached without it, redirect to `b`. |

## Hexagon labels

The parenthetical inside a hexagon has three forms, depending on how the step was
declared:

| You write | Diagram shows | Means |
|-----------|---------------|-------|
| `skip_unless: :adding` | `(when adding)` | Show this step **only when** `adding` is true. |
| `skip_if: :on_new` | `(unless on_new)` | Show this step **unless** `on_new` is true (i.e. hide it when true). |
| `decision :path, from: :start, …` | `(path?)` on `start` | This step **routes on** the `path` variable; the outgoing labeled edges are the choices. |

`when` and `unless` are opposite frames on purpose — `skip_unless` and `skip_if` are
opposite conditions, so the diagram states each honestly rather than forcing both into
one word (which would reintroduce a double negative like "when not new"). Read it as:
**`when` = shown if the condition holds; `unless` = shown if it does not.**

Labels are always *positive* — a `skip_unless: :adding` renders `(when adding)`, never
the internal double negative `(if not_adding)`.

## The dashed edges are guards, not routes

This is the diagram's least obvious convention, so it gets its own note.

A dashed `-. needs x .->` edge does **not** mean "the walk goes here next." It means:
this step declares `requires: :x` (a named prerequisite), and if a visitor ever reaches
the step without `x` satisfied, `detour_for` redirects them to the prerequisite's
`detour:` step. Two consequences that surprise first readers:

- **It can point backward.** Solid = "next"; dashed = "only if a prerequisite is
  missing." A backward dashed arrow is a redirect, not a loop.
- **In a well-ordered flow it never fires.** The walk order already guarantees the
  prerequisite is set before the step is reached, so a normal click-through never sees
  the redirect. The guard exists for *out-of-order* entry — a bookmarked URL, a
  back-button jump, tampered state.

Several dashed edges converging on one step means "these steps all require the same
thing," because a prerequisite names a single `detour:` target — the one place it is
satisfied — not a step the walk passes through repeatedly.

## The builder verbs

The declarations you write in `Flow.build { … }`, and how each surfaces in the diagram:

| Verb | Declares | In the diagram |
|------|----------|----------------|
| `condition :name, ->{…}` | A named predicate over `(state, config)`. | Nothing directly; referenced by steps, which then label hexagons. |
| `prerequisite :name, ->{…}, detour:` | A condition that, when unmet, redirects a `requires:`-ing step to `detour:`. | The dashed guard edges. |
| `branch :var, on:, val: :step, …` | Mutually-exclusive steps chosen by one variable; generates their skip conditions. | A fork: `from -->\|val\| step`, alternatives converging. |
| `decision :var, from:, val: :step, …` | A **diagram-only** routing fork to already-gated, possibly-shared steps. Generates no conditions. | A fork from a hexagon `(var?)` step; targets keep their own edges. |
| `step :name, …` | One step, with its skips/prerequisites/rail/display metadata. | A node (shape per role above). |
| `rail_order :a, :b, …` | The progress-rail phase order (independent of walk order). | Not in the flowchart; drives `flow.rail`. |

### `step` keywords

| Keyword | Meaning | Diagram effect |
|---------|---------|----------------|
| `requires: :x` | Detours to `x`'s prerequisite `detour:` if `x` is unmet. | Dashed guard edge. |
| `skip_unless: :c` | Show only when condition `c` holds. | Hexagon `(when c)`. |
| `skip_if: :c` | Skip (hide) when condition `c` holds. | Hexagon `(unless c)`. |
| `terminal: true` | The flow ends at this step. | Stadium node. |
| `on_skip: :entry` | When skipped, a direct visit is bounced to the entry (vs passing through). | Not drawn; affects `detour_for`. |
| `rail: :key` | The progress-rail phase this step belongs to (`rail_key`). | Not in the flowchart; drives `flow.rail`. |
| `rail_if: :c` | Show this step's rail phase only when `c` holds. | Not in the flowchart; drives `flow.rail`. |
| `icon:` / `label_key:` | Display metadata for the rail. | Not in the flowchart; drives `flow.rail`. |

> **`branch` vs `decision`** — both draw a fork, and the distinction is worth keeping
> straight. `branch` *gates*: it generates the per-value skip conditions, for a clean
> "one value → its own exclusive step" split. `decision` is *draw-only*: it generates
> nothing and just reroutes edges in the diagram, for a fork whose targets are already
> gated by their own skips and may be shared or convergent.
