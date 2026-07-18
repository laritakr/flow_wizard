# frozen_string_literal: true

require "flow_wizard/step"
require "flow_wizard/condition"

module FlowWizard
  # A flow is an ordered list of Steps plus a navigator (next/back/detour/rail)
  # computed from each Step's declared rules — so ordering, skips, prerequisites,
  # and the progress rail live in one place as swappable data. An app reshapes the
  # flow by assigning a new Flow, not by editing flow logic.
  #
  # Conditions (named predicates a step's skip_if/rail_if/requires reference) are
  # injected here rather than hardcoded, so the same navigator serves any domain.
  # Build a Flow directly (`Flow.new(steps, conditions:)`) or via the DSL
  # (`Flow.build { ... }`, see Builder).
  class Flow
    attr_reader :steps, :rail_keys, :conditions

    # @param steps [Array<Step>] the ordered step list.
    # @param rail_keys [Array<Symbol>] progress-rail phase order (its OWN order, so
    #   several steps can collapse into one phase and phases can differ from walk
    #   order). Defaults to the distinct rail_keys in step order.
    # @param conditions [Hash{Symbol=>Condition}] the named-condition registry.
    def initialize(steps, rail_keys: nil, conditions: {})
      @steps = steps
      @conditions = conditions
      @rail_keys = rail_keys || default_rail_keys
    end

    # @return [Flow] built from the DSL (see Builder).
    def self.build(&block)
      require "flow_wizard/builder"
      Builder.new.build(&block)
    end

    def names
      steps.map(&:name)
    end

    def valid_step?(name)
      names.include?(name.to_s)
    end

    def step(name)
      steps.find { |s| s.name == name.to_s }
    end

    # Renderable steps for the current state: non-terminal and not skipped.
    def visible_steps(state, config)
      steps.reject(&:terminal?).select { |s| s.visible?(state, config, conditions) }
    end

    # The next visible, non-terminal step after +name+, or nil at the end. Uses the
    # FULL step order to locate +name+ (so a skipped step still has a position) then
    # scans forward for the next visible step.
    def next_after(name, state, config)
      after = steps.drop_while { |s| s.name != name.to_s }.drop(1)
      after.find { |s| !s.terminal? && s.visible?(state, config, conditions) }&.name
    end

    # The previous visible step before +name+, or nil at the entry (the root).
    def back_before(name, state, config)
      before = steps.take_while { |s| s.name != name.to_s }
      before.reverse.find { |s| !s.terminal? && s.visible?(state, config, conditions) }&.name
    end

    # Where a requested step should redirect instead of rendering, or nil to render
    # it: to the step fulfilling an unmet prerequisite, or (if the step is skipped
    # in the current state) on to its next visible step / the entry.
    def detour_for(name, state, config)
      target = step(name)
      return nil if target.nil?

      target.prerequisite_names.each do |req|
        condition = conditions[req]
        return condition.detour if condition&.prerequisite? && !condition.met?(state, config)
      end

      return nil if target.visible?(state, config, conditions)

      # A skipped step: :entry sends an invalid direct visit back to the start;
      # otherwise pass through to the next visible step.
      return names.first if target.on_skip == :entry

      next_after(name, state, config) || back_before(name, state, config) || names.first
    end

    # The progress rail, in +rail_keys+ order. A phase appears only when a visible
    # step maps to it; its icon/label come from whichever visible step in the group
    # defines them (collapsed steps need not all carry them). Order is the rail_keys
    # list, NOT the step sequence, so display and flow order stay independent.
    def rail(state, config)
      rail_keys.filter_map do |key|
        group = visible_steps(state, config)
                .select { |s| s.rail_key == key && s.rail_visible?(state, config, conditions) }
        next if group.empty?

        { key: key,
          icon: group.filter_map(&:icon).first,
          label_key: group.filter_map(&:label_key).first }
      end
    end

    # A Mermaid flowchart of this flow's structure. See Mermaid.
    def to_mermaid(**options)
      require "flow_wizard/mermaid"
      Mermaid.new(self).render(**options)
    end

    private

    # Distinct rail_keys in the order steps first introduce them.
    def default_rail_keys
      steps.filter_map(&:rail_key).uniq
    end
  end
end
