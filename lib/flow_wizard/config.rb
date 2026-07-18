# frozen_string_literal: true

require "flow_wizard/flow"

module FlowWizard
  # Base for a flow's configuration seam: holds a swappable Flow plus whatever
  # settings your app needs. Subclass it to add app-specific settings and
  # capabilities (feature flags, host config) — those stay in your subclass, not the
  # gem, so the engine carries no host coupling.
  #
  #   class MyConfig < FlowWizard::Config
  #     attr_accessor :container_type
  #   end
  #
  # An app assigns its own flow (`config.flow = FlowWizard::Flow.build { ... }`); the
  # default is an empty flow so a bare Config is usable.
  class Config
    attr_writer :flow

    def flow
      @flow ||= default_flow
    end

    private

    # Subclasses override to supply their built-in flow. The base default is empty.
    def default_flow
      Flow.new([])
    end
  end
end
