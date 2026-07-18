# Contributing to flow_wizard

Thanks for your interest in improving `flow_wizard`. It's a small, dependency-free Ruby
gem, so the development loop is quick.

## Setup

You need Ruby (the gem targets **>= 2.7.0**) and Bundler.

```sh
git clone https://github.com/laritakr/flow_wizard.git
cd flow_wizard
bundle install
```

That installs the runtime (none) plus the development dependencies — RSpec, RuboCop,
and Rake — declared in [`flow_wizard.gemspec`](flow_wizard.gemspec).

## Running the checks

```sh
bundle exec rake            # specs + lint (the full check; run this before a PR)

bundle exec rspec           # just the specs
bundle exec rspec spec/flow_wizard/flow_spec.rb   # a single spec file

bundle exec rubocop         # just the lint
bundle exec rubocop -a      # lint + safe autocorrect
```

`rake` (no arguments) runs `spec` then `rubocop`; a green `rake` is the bar for a pull
request. The gem loads with `require "flow_wizard"` alone, so the specs run without
Rails or any web framework.

## Conventions

- **Zero runtime dependencies.** The gem must keep loading with only `require
  "flow_wizard"`. Don't add a runtime dependency; development-only tools go in the
  gemspec's `add_development_dependency` list.
- **Framework-agnostic.** Nothing in `lib/` may reference Rails, a controller, a
  session, or a request. The gem answers questions; the host app acts on the answers.
  (See [docs/INTEGRATION.md](docs/INTEGRATION.md).)
- **Double-quoted strings**, and the RuboCop config in
  [`.rubocop.yml`](.rubocop.yml) is the source of truth for style. If a rule genuinely
  doesn't fit, discuss it in the PR rather than adding an inline `rubocop:disable`.
- **Test-first for fixes.** Add a spec that reproduces the bug and fails, then fix it.

## Adding a spec

Specs live in `spec/flow_wizard/`. Shared fixtures — a sample flow and a stand-in
state object — are in [`spec/support/example_flow.rb`](spec/support/example_flow.rb);
reuse them where you can. Because a flow is plain data, most behavior can be exercised
by building a `Flow` and asserting on the navigator (`next_after`, `detour_for`,
`visible_steps`, `rail`, `validate`) — no doubles or web stack needed.

## Documentation

The `docs/` directory holds the reference material — how to author a flow
([AUTHORING-FLOWS.md](docs/AUTHORING-FLOWS.md)), read its diagram
([DIAGRAMS.md](docs/DIAGRAMS.md)), and wire it into an app
([INTEGRATION.md](docs/INTEGRATION.md)). If a change alters behavior a doc describes,
update the doc in the same PR. The Ruby examples in the docs are meant to be correct —
keep them buildable, and `flow.validate` clean where a full flow is shown.

## Pull requests

- Branch from `main`, keep the change focused.
- Run `bundle exec rake` and make sure it's green.
- Describe *why* the change is needed, not just what it does.
