# frozen_string_literal: true

module FlowWizard
  # Base for a flow's server-side state: a thin wrapper over a plain hash (typically
  # the session bag) that round-trips across the per-step request cycle. Subclass it
  # and add typed accessors for your domain's slots; every slot reads/writes the
  # backing hash with string keys.
  #
  #   class MyState < FlowWizard::State
  #     def path;        store["path"]; end
  #     def path=(value) store["path"] = value; end
  #   end
  #
  # The store is entirely external — the gem never touches a session object; it
  # wraps whatever hash you hand it.
  class State
    def initialize(store = nil)
      @store = store || {}
    end

    # A namespaced bag for extra state a step needs to persist without adding a
    # first-class slot. Round-trips like the built-in slots.
    def extra
      store["extra"] ||= {}
    end

    # The raw backing hash, for assignment back into the session.
    def to_h
      store
    end

    protected

    attr_reader :store
  end
end
