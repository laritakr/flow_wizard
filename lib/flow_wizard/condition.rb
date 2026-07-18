# frozen_string_literal: true

module FlowWizard
  # A named, introspectable predicate over (state, config). Steps reference
  # conditions by name so the navigator can evaluate them AND the diagram can label
  # them (an opaque inline lambda can be evaluated but not described).
  #
  # A condition with a +detour+ step name is a *prerequisite*: when unmet, a step
  # requiring it redirects to +detour+ instead of rendering.
  #
  # A condition with a +negates+ name is the inverse of another condition (created
  # by the builder's `skip_unless:`). Keeping the link lets the diagram render a
  # *positive* label ("when adding") instead of the internal double negative
  # ("if not_adding").
  Condition = Struct.new(:name, :predicate, :detour, :negates, keyword_init: true) do
    def met?(state, config)
      !!predicate.call(state, config)
    end

    def prerequisite?
      !detour.nil?
    end

    # The condition this one is the inverse of, or nil.
    def negation?
      !negates.nil?
    end
  end
end
