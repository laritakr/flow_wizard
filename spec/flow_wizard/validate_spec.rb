# frozen_string_literal: true

require "spec_helper"

# Flow#validate reports structural/referential problems that the navigator would
# otherwise hit silently at runtime. It checks assembled Flow data (steps, conditions,
# branches, decisions) and returns a list of human-readable messages — [] when clean.
#
# Flows are built with Flow.new + raw Steps here on purpose: the builder DSL raises on
# some of these mistakes at declaration time, so to reach a *built* Flow carrying the
# error we construct it directly.
RSpec.describe "FlowWizard::Flow#validate" do
  def flow(steps, **kwargs)
    FlowWizard::Flow.new(steps, **kwargs)
  end

  def step(name, **fields)
    FlowWizard::Step.new(name: name, **fields)
  end

  def condition(name, detour: nil)
    FlowWizard::Condition.new(name: name, predicate: ->(_s, _c) { true }, detour: detour)
  end

  describe "a well-formed flow" do
    it "reports no problems" do
      f = flow(
        [step("start"), step("known_type"),
         step("details", requires: :work_type),
         step("done", terminal: true)],
        conditions: { work_type: condition(:work_type, detour: "known_type") }
      )
      expect(f.validate).to eq([])
      expect(f).to be_valid
    end
  end

  describe "unknown condition references" do
    it "flags a skip_if naming a condition that was never declared" do
      f = flow([step("a", skip_if: :missing), step("done", terminal: true)])
      expect(f.validate).to include(a_string_matching(/step "a".*unknown condition :missing/))
    end

    it "flags a rail_if naming an undeclared condition" do
      f = flow([step("a", rail_key: :phase, rail_if: :missing), step("done", terminal: true)])
      expect(f.validate).to include(a_string_matching(/step "a".*rail_if.*:missing/))
    end

    it "does not flag a raw lambda skip_if (only named conditions are checkable)" do
      f = flow([step("a", skip_if: ->(_s, _c) { true }), step("done", terminal: true)])
      expect(f.validate).to eq([])
    end
  end

  describe "prerequisite references" do
    it "flags a requires naming a condition that is not a prerequisite (no detour)" do
      f = flow(
        [step("a", requires: :plain), step("done", terminal: true)],
        conditions: { plain: condition(:plain) } # no detour: -> not a prerequisite
      )
      expect(f.validate).to include(a_string_matching(/step "a".*requires :plain.*not a prerequisite/))
    end

    it "flags a requires naming an undeclared condition" do
      f = flow([step("a", requires: :missing), step("done", terminal: true)])
      expect(f.validate).to include(a_string_matching(/step "a".*requires :missing.*not declared/))
    end

    it "flags a prerequisite whose detour step does not exist" do
      f = flow(
        [step("a", requires: :work_type), step("done", terminal: true)],
        conditions: { work_type: condition(:work_type, detour: "ghost") }
      )
      expect(f.validate).to include(a_string_matching(/prerequisite :work_type.*detour.*"ghost".*does not exist/))
    end
  end

  describe "terminal steps" do
    it "flags a flow with no terminal step" do
      f = flow([step("a"), step("b")])
      expect(f.validate).to include(a_string_matching(/no terminal step/))
    end

    it "does not flag multiple terminal steps (several exits are allowed)" do
      f = flow([step("a"), step("done", terminal: true), step("cancelled", terminal: true)])
      expect(f.validate).to eq([])
    end
  end

  describe "branch references" do
    it "flags a branch case pointing at a step that does not exist" do
      f = flow(
        [step("start"), step("done", terminal: true)],
        branches: [{ variable: :mode, cases: [{ value: "x", step: "ghost", condition: :mode_is_x }] }]
      )
      expect(f.validate).to include(a_string_matching(/branch :mode.*case "x".*step "ghost".*does not exist/))
    end
  end

  describe "decision references" do
    it "flags a decision whose from step does not exist" do
      f = flow(
        [step("start"), step("done", terminal: true)],
        decisions: [{ variable: :path, from: "ghost", cases: [{ value: "a", to: "start" }] }]
      )
      expect(f.validate).to include(a_string_matching(/decision :path.*from.*"ghost".*does not exist/))
    end

    it "flags a decision route pointing at a step that does not exist" do
      f = flow(
        [step("start"), step("done", terminal: true)],
        decisions: [{ variable: :path, from: "start", cases: [{ value: "a", to: "ghost" }] }]
      )
      expect(f.validate).to include(a_string_matching(/decision :path.*route "a".*"ghost".*does not exist/))
    end
  end

  describe "validate! (raising variant)" do
    it "raises with all problems joined when invalid" do
      f = flow([step("a", skip_if: :missing)])
      expect { f.validate! }.to raise_error(FlowWizard::Flow::InvalidFlow, /unknown condition :missing/)
    end

    it "returns the flow when valid" do
      f = flow([step("a"), step("done", terminal: true)])
      expect(f.validate!).to equal(f)
    end
  end
end
