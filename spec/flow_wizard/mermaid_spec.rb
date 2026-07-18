# frozen_string_literal: true

require "spec_helper"
require "support/example_flow"

RSpec.describe FlowWizard::Mermaid do
  subject(:diagram) { example_flow.to_mermaid }

  it "opens with a top-down flowchart" do
    expect(diagram).to start_with("flowchart TD")
  end

  it "renders each step as a node with a quoted label" do
    expect(diagram).to include('start["start"]')
    expect(diagram).to include('known_type["known_type"]')
  end

  it "shapes a terminal step as a stadium node" do
    expect(diagram).to include('done(["done"])')
  end

  it "marks a conditional step as a hexagon labeled with its condition" do
    # select_parent is skip_unless: :adding, registered as the inverse not_adding.
    # Labels are quoted so the parens/<br/> parse in Mermaid.
    expect(diagram).to include('select_parent{{"select_parent<br/>(if not_adding)"}}')
    expect(diagram).to include('file_meta{{"file_meta<br/>(if not_has_files)"}}')
  end

  it "links the sequential spine with solid edges" do
    expect(diagram).to include("start --> select_parent")
    expect(diagram).to include("review --> done")
  end

  it "renders a dashed, named detour edge for a prerequisite" do
    expect(diagram).to include("details -. needs work_type .-> known_type")
    expect(diagram).to include("review -. needs work_type .-> known_type")
  end

  it "honors a custom direction" do
    expect(example_flow.to_mermaid(direction: "LR")).to start_with("flowchart LR")
  end

  it "quotes every node label so parens/<br/> parse in Mermaid (regression)" do
    # An unquoted `{{label (with parens)}}` breaks Mermaid's parser. Every node's
    # bracketed label must open with a double quote.
    node_lines = diagram.lines.grep(/\A\s+\w+(\[|\{\{|\(\[)/)
    expect(node_lines).not_to be_empty
    node_lines.each do |line|
      expect(line).to match(/(\[|\{\{|\(\[)"/), "unquoted node label: #{line.strip}"
    end
  end

  it "produces a stable snapshot for the example flow" do
    expect(diagram).to eq(<<~MERMAID.chomp)
      flowchart TD
        start["start"]
        select_parent{{"select_parent<br/>(if not_adding)"}}
        known_type["known_type"]
        files["files"]
        details["details"]
        file_meta{{"file_meta<br/>(if not_has_files)"}}
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
    MERMAID
  end
end
