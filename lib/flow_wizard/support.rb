# frozen_string_literal: true

module FlowWizard
  # Tiny presence helpers so the gem carries no ActiveSupport dependency. These
  # mirror ActiveSupport's blank?/present?/presence for the handful of call sites
  # the extracted engine needs (strings, arrays, nil).
  module Support
    module_function

    # Nil, or an object that is empty (""/[]/{}) or all-whitespace (a String).
    def blank?(value)
      return true if value.nil?
      return value.strip.empty? if value.is_a?(String)
      return value.empty? if value.respond_to?(:empty?)

      false
    end

    def present?(value)
      !blank?(value)
    end

    # The value if present, else nil (ActiveSupport's #presence).
    def presence(value)
      value if present?(value)
    end
  end
end
