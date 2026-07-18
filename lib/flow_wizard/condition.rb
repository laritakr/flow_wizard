# frozen_string_literal: true

module FlowWizard
  # A named, introspectable predicate over (state, config). Steps reference
  # conditions by name so the navigator can evaluate them AND the diagram can label
  # them (an opaque inline lambda can be evaluated but not described).
  #
  # A condition with a +detour+ step name is a *prerequisite*: when unmet, a step
  # requiring it redirects to +detour+ instead of rendering.
  Condition = Struct.new(:name, :predicate, :detour, keyword_init: true) do
    def met?(state, config)
      !!predicate.call(state, config)
    end

    def prerequisite?
      !detour.nil?
    end
  end
end
