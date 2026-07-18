# Diagrams: a worked example

`Flow#to_mermaid` renders a flow as a Mermaid `flowchart` that drops straight into
GitHub markdown, a PR description, or docs — no image tooling. This page walks one
**complete** flow: the builder that defines it, the diagram it renders, and a
line-by-line reading of every shape and edge.

The [README](../README.md#self-documenting-diagrams) covers the basics and shows a
simple flow. Start there if you just want the shape of the output. For a term-by-term
reference of every shape, edge, and label, see [VOCABULARY.md](VOCABULARY.md).

## The flow

A deposit wizard with **two forks and a convergence**. A depositor picks an intent on
`start` (`add` / `standalone` / `new`), the paths reconverge at `files`, then a second
fork chooses how to set the work type (`known` vs a file-driven `guided` step):

```ruby
flow = FlowWizard::Flow.build do
  rail_order :parent, :type, :upload, :detail, :file_detail, :review

  condition :adding,    ->(state, _config) { state.path == "add" }
  condition :on_new,    ->(state, _config) { state.path == "new" }
  condition :has_files, ->(state, _config) { state.uploaded_file_ids.any? }
  prerequisite :work_type, ->(state, _config) { state.work_type.present? }, detour: :known_type

  # start routes to already-gated, partly-shared steps that reconverge at files:
  # a draw-only decision (generates no conditions), not a branch.
  decision :path, from: :start,
           add: :select_parent, standalone: :item_start, new: :files

  # two mutually-exclusive ways to set the work type, keyed on the chosen mode:
  # a real branch (generates the per-value skips, records the fork).
  branch :type_mode, on: ->(state, _config) { state.type_mode },
         known: :known_type, guided: :guided_confirm

  step :start,          rail: :type
  step :select_parent,  skip_unless: :adding, on_skip: :entry, rail: :parent, rail_if: :adding
  step :item_start,     skip_if: :on_new, rail: :type
  step :files,          rail: :upload
  step :known_type,     rail: :type
  step :guided_confirm, rail: :type
  step :details,        requires: :work_type, rail: :detail
  step :file_meta,      requires: :work_type, skip_unless: :has_files, rail: :file_detail, rail_if: :has_files
  step :review,         requires: :work_type, rail: :review
  step :done,           terminal: true
end
```

## The diagram

`puts flow.to_mermaid` produces:

```mermaid
flowchart TD
  start{{"start<br/>(path?)"}}
  select_parent{{"select_parent<br/>(when adding)"}}
  item_start{{"item_start<br/>(unless on_new)"}}
  files["files"]
  known_type["known_type"]
  guided_confirm["guided_confirm"]
  details["details"]
  file_meta{{"file_meta<br/>(when has_files)"}}
  review["review"]
  done(["done"])
  start -->|add| select_parent
  start -->|standalone| item_start
  start -->|new| files
  select_parent --> item_start
  item_start --> files
  files -->|known| known_type
  known_type --> details
  files -->|guided| guided_confirm
  guided_confirm --> details
  details --> file_meta
  file_meta --> review
  review --> done
  details -. needs work_type .-> known_type
  file_meta -. needs work_type .-> known_type
  review -. needs work_type .-> known_type
```

## Reading it

### Node shapes

- **Rectangle** (`files`, `known_type`, `details`) — a plain step, always shown when
  the walk reaches it.
- **Hexagon** (`start`, `select_parent`, `item_start`, `file_meta`) — a step with a
  condition attached. The label is the *reason it shows*, written positively:
  `select_parent` reads `(when adding)`, not the internal double negative
  `(if not_adding)`. A fork's `from` step is a hexagon too, labeled with the routing
  variable it decides on (`start<br/>(path?)`).
- **Stadium** (`done`) — a terminal step; the walk ends here.

### The `start` fork (a `decision`)

```
start -->|add| select_parent
start -->|standalone| item_start
start -->|new| files
```

`start` is one screen where the depositor chooses an intent. The three intents are
**siblings**, not a sequence — so the diagram fans out from `start`, each edge labeled
by the value that selects it. `new` skips straight to `files` because that path sets
its work type up front and needs neither the parent chooser nor the item chooser.

A `decision` is **diagram-only**: it draws this fork but generates no conditions and
changes no navigation. Each target step is gated by its *own* skip (`select_parent` is
`skip_unless: :adding`, `item_start` is `skip_if: :on_new`), which is why the fork can
point at steps that are shared between paths.

### The convergence

```
select_parent --> item_start
item_start --> files
```

After the fork the paths merge again: `add` flows `select_parent -> item_start`, then
`add` and `standalone` both meet at `item_start -> files`, and all three meet at
`files`. These are ordinary solid edges — the fork changed where each path *enters*,
not the walk that follows.

### The `files` fork (a `branch`)

```
files -->|known| known_type
files -->|guided| guided_confirm
known_type --> details
guided_confirm --> details
```

Two **mutually-exclusive** ways to set the work type. Unlike the `decision`, a
`branch` *does* gate: it generates the `type_mode_is_known` / `type_mode_is_guided`
skip conditions so exactly one of the two steps shows. Both alternatives converge on
`details`. The value labels (`known` / `guided`) carry the reason, so the two steps
render as plain rectangles rather than repeating the condition inline.

### The dashed edges — guards, not routes

```
details   -. needs work_type .-> known_type
file_meta -. needs work_type .-> known_type
review    -. needs work_type .-> known_type
```

Each dashed edge is a **prerequisite guard**, not a step in the forward walk. It says
"this step requires `work_type`; if a visitor reaches it without one set, redirect to
the prerequisite's `detour:` step" — here `known_type`, the designated place a work
type gets set. Two things about them commonly surprise a first reader:

- **They can point *backward*.** A dashed edge is a conditional redirect, not a
  transition. Solid means "next"; dashed means "only if a prerequisite is missing."
- **In a well-ordered flow they never fire during normal use.** The walk order already
  guarantees `work_type` is set before any of these steps is reached (the `known` path
  sets it at `known_type`, the `guided` path at `guided_confirm`), so a depositor
  clicking through never sees the redirect. The guard exists for *out-of-order* entry
  — a bookmarked URL, a back-button jump, tampered state — and `detour_for` enforces
  it live. The dashed edge documents that invariant and its enforcement point.

All three point at the *same* step because they share one named prerequisite, and a
prerequisite names a single `detour:` target — the one place it is satisfied. Several
dashed edges converging on one step means "these steps all require the same thing,"
not "the walk passes through that step repeatedly."

> One honest wrinkle this example exposes: the `guided` path sets its type at
> `guided_confirm`, but the prerequisite's `detour:` is `known_type` for everyone. In
> normal use a guided depositor reaches `details`/`review` with a type already set, so
> the guard never fires — but if it *did*, it would send them to `known_type` rather
> than back to `guided_confirm`. A prerequisite carries one detour target; per-path
> detours are a modeling choice a flow would have to make explicitly.

## Direction

`to_mermaid` defaults to top-down (`flowchart TD`). Pass `direction:` for a
left-to-right layout, which often reads better for long linear flows:

```ruby
puts flow.to_mermaid(direction: "LR")
```
