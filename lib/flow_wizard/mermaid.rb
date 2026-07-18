# frozen_string_literal: true

module FlowWizard
  # Turns a step name into a Mermaid-safe node id (letters, digits, underscore).
  # Shared by the renderer and its node collaborator so both emit the same ids.
  module MermaidId
    module_function

    def id(name)
      name.to_s.gsub(/[^A-Za-z0-9_]/, "_")
    end
  end

  # Renders each Flow step as a Mermaid node line: a shape by role (stadium terminal,
  # hexagon conditional, plain rectangle) and a label. A conditional step's label is
  # POSITIVE ("when adding"), derived from its named condition rather than the
  # internal double negative ("if not_adding"). A branch-case step stays a plain node
  # — the fork edge carries its condition, so no inline label is added.
  class MermaidNodes
    include MermaidId

    def initialize(flow, branch_by_step)
      @flow = flow
      @branch_by_step = branch_by_step
    end

    def lines
      flow.steps.map { |step| "  #{node(step)}" }
    end

    private

    attr_reader :flow, :branch_by_step

    def node(step)
      label = %("#{node_label(step)}")
      if step.terminal?
        "#{id(step.name)}([#{label}])"
      elsif conditional_label(step)
        "#{id(step.name)}{{#{label}}}"
      else
        "#{id(step.name)}[#{label}]"
      end
    end

    def node_label(step)
      cond = conditional_label(step)
      cond ? "#{step.name}<br/>#{cond}" : step.name
    end

    # A positive, readable condition phrase for a conditional step, or nil.
    def conditional_label(step)
      return nil if branch_by_step.key?(step.name)
      return nil unless step.skip_condition_name

      cond = flow.conditions[step.skip_condition_name]
      if cond&.negation?
        "(when #{cond.negates})" # skip_unless :adding -> "when adding"
      else
        "(unless #{step.skip_condition_name})"
      end
    end
  end

  # Renders a Flow as a Mermaid `flowchart` string — a self-documenting diagram that
  # drops straight into GitHub markdown, a PR description, or docs, with no image
  # dependency. It reads only introspectable data, so it shows structure, not the
  # bodies of predicates.
  #
  # It aims to read like the *process*, not the raw step array:
  # - Conditional steps carry a POSITIVE label ("when adding") — see MermaidNodes.
  # - A declared `branch` renders as a real fork: the step before it points to each
  #   alternative with a value-labeled edge, and the alternatives converge again —
  #   rather than a misleading straight line through mutually-exclusive steps.
  # - Prerequisite detours are dashed labeled edges.
  class Mermaid
    include MermaidId

    def initialize(flow)
      @flow = flow
      @branch_by_step = index_branch_steps
    end

    def render(direction: "TD")
      lines = ["flowchart #{direction}"]
      lines.concat(MermaidNodes.new(flow, branch_by_step).lines)
      lines.concat(edge_lines)
      lines.concat(prerequisite_edge_lines)
      lines.join("\n")
    end

    private

    attr_reader :flow, :branch_by_step

    # step name => the branch it participates in (as a case), for edge routing.
    def index_branch_steps
      flow.branches.each_with_object({}) do |branch, map|
        branch[:cases].each { |c| map[c[:step]] = branch }
      end
    end

    # The forward walk, rerouted around branches so alternatives fork and converge
    # instead of chaining through each other.
    def edge_lines
      spine = flow.steps.reject(&:terminal?)
      edges = []
      index = 0
      while index < spine.length
        branch = branch_starting_at(spine, index)
        if branch
          edges.concat(branch_edges(spine, index, branch))
          index += branch[:cases].length + 1 # skip the fork step + its case steps
        else
          edges.concat(linear_edge(spine, index))
          index += 1
        end
      end
      edges.concat(terminal_edges(spine.last))
      edges
    end

    # The single forward edge from the step at +index+ to its successor, unless the
    # successor is a branch case (a fork edge covers that).
    def linear_edge(spine, index)
      step = spine[index]
      nxt = spine[index + 1]
      return [] unless nxt && !branch_by_step.key?(nxt.name)

      ["  #{id(step.name)} --> #{id(nxt.name)}"]
    end

    # If the steps immediately after +index+ are exactly this branch's cases, return
    # the branch; else nil. (Branch cases are declared consecutively.)
    def branch_starting_at(spine, index)
      nxt = spine[index + 1]
      return nil unless nxt

      branch = branch_by_step[nxt.name]
      return nil unless branch

      case_names = branch[:cases].map { |c| c[:step] }
      window = spine[(index + 1)...(index + 1 + case_names.length)]&.map(&:name)
      branch if window == case_names
    end

    # fork: source --|value|--> each case; each case --> the step after the branch.
    def branch_edges(spine, index, branch)
      source = spine[index]
      after = spine[index + 1 + branch[:cases].length]
      branch[:cases].flat_map do |c|
        edges = ["  #{id(source.name)} -->|#{c[:value]}| #{id(c[:step])}"]
        edges << "  #{id(c[:step])} --> #{id(after.name)}" if after
        edges
      end
    end

    def terminal_edges(last_non_terminal)
      return [] unless last_non_terminal

      flow.steps.select(&:terminal?).map do |term|
        "  #{id(last_non_terminal.name)} --> #{id(term.name)}"
      end
    end

    def prerequisite_edge_lines
      flow.steps.flat_map do |step|
        step.prerequisite_names.filter_map do |req|
          condition = flow.conditions[req]
          next unless condition&.prerequisite?
          next if condition.detour == step.name # the step that fulfills it needs no self-edge

          "  #{id(step.name)} -. needs #{req} .-> #{id(condition.detour)}"
        end
      end
    end
  end
end
