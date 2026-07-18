# frozen_string_literal: true

require_relative "lib/flow_wizard/version"

Gem::Specification.new do |spec|
  spec.name = "flow_wizard"
  spec.version = FlowWizard::VERSION
  spec.authors = ["LaRita Robinson"]
  spec.email = ["laritakr@gmail.com"]
  spec.summary = "Declarative, self-documenting multi-step flows as swappable data."
  spec.description = <<~DESC
    A dependency-free, controller-agnostic engine for multi-step wizard flows. A flow
    is an ordered list of Steps (plain data) plus a navigator (next/back/detour/skip/
    progress rail). Steps reference named conditions, so a flow is both buildable
    (a small DSL) and self-documenting (renders to a Mermaid diagram). Your app queries
    the flow; the gem never owns the request cycle.
  DESC
  spec.homepage = "https://github.com/laritakr/flow_wizard"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "docs/**/*"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.88"
end
