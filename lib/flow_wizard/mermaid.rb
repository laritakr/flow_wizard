# frozen_string_literal: true

module FlowWizard
  # Renders a Flow as a Mermaid `flowchart` string — a self-documenting diagram that
  # drops straight into GitHub markdown, a PR description, or docs, with no image
  # dependency. It reads only introspectable data, so it shows structure, not the
  # bodies of predicates:
  #
  # - Nodes: each step. Terminal steps use a stadium shape; conditional steps (a
  #   named skip condition) are annotated with that condition name.
  # - Solid edges: the sequential walk (step order, terminals excluded from the
  #   forward spine but shown as an endpoint).
  # - Dashed labeled edges: prerequisite detours — a step that `requires` a
  #   condition points to that condition's detour step, labeled with the condition
  #   name (readable precisely because the condition is NAMED, not an inline lambda).
  class Mermaid
    def initialize(flow)
      @flow = flow
    end

    # @param direction [String] Mermaid flow direction (default "TD" top-down).
    # @return [String] the flowchart source.
    def render(direction: "TD")
      lines = ["flowchart #{direction}"]
      lines.concat(node_lines)
      lines.concat(sequential_edge_lines)
      lines.concat(prerequisite_edge_lines)
      lines.join("\n")
    end

    private

    attr_reader :flow

    def node_lines
      flow.steps.map { |step| "  #{node(step)}" }
    end

    # A step's node declaration, shaped by terminal/conditional.
    def node(step)
      label = node_label(step)
      if step.terminal?
        "#{id(step.name)}([#{label}])" # stadium = terminal endpoint
      elsif step.skip_condition_name
        "#{id(step.name)}{{#{label}}}" # hexagon = conditional
      else
        "#{id(step.name)}[#{label}]" # rectangle = plain step
      end
    end

    def node_label(step)
      cond = step.skip_condition_name
      cond ? "#{step.name}<br/>(if #{cond})" : step.name
    end

    # Solid edges along the step order (terminals are endpoints, not spine links).
    def sequential_edge_lines
      spine = flow.steps.reject(&:terminal?)
      edges = spine.each_cons(2).map { |a, b| "  #{id(a.name)} --> #{id(b.name)}" }
      # Link the last non-terminal step to each terminal step (usually one: done).
      last = spine.last
      flow.steps.select(&:terminal?).each do |term|
        edges << "  #{id(last.name)} --> #{id(term.name)}" if last
      end
      edges
    end

    # Dashed detour edges from a step to the step its unmet prerequisite provides.
    def prerequisite_edge_lines
      flow.steps.flat_map do |step|
        step.prerequisite_names.filter_map do |req|
          condition = flow.conditions[req]
          next unless condition&.prerequisite?

          "  #{id(step.name)} -. needs #{req} .-> #{id(condition.detour)}"
        end
      end
    end

    # Mermaid node ids must be identifier-safe; step names are already simple, but
    # normalize just in case.
    def id(name)
      name.to_s.gsub(/[^A-Za-z0-9_]/, "_")
    end
  end
end
