# flow_wizard

A dependency-free, controller-agnostic engine for **multi-step wizard flows**. A
flow is an ordered list of steps as plain data, plus a navigator
(next/back/detour/skip/progress-rail). Steps reference **named conditions**, so a
flow is both **buildable** (a small DSL) and **self-documenting** (it renders to a
Mermaid diagram).

Your app *queries* the flow — the gem never takes over your controller, and it
assumes nothing about your models or storage.

**Why model a wizard this way?** Because it makes the navigation *data* instead of
imperative controller logic, which buys three things:

- **Reconfigurable in one place.** A downstream app reshapes the wizard by assigning a
  new `config.flow` — the code that walks it never changes. (This gem was extracted so
  two apps could share one navigator and each swap the step list.)
- **Testable as a plain object.** The whole flow — every route, skip, detour, and rail
  phase — is exercised as a PORO, with no controller, request, or session in the loop.
- **Trustworthy self-documentation.** The diagram is accurate *because* the branching
  is declarative data a renderer can read — unlike branching buried in controller
  `if`s, which no diagram can follow.

The implementation is deliberately small; the point is the shape, not the line count.
For a genuinely linear form that will never branch, skip, or be reused, plain
controller actions are simpler — reach for this once there's real branching, a
prerequisite guard, a progress rail, or a second consumer.

## How is this different from existing gems?

We surveyed the Ruby/Rails ecosystem before writing this. Existing tools split into
two camps, and neither does what `flow_wizard` does — because the requirement that
matters most eliminates almost everything:

> **Steps are declarative runtime *data*.** A downstream app reorders, inserts, or
> removes steps by assigning `config.flow = Flow.new([...])` — no controller
> subclassing, no one-model-per-step assumption, no editing the wizard's logic.

### UI wizard gems — right domain, wrong architecture

**wicked**, **DfE::Wizard**, and the `form_wizard` / GOV.UK family live in the right
place (multi-step forms) but **take over the controller**. In wicked, `include
Wicked::Wizard` makes the controller *be* the wizard; the step list is
`steps :a, :b, …` in the controller class, not data an app can swap. A downstream app
customizes by overriding the controller — heavier and more fragile than assigning a
config value. Skips scatter into the `show` case, and there's no first-class
detour/prerequisite and no phase-collapsing progress rail. (DfE::Wizard is the closest
philosophically — standalone step classes, no controller takeover — but its flow is
still defined in code rather than as swappable data, which is the distinction that
matters here.)

### Flow / pipeline / state-machine gems — right philosophy, wrong domain

**trailblazer-activity**, **dry-transaction/operation**, and the state machines
(**aasm**, **state_machines**, **statesman**, **workflow**) are libraries you query
rather than frameworks that own the controller — the right philosophy. But they model
the wrong thing: a **service-execution pipeline** that runs and returns a result within
one request (trailblazer, dry-rb), or **states-and-transitions** (the state machines).
Neither models *request-spanning UI navigation* — back/forward across the request
cycle, skip, detour-to-a-prerequisite, or a progress rail. A linear-wizard-with-skips
isn't naturally a state machine, and their step lists are class-DSL, not data.

### The empty intersection

`flow_wizard` sits where nothing else does: **request-spanning UI navigation, modeled
as swappable data, decoupled from the controller, with prerequisite-detours and a
phase-collapsing progress rail.** UI gems own the controller; pipeline gems don't span
requests. That gap is why the gem exists.

### They compose — you can use both

The pipeline gems above aren't just "not competitors"; you may well use one *alongside*
`flow_wizard`, because they do different jobs in the same request:

- **`flow_wizard` runs the outer loop** — which step the user is on, whether they can go
  back, whether a prerequisite redirects them, where the progress rail sits. It answers
  *"where next?"* and never does a step's actual work.
- **A step's submit often has to *do something*** — save a record, enqueue a job,
  validate against a service — and that work can succeed or fail. `flow_wizard` has no
  opinion on it. That is where a service object, **trailblazer-activity**, or
  **dry-monads** does the job.

They meet in the step's controller action: `flow_wizard` tells you the user is on
`review`, your action runs the operation that saves the work, and its success/failure
becomes the `Transition` you hand back — `advance` to the next step, or `rerender` with
the errors. Sequencing (this gem) and doing-the-work (that gem) stack cleanly; neither
replaces the other. The [integration guide](docs/INTEGRATION.md) shows where that call
lands in the loop.

## Install

```ruby
gem "flow_wizard"
```

## Define a flow

```ruby
flow = FlowWizard::Flow.build do
  condition :adding,       ->(state, _config) { state.path == "add" }
  condition :has_files,    ->(state, _config) { state.uploaded_file_ids.any? }
  prerequisite :work_type, ->(state, _config) { state.work_type }, detour: :known_type

  step :start, rail: :type
  step :select_parent, skip_unless: :adding, on_skip: :entry, rail: :parent
  step :known_type, rail: :type
  step :files, rail: :upload
  step :details, requires: :work_type, rail: :detail
  step :file_meta, requires: :work_type, skip_unless: :has_files, rail: :file_detail
  step :review, requires: :work_type, rail: :review
  step :done, terminal: true
end
```

`skip_unless: :adding` reads as intent ("show this step only when adding");
`requires: :work_type` means "if the work type isn't set yet, detour to the step
that sets it." Both reference **named** conditions, which is what makes the diagram
below possible — an inline `->(s,c){...}` can be evaluated but not described.

Two more declarations model forks:

- **`branch`** — a set of **mutually-exclusive** steps chosen by one variable. It
  generates the per-value skip conditions and records the fork so the diagram draws a
  real branch.
- **`decision`** — a step that *routes* to several **already-gated**, possibly-shared
  downstream steps (a fork that doesn't fit `branch`'s one-value-one-exclusive-step
  shape). Diagram-only: it generates no conditions and changes no navigation.

Both are shown in a full worked flow in
**[docs/DIAGRAMS.md](docs/DIAGRAMS.md)**.

## Navigate

The navigator methods take your own `state` (any object your conditions understand)
and an optional `config`:

```ruby
flow.next_after("files", state, config)   # => "details"  (skips file_meta when no files)
flow.back_before("details", state, config) # => "files"
flow.detour_for("details", state, config)  # => "known_type" until work_type is set, else nil
flow.visible_steps(state, config)          # => the steps to show for this state
flow.rail(state, config)                   # => [{ key:, icon:, label_key: }, ...] progress rail
```

`Transition` is the small result object your controller turns into a redirect or a
re-render:

```ruby
FlowWizard::Transition.advance("details", notice: "Type selected")
FlowWizard::Transition.rerender("known_type", alert: "Pick a type")
```

## Self-documenting diagrams

```ruby
puts flow.to_mermaid
```

produces Mermaid source that renders as a live diagram in GitHub, PRs, and docs —
no image tooling. It reads like the *process*, not the raw step array:

- **Hexagons** are conditional steps, labeled *positively* from the named condition
  (`when adding`, not the internal double negative `if not_adding`).
- **Solid edges** are the sequential walk; the **stadium** node is a terminal step.
- **Dashed labeled edges** are prerequisite *guards*, not routes (`needs work_type`).
- A declared **`branch`** renders as a real fork — the step before it points to each
  alternative with a value-labeled edge, and the alternatives converge again.

Every shape, edge, and label — and how each maps to the DSL you wrote — is spelled out
in **[docs/VOCABULARY.md](docs/VOCABULARY.md)**.

```mermaid
flowchart TD
  start["start"]
  select_parent{{"select_parent<br/>(when adding)"}}
  known_type["known_type"]
  files["files"]
  details["details"]
  file_meta{{"file_meta<br/>(when has_files)"}}
  review["review"]
  done(["done"])
  start --> select_parent
  select_parent --> known_type
  known_type --> files
  files --> details
  details --> file_meta
  file_meta --> review
  review --> done
  details -. needs work_type .-> known_type
  file_meta -. needs work_type .-> known_type
  review -. needs work_type .-> known_type
```

The **dashed edges are prerequisite guards, not routes** — a step that `requires:`
something redirects to that prerequisite's `detour:` step if reached without it, so a
dashed edge can point backward and normally never fires. That, plus a fully worked
example (a two-fork flow with its diagram and a line-by-line reading of every shape
and edge), is in **[docs/DIAGRAMS.md](docs/DIAGRAMS.md)**.

## State and Config bases

`FlowWizard::State` wraps a plain hash (typically your session bag) — subclass it and
add typed accessors for your domain's slots; `#extra` is a namespaced bag for
ad-hoc state, and `#to_h` gives the raw hash back for the session.
`FlowWizard::Config` holds a swappable `flow` plus whatever settings your app needs;
feature-flag / host reads live in *your* subclass, keeping the engine host-free.

## Wiring it into an app

The gem gives you a flow and a navigator; your app supplies the controller, the
session, and the views. For the full glue — the `State`/`Config` subclasses, the
controller loop (show / update / back), the session round-trip, and the progress rail
in a view — see **[docs/INTEGRATION.md](docs/INTEGRATION.md)**. (Shown with a Rails
controller for concreteness; the gem itself needs no framework.)

## Design notes

- **Steps are data.** A downstream app reshapes the flow by assigning a new `Flow`
  (or editing the builder block) — no controller subclassing.
- **Named conditions are the core abstraction.** They make flows legible and
  diagrams labeled. Raw lambdas still work as an escape hatch, but only named
  conditions get labeled edges.
- **Zero runtime dependencies.** The gem loads with `require "flow_wizard"` alone.

## License

Apache-2.0.
