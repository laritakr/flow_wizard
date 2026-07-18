# frozen_string_literal: true

require "flow_wizard/flow"
require "flow_wizard/step"
require "flow_wizard/condition"

module FlowWizard
  # A small DSL for assembling a Flow legibly. It is pure sugar: it accumulates
  # +condition+/+prerequisite+/+branch+/+step+ declarations and returns a plain Flow
  # with the same Step data you could build by hand. Its value is readability —
  # named conditions read as intent, and the diagram renders them (positive labels
  # for skip_unless, real forks for branches).
  #
  #   FlowWizard::Flow.build do
  #     condition :adding,       ->(s, _c) { s.path == "add" }
  #     prerequisite :work_type, ->(s, _c) { s.work_type }, detour: :known_type
  #     branch :type_mode, on: ->(s, _c) { s.type_mode },
  #            known: :known_type, guided: :guided_confirm
  #
  #     step :start
  #     step :select_parent, skip_unless: :adding, on_skip: :entry, rail: :parent
  #     step :known_type, requires: :work_type, rail: :type
  #     step :guided_confirm, rail: :type
  #     step :done, terminal: true
  #   end
  class Builder
    def initialize
      @conditions = {}
      @branches = []
      @step_options = {}
      @steps = []
      @rail_keys = nil
    end

    def build(&block)
      instance_eval(&block) if block
      apply_branches
      Flow.new(@steps, rail_keys: @rail_keys, conditions: @conditions, branches: @branches)
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

    # A mutually-exclusive branch keyed on one decision variable. `on:` extracts the
    # variable from state; the remaining keyword args map each value to the step that
    # runs for it. Each mapped step shows only when the variable equals its value —
    # so declare the steps separately (with their rail/icon/etc.); this just adds the
    # skip condition and records the fork for the diagram.
    #
    #   branch :type_mode, on: ->(s, _c) { s.type_mode },
    #          known: :known_type, guided: :guided_confirm
    def branch(variable, on:, **value_to_step)
      cases = value_to_step.map do |value, step_name|
        cond_name = :"#{variable}_is_#{value}"
        @conditions[cond_name] ||= Condition.new(
          name: cond_name, predicate: ->(state, config) { on.call(state, config) == value.to_s }
        )
        # The step shows only for this value: record a skip_unless on it, applied
        # after all steps are declared (order-independent).
        @step_options[step_name.to_sym] = { skip_unless: cond_name }
        { value: value.to_s, step: step_name.to_s, condition: cond_name }
      end
      @branches << { variable: variable.to_sym, cases: cases }
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

    # Apply branch-declared skip conditions to their steps (after all step()s, so a
    # branch can be declared before or after the steps it gates).
    def apply_branches
      @step_options.each do |step_name, opts|
        target = @steps.find { |s| s.name == step_name.to_s }
        raise KeyError, "branch references unknown step #{step_name.inspect}" unless target

        # Don't clobber an explicit skip already on the step.
        target.skip_if ||= negated(opts[:skip_unless])
      end
    end

    # `skip_unless: :adding` means "skip when NOT adding". Register the inverse as a
    # derived named condition, linked back to its base so the diagram can render a
    # positive label.
    def negated(condition_name)
      base = @conditions.fetch(condition_name.to_sym) do
        raise KeyError, "skip_unless references unknown condition #{condition_name.inspect}"
      end
      inverse = :"not_#{base.name}"
      @conditions[inverse] ||= Condition.new(
        name: inverse,
        predicate: ->(state, config) { !base.met?(state, config) },
        negates: base.name
      )
      inverse
    end
  end
end
