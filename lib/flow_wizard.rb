# frozen_string_literal: true

require "flow_wizard/version"
require "flow_wizard/support"
require "flow_wizard/condition"
require "flow_wizard/transition"
require "flow_wizard/step"
require "flow_wizard/flow"
require "flow_wizard/builder"
require "flow_wizard/mermaid"
require "flow_wizard/state"
require "flow_wizard/config"

# A declarative, self-documenting multi-step flow engine. A flow is an ordered list
# of Steps (plain data) plus a navigator (next/back/detour/skip/rail). Steps
# reference named conditions, so the flow is both buildable (Flow.build DSL) and
# diagrammable (Flow#to_mermaid). The engine is dependency-free and controller-
# agnostic: your app queries it, it never owns the request cycle.
module FlowWizard
end
