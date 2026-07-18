# frozen_string_literal: true

# The gem must load with nothing but its own require — no Rails, no ActiveSupport,
# no host framework. If this line needed anything else, the extraction leaked.
require "flow_wizard"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
