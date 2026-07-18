# frozen_string_literal: true

require "set"

module FlowWizard
  # Reports flow lambdas that can't be called with (state, config). Arity is
  # introspectable even though the body is not, so a wrong-arity lambda — which would
  # otherwise raise ArgumentError mid-navigation — is caught at build time. Covers named
  # condition predicates and raw skip_if/rail_if lambdas on steps.
  class LambdaArity
    def initialize(flow)
      @flow = flow
    end

    def problems
      condition_problems + step_problems
    end

    private

    attr_reader :flow

    def condition_problems
      flow.conditions.values.filter_map do |condition|
        next if callable_with_two?(condition.predicate)

        "condition #{condition.name.inspect}: lambda must accept (state, config) — " \
          "has arity #{condition.predicate.arity}"
      end
    end

    def step_problems
      flow.steps.flat_map do |step|
        [[step.skip_if, "skip_if"], [step.rail_if, "rail_if"]].filter_map do |entry, label|
          next unless entry.respond_to?(:arity) # a Symbol names a condition, checked elsewhere
          next if callable_with_two?(entry)

          "step #{step.name.inspect}: #{label} lambda must accept (state, config) — " \
            "has arity #{entry.arity}"
        end
      end
    end

    # True if the lambda can be called with exactly two positional args. A non-negative
    # arity must be 2; a negative arity -n requires (n-1) args, so it must need at most 2.
    def callable_with_two?(callable)
      arity = callable.arity
      arity >= 0 ? arity == 2 : (-arity - 1) <= 2
    end
  end

  # Checks a built Flow for mistakes the navigator would otherwise hit silently at
  # runtime: a step referencing a condition or step name that doesn't exist, a
  # prerequisite with a dangling detour, a flow with no way out, or a lambda that can't
  # take (state, config) (see LambdaArity). It reads only assembled data, so it catches
  # typos, stale names, and wrong signatures at definition time.
  #
  # Returns a list of human-readable messages; an empty list means the flow is sound. A
  # raw-lambda skip/rail can't have its *logic* checked (only named conditions are
  # resolved), but its arity is.
  class Validator
    def initialize(flow)
      @flow = flow
      @step_names = flow.names.to_set
    end

    def problems
      [
        *terminal_problems,
        *step_reference_problems,
        *prerequisite_detour_problems,
        *branch_problems,
        *decision_problems,
        *arity_problems
      ]
    end

    private

    attr_reader :flow, :step_names

    def conditions
      flow.conditions
    end

    def known_step?(name)
      step_names.include?(name.to_s)
    end

    # A flow needs at least one terminal step, or the walk never ends. Several are fine
    # (multiple exits — done / cancelled / ...).
    def terminal_problems
      return [] if flow.steps.any?(&:terminal?)

      ["flow has no terminal step (declare one with terminal: true)"]
    end

    # Every named skip_if/rail_if/requires on a step must resolve.
    def step_reference_problems
      flow.steps.flat_map do |step|
        [
          *named_condition_problem(step, step.skip_if, "skip_if"),
          *named_condition_problem(step, step.rail_if, "rail_if"),
          *requires_problems(step)
        ]
      end
    end

    # A Symbol skip_if/rail_if must name a declared condition; a lambda is opaque, so
    # it's skipped.
    def named_condition_problem(step, entry, label)
      return [] unless entry.is_a?(Symbol)
      return [] if conditions.key?(entry)

      ["step #{step.name.inspect}: #{label} names unknown condition #{entry.inspect}"]
    end

    # A `requires:` must name a declared condition that is a prerequisite (has a
    # detour) — otherwise the step never actually detours.
    def requires_problems(step)
      step.prerequisite_names.filter_map do |req|
        condition = conditions[req]
        if condition.nil?
          "step #{step.name.inspect}: requires #{req.inspect}, which is not declared"
        elsif !condition.prerequisite?
          "step #{step.name.inspect}: requires #{req.inspect}, which is not a prerequisite " \
            "(declare it with `prerequisite ..., detour:`)"
        end
      end
    end

    # A prerequisite's detour must point at a real step.
    def prerequisite_detour_problems
      conditions.values.filter_map do |condition|
        next unless condition.prerequisite?
        next if known_step?(condition.detour)

        "prerequisite #{condition.name.inspect}: detour step #{condition.detour.inspect} does not exist"
      end
    end

    # Every branch case must point at a real step.
    def branch_problems
      flow.branches.flat_map do |branch|
        branch[:cases].filter_map do |c|
          next if known_step?(c[:step])

          "branch #{branch[:variable].inspect}: case #{c[:value].inspect} names step " \
            "#{c[:step].inspect}, which does not exist"
        end
      end
    end

    # Flow lambdas that can't take (state, config). See LambdaArity.
    def arity_problems
      LambdaArity.new(flow).problems
    end

    # A decision's from-step and every route target must be real steps.
    def decision_problems
      flow.decisions.flat_map do |decision|
        from = decision[:from]
        problems = []
        unless known_step?(from)
          problems << "decision #{decision[:variable].inspect}: from step #{from.inspect} does not exist"
        end
        decision[:cases].each do |c|
          next if known_step?(c[:to])

          problems << "decision #{decision[:variable].inspect}: route #{c[:value].inspect} names step " \
                      "#{c[:to].inspect}, which does not exist"
        end
        problems
      end
    end
  end
end
