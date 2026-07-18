# frozen_string_literal: true

require "spec_helper"

RSpec.describe FlowWizard::Builder do
  describe "parity: the DSL is sugar over Flow.new" do
    it "produces the same step names and order as a hand-built Flow" do
      built = FlowWizard::Flow.build do
        step :a
        step :b, rail: :mid
        step :done, terminal: true
      end

      hand = FlowWizard::Flow.new([
                                    FlowWizard::Step.new(name: "a"),
                                    FlowWizard::Step.new(name: "b", rail_key: :mid),
                                    FlowWizard::Step.new(name: "done", terminal: true)
                                  ])

      expect(built.names).to eq(hand.names)
      expect(built.step("b").rail_key).to eq(hand.step("b").rail_key)
      expect(built.step("done").terminal?).to be(true)
    end
  end

  describe "skip_unless" do
    let(:state) { Struct.new(:on).new(false) }

    it "shows the step only when the named condition is met (inverse of skip_if)" do
      flow = FlowWizard::Flow.build do
        condition :on, ->(s, _c) { s.on }
        step :always
        step :gated, skip_unless: :on
      end

      state.on = false
      expect(flow.visible_steps(state, nil).map(&:name)).to eq(%w[always])
      state.on = true
      expect(flow.visible_steps(state, nil).map(&:name)).to eq(%w[always gated])
    end

    it "rejects declaring both skip_unless and skip_if" do
      expect do
        FlowWizard::Flow.build do
          condition :on, ->(_s, _c) { true }
          step :x, skip_unless: :on, skip_if: :on
        end
      end.to raise_error(ArgumentError, /skip_unless OR skip_if/)
    end

    it "raises for a skip_unless referencing an unknown condition" do
      expect do
        FlowWizard::Flow.build { step :x, skip_unless: :nope }
      end.to raise_error(KeyError, /unknown condition/)
    end
  end

  describe "prerequisite" do
    it "registers a detour condition consumed by detour_for" do
      state = Struct.new(:ready).new(false)
      flow = FlowWizard::Flow.build do
        prerequisite :ready, ->(s, _c) { s.ready }, detour: :setup
        step :setup
        step :guarded, requires: :ready
      end

      expect(flow.detour_for("guarded", state, nil)).to eq("setup")
      state.ready = true
      expect(flow.detour_for("guarded", state, nil)).to be_nil
    end
  end

  describe "an unknown condition symbol at evaluation time" do
    it "raises a clear KeyError naming the step" do
      flow = FlowWizard::Flow.new([FlowWizard::Step.new(name: "x", skip_if: :missing)])
      expect { flow.visible_steps(Object.new, nil) }
        .to raise_error(KeyError, /unknown condition :missing on step "x"/)
    end
  end
end
