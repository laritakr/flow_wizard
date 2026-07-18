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

Existing tools split into two camps, and neither does what `flow_wizard` does —
because the requirement that matters most eliminates almost everything:

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

The pipeline gems above make good partners, not rivals — they do a different job in the
same request:

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

## What a flow looks like

A flow is a builder block — named conditions, then steps that reference them — and it
renders itself to a diagram:

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

puts flow.to_mermaid  # the diagram below — renders live in GitHub, PRs, and docs
```

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

Hexagons are conditional steps (labeled positively — `when adding`), the stadium is the
end, and the dashed edges are prerequisite *guards* (redirect if a requirement is
missing), not steps in the walk. Flows can also **fork** — a `branch` or `decision`
draws real forking paths. [A fully-branching example is in DIAGRAMS.md](docs/DIAGRAMS.md).

## Install

```ruby
gem "flow_wizard"
```

## At a glance

- **Build a flow** as data — name the conditions that gate your steps, list the steps,
  and declare any forking paths. The whole flow is one readable block. →
  [Anatomy of a flow](docs/AUTHORING-FLOWS.md#anatomy-of-a-flow)
- **Navigate** it — ask the flow where to go: the next step, the previous step, whether
  a step should redirect because a prerequisite isn't met, which steps to show, and the
  progress rail. Your controller acts on the answers. → [Integration
  guide](docs/INTEGRATION.md)
- **Validate** it — catch a mistyped condition or step name at build time instead of
  silently at runtime. → [Validating a flow](docs/AUTHORING-FLOWS.md#validating-a-flow)
- **Diagram** it — render the flow's structure to a Mermaid diagram straight from the
  data, no image tooling. → [Diagrams](docs/DIAGRAMS.md)
- **Wire it into an app** — hold your wizard's state and settings, and drive the flow
  from a controller loop. → [Integration guide](docs/INTEGRATION.md)

## Documentation

- **[docs/AUTHORING-FLOWS.md](docs/AUTHORING-FLOWS.md)** — every term: how to build a flow
  piece by piece, and how to read the diagram it renders.
- **[docs/DIAGRAMS.md](docs/DIAGRAMS.md)** — a full worked flow, its diagram, and a
  line-by-line reading of every shape and edge.
- **[docs/INTEGRATION.md](docs/INTEGRATION.md)** — wiring a flow into an app: the
  `State`/`Config` subclasses, the controller loop, the session round-trip, the rail.

## Design notes

- **Steps are data.** A downstream app reshapes the flow by assigning a new `Flow`
  (or editing the builder block) — no controller subclassing.
- **Named conditions are the core abstraction.** They make flows legible and
  diagrams labeled. Raw lambdas still work as an escape hatch, but only named
  conditions get labeled edges.
- **Zero runtime dependencies.** The gem loads with `require "flow_wizard"` alone.

## Contributing

`bundle install`, then `bundle exec rake` runs the specs and lint. See
**[CONTRIBUTING.md](CONTRIBUTING.md)** for the full development setup and conventions.

## License

Apache-2.0.
