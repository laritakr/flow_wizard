# Integration: wiring a flow into an app

`flow_wizard` gives you a `Flow` and a navigator; your app supplies the controller,
the session, and the views. This page shows the glue: the `State` and `Config`
subclasses you define, the controller loop that drives the wizard, and how the
progress rail reaches a view.

> **The gem is framework-agnostic** — it never touches a session, a controller, or a
> request. The Rails controller below is *illustration*, not a dependency: the same
> five moves (load state, check detour, apply params, decide, advance) work in any
> request/response stack. Nothing in the gem requires Rails.

The flow itself — `Flow.build { ... }` — is covered in the
[README](../README.md#define-a-flow) and [DIAGRAMS.md](DIAGRAMS.md). This page assumes
you already have one.

## 1. Define your State

`State` round-trips your wizard's server-side data across the per-step request cycle.
It wraps a plain hash — typically the session bag — and you add typed accessors for
your domain's slots. Every slot reads and writes the backing hash with string keys, so
whatever you store survives being serialized into the session and read back next
request.

```ruby
class DepositState < FlowWizard::State
  def path;                 store["path"];               end
  def path=(value)          store["path"] = value;        end

  def work_type;            store["work_type"];           end
  def work_type=(value)     store["work_type"] = value;    end

  def uploaded_file_ids;    store["uploaded_file_ids"] ||= []; end
  def uploaded_file_ids=(v) store["uploaded_file_ids"] = v;    end
end
```

`store` is `protected`, so accessors live inside the subclass. For one-off values a
step needs to persist without a first-class slot, use the built-in `#extra` bag (it
round-trips the same way):

```ruby
state.extra["type_mode"] = "guided"   # read later as state.extra["type_mode"]
```

Your **conditions** read these accessors — `condition :adding, ->(state, _c) { state.path == "add" }`
— which is why the slot names in the flow definition and the accessors here must line
up.

## 2. Define your Config

`Config` is the seam that holds the flow plus any app settings. Subclass it, assign
your built-in flow, and add whatever host-specific settings or feature flags your
conditions need — those stay in *your* subclass, keeping the gem host-free.

```ruby
class DepositConfig < FlowWizard::Config
  private

  def default_flow
    DepositFlow.build   # your Flow.build { ... }, memoized by the base #flow
  end
end
```

`config.flow` returns this flow (the base memoizes it); an app can still swap it at
runtime with `config.flow = other_flow`. The `config` object is passed as the second
argument to every condition, so app settings a predicate needs (a feature flag, a host
value) live here and reach conditions as `->(state, config) { config.some_setting }`.

## 3. The controller loop

A wizard is one step per request. The controller does five things: **load** state from
the session, **redirect** if the requested step is guarded or skipped, **apply** the
submitted params on a POST, **decide** whether the submission advances, and **persist**
state back to the session. The navigator answers every routing question; the
controller only turns those answers into redirects and renders.

```ruby
# Rails shown for concreteness — the gem needs none of it.
class DepositWizardController < ApplicationController
  before_action :load_state_and_config

  # GET /deposit/:step — render one step, or redirect if it can't be shown yet.
  def show
    detour = @flow.detour_for(params[:step], @state, @config)
    return redirect_to(deposit_path(detour)) if detour

    @step = @flow.step(params[:step])
    @rail = @flow.rail(@state, @config)
    render "deposit/#{@step.name}"
  end

  # PATCH /deposit/:step — apply the submitted params, then advance or re-render.
  def update
    transition = apply(params[:step])       # returns a FlowWizard::Transition
    persist_state

    if transition.advance?
      nxt = @flow.next_after(params[:step], @state, @config)
      redirect_to deposit_path(nxt || "done"), notice: transition.notice
    else
      flash.now[:alert] = transition.alert
      @step = @flow.step(params[:step])
      @rail = @flow.rail(@state, @config)
      render "deposit/#{@step.name}"
    end
  end

  # GET /deposit/:step/back — step backward through the visible steps.
  def back
    prev = @flow.back_before(params[:step], @state, @config)
    redirect_to deposit_path(prev || @flow.names.first)
  end

  private

  def load_state_and_config
    @config = DepositConfig.new
    @state  = DepositState.new(session[:deposit] ||= {})
    @flow   = @config.flow
  end

  # Assignment back into the session: State wraps the SAME hash you handed it, so
  # once slots are set, the session already holds them. (to_h returns that hash.)
  def persist_state
    session[:deposit] = @state.to_h
  end

  # Per-step: mutate @state from params, validate, and return a Transition. Each
  # step's own logic lives here (or in a per-step object you dispatch to).
  def apply(step_name)
    case step_name
    when "select_parent"
      if params[:parent_id].present?
        @state.extra["parent_id"] = params[:parent_id]
        FlowWizard::Transition.advance(step_name, notice: "Parent selected")
      else
        FlowWizard::Transition.rerender(step_name, alert: "Choose a work to add to")
      end
    when "known_type"
      @state.work_type = params[:work_type]
      FlowWizard::Transition.advance(step_name)
    # ...one branch per step, or dispatch to a per-step service...
    else
      FlowWizard::Transition.advance(step_name)
    end
  end
end
```

### Why each navigator call

- **`detour_for(step, state, config)`** — the guard. Returns where a requested step
  should redirect *instead* of rendering: to an unmet prerequisite's `detour:` step,
  or (if the step is skipped in the current state) on to the next visible step. Returns
  `nil` when the step is fine to render. Call it first in `show`; it is what makes the
  dashed prerequisite edges real. (See [DIAGRAMS.md](DIAGRAMS.md#the-dashed-edges--guards-not-routes).)
- **`next_after(step, state, config)`** — the forward move. The next *visible*,
  non-terminal step, skipping anything the current state hides. `nil` at the end.
- **`back_before(step, state, config)`** — the mirror, for a Back button. The previous
  visible step, `nil` at the entry.
- **`step(name)`** / **`names`** — look up a Step (for its view/rail metadata) or the
  full ordered name list.

## 4. The Transition

`apply` returns a `Transition` — the gem's small result object, so your step logic
declares *what should happen* without knowing about redirects:

```ruby
FlowWizard::Transition.advance("known_type", notice: "Type selected")
FlowWizard::Transition.rerender("known_type", alert: "Pick a type")
```

The controller reads `transition.advance?` to choose redirect-forward vs re-render, and
`transition.notice` / `transition.alert` for the flash. `rerender` also carries an
optional `messages:` list for field-level errors your view can display.

## 5. The progress rail

`flow.rail(state, config)` returns the phases to show for the current state, already
collapsed and ordered — several steps can map to one phase, and the rail's order is its
own (set by `rail_order`), independent of the walk. Each entry is
`{ key:, icon:, label_key: }`:

```erb
<%# @rail = @flow.rail(@state, @config) %>
<ol class="wizard-rail">
  <% @rail.each do |phase| %>
    <li class="<%= "is-current" if phase[:key] == @step.rail_key %>">
      <i class="<%= phase[:icon] %>"></i>
      <%= t(phase[:label_key]) %>
    </li>
  <% end %>
</ol>
```

A phase appears only when a visible step maps to it, so the rail shrinks and grows with
the path the depositor is on — the file-metadata phase, for instance, shows up only
once files exist. The `icon` and `label_key` come from whichever visible step in the
group defines them, so collapsed steps need not all carry display metadata.

## The whole loop, in one breath

Each request: **load** `State` from the session and the `Flow` from `Config` → on GET,
**redirect** if `detour_for` returns a target, else render the step with its `rail` → on
POST, **apply** params to `State`, **persist** it back to the session, then **advance**
via `next_after` (or **re-render** on a rejected `Transition`). The gem answers every
"where next?"; your controller owns the request, the session, and the views.
