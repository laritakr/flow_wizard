# frozen_string_literal: true

require "flow_wizard/support"

module FlowWizard
  # One step in a flow, as declarative data. Fields:
  # - +name+       the step key (matches the app's view/route for the step).
  # - +requires+   named prerequisite condition(s) (Symbol or Array). A step whose
  #                prerequisite is unmet detours to the condition's +detour+ step.
  # - +skip_if+    a Symbol naming a condition, or a raw ->(state, config) lambda.
  #                When it evaluates truthy the step is skipped (passed over by
  #                next/back, detoured away from if visited directly).
  # - +terminal+   true for a step reached by a non-advance action; terminal steps
  #                are never an advance target.
  # - +on_skip+    where a direct visit to a skipped step lands: :forward (default,
  #                pass through to the next visible step) or :entry (back to the
  #                first step).
  # - rail metadata: +rail_key+ (steps sharing a key collapse to one rail phase),
  #                +rail_if+ (Symbol or lambda gating the phase), +icon+, +label_key+.
  #
  # +skip_if+/+rail_if+ accept a Symbol (a named condition, the documented path —
  # only named conditions get labeled edges in the diagram) or a raw lambda (an
  # escape hatch). The owning Flow supplies the condition registry when evaluating.
  Step = Struct.new(
    :name, :requires, :skip_if, :terminal, :on_skip,
    :rail_key, :rail_if, :icon, :label_key,
    keyword_init: true
  ) do
    def visible?(state, config, conditions = {})
      skip_if.nil? || !evaluate(skip_if, state, config, conditions)
    end

    def rail_visible?(state, config, conditions = {})
      Support.present?(rail_key) &&
        (rail_if.nil? || evaluate(rail_if, state, config, conditions))
    end

    def terminal?
      !!terminal
    end

    # The names of this step's prerequisite conditions, as symbols.
    def prerequisite_names
      Array(requires).map(&:to_sym)
    end

    # The name of the skip condition when it is a named Symbol (not a raw lambda),
    # or nil. Used by the diagram to label a conditional step.
    def skip_condition_name
      skip_if if skip_if.is_a?(Symbol)
    end

    def conditional?
      !skip_if.nil?
    end

    private

    # A skip_if/rail_if entry is either a Symbol (resolve against the registry) or a
    # callable lambda. Returns truthy/falsey.
    def evaluate(entry, state, config, conditions)
      if entry.is_a?(Symbol)
        condition = conditions.fetch(entry) do
          raise KeyError, "unknown condition #{entry.inspect} on step #{name.inspect}"
        end
        condition.met?(state, config)
      else
        entry.call(state, config)
      end
    end
  end
end
