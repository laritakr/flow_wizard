# frozen_string_literal: true

require "flow_wizard/flow"
require "flow_wizard/step"
require "flow_wizard/condition"

module FlowWizard
  # A small DSL for assembling a Flow legibly. It is pure sugar: it accumulates
  # +condition+/+prerequisite+/+step+ declarations and returns a plain Flow with the
  # same Step data you could build by hand. Its value is readability — named
  # conditions read as intent, and only named conditions get labeled diagram edges.
  #
  #   FlowWizard::Flow.build do
  #     condition :adding,       ->(s, _c) { s.path == "add" }
  #     prerequisite :work_type, ->(s, _c) { s.work_type }, detour: :known_type
  #
  #     step :start
  #     step :select_parent, skip_unless: :adding, on_skip: :entry, rail: :parent
  #     step :known_type, requires: :work_type, rail: :type
  #     step :done, terminal: true
  #   end
  class Builder
    def initialize
      @conditions = {}
      @steps = []
      @rail_keys = nil
    end

    def build(&block)
      instance_eval(&block) if block
      Flow.new(@steps, rail_keys: @rail_keys, conditions: @conditions)
    end

    # A named predicate over (state, config), referenced by skip_unless/skip_if/rail_if.
    def condition(name, predicate)
      @conditions[name.to_sym] = Condition.new(name: name.to_sym, predicate: predicate)
    end

    # A named prerequisite: when the predicate is unmet, a step that +requires+ it
    # detours to +detour+.
    def prerequisite(name, predicate, detour:)
      @conditions[name.to_sym] = Condition.new(name: name.to_sym, predicate: predicate, detour: detour.to_s)
    end

    # Override the rail phase order (defaults to the order steps introduce rail keys).
    def rail_order(*keys)
      @rail_keys = keys.flatten.map(&:to_sym)
    end

    # Declare a step. DSL conveniences over the raw Step:
    # - +skip_unless+: a condition name; the step shows only when it is met (the
    #   readable inverse of skip_if). Provide EITHER skip_unless OR skip_if.
    # - +skip_if+: a condition name or lambda; the step is skipped when truthy.
    # - +rail+: shorthand for rail_key.
    # - +rail_if+: a condition name or lambda gating the rail phase.
    def step(name, requires: nil, skip_unless: nil, skip_if: nil, on_skip: nil,
             terminal: false, rail: nil, rail_if: nil, icon: nil, label_key: nil)
      raise ArgumentError, "step #{name}: use skip_unless OR skip_if, not both" if skip_unless && skip_if

      @steps << Step.new(
        name: name.to_s,
        requires: requires && Array(requires).map(&:to_sym),
        skip_if: skip_unless ? negated(skip_unless) : skip_if,
        terminal: terminal,
        on_skip: on_skip,
        rail_key: rail,
        rail_if: rail_if,
        icon: icon,
        label_key: label_key
      )
    end

    private

    # `skip_unless: :adding` means "skip when NOT adding". Register the inverse as a
    # derived named condition so it still reads/labels as a name in the diagram.
    def negated(condition_name)
      base = @conditions.fetch(condition_name.to_sym) do
        raise KeyError, "skip_unless references unknown condition #{condition_name.inspect}"
      end
      inverse = :"not_#{base.name}"
      @conditions[inverse] ||= Condition.new(
        name: inverse,
        predicate: ->(state, config) { !base.met?(state, config) }
      )
      inverse
    end
  end
end
