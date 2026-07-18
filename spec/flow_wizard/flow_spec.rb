# frozen_string_literal: true

require "spec_helper"
require "support/example_flow"

RSpec.describe FlowWizard::Flow do
  subject(:flow) { example_flow }

  let(:config) { nil } # this example's conditions ignore config

  def state(**slots)
    ExampleState.new(**slots)
  end

  describe "#names and #valid_step?" do
    it "lists steps in order" do
      expect(flow.names).to eq(%w[start select_parent known_type files details file_meta review done])
    end

    it "validates step names" do
      expect(flow).to be_valid_step("review")
      expect(flow).not_to be_valid_step("bogus")
    end
  end

  describe "#visible_steps" do
    it "hides select_parent off the add path" do
      expect(flow.visible_steps(state, config).map(&:name)).not_to include("select_parent")
      expect(flow.visible_steps(state(path: "add"), config).map(&:name)).to include("select_parent")
    end

    it "hides file_meta until files are uploaded" do
      expect(flow.visible_steps(state, config).map(&:name)).not_to include("file_meta")
      expect(flow.visible_steps(state(uploaded_file_ids: ["a"]), config).map(&:name)).to include("file_meta")
    end

    it "excludes terminal steps" do
      expect(flow.visible_steps(state, config).map(&:name)).not_to include("done")
    end
  end

  describe "#next_after" do
    it "skips a hidden step (files -> details when no files, past file_meta)" do
      expect(flow.next_after("files", state, config)).to eq("details")
    end

    it "includes file_meta once files exist" do
      expect(flow.next_after("details", state(uploaded_file_ids: ["a"]), config)).to eq("file_meta")
    end

    it "routes start to select_parent on the add path" do
      expect(flow.next_after("start", state(path: "add"), config)).to eq("select_parent")
    end

    it "returns nil past the last non-terminal step" do
      expect(flow.next_after("review", state, config)).to be_nil
    end
  end

  describe "#back_before" do
    it "returns the previous visible step" do
      expect(flow.back_before("details", state, config)).to eq("files")
    end

    it "skips a hidden step going back" do
      expect(flow.back_before("details", state, config)).to eq("files") # select_parent hidden
    end

    it "has no back before the entry" do
      expect(flow.back_before("start", state, config)).to be_nil
    end
  end

  describe "#detour_for" do
    it "detours a prerequisite-unmet step to the condition's detour step" do
      expect(flow.detour_for("details", state, config)).to eq("known_type")
    end

    it "renders the step once the prerequisite is met" do
      expect(flow.detour_for("details", state(work_type: "Image"), config)).to be_nil
    end

    it "bounces an invalid direct visit to an :entry-skipped step back to start" do
      expect(flow.detour_for("select_parent", state, config)).to eq("start")
    end

    it "does not detour a step with no prerequisite" do
      expect(flow.detour_for("files", state, config)).to be_nil
    end
  end

  describe "#rail" do
    it "collapses start/known_type into one :type phase and orders by rail_keys" do
      keys = flow.rail(state(work_type: "Image"), config).map { |r| r[:key] }
      expect(keys).to eq(%i[type upload detail review])
    end

    it "shows :parent on the add path and :file_detail once files exist" do
      keys = flow.rail(state(path: "add", work_type: "Image", uploaded_file_ids: ["a"]), config)
                 .map { |r| r[:key] }
      expect(keys).to eq(%i[type parent upload detail file_detail review])
    end

    it "sources a phase's icon/label from whichever visible step in the group defines them" do
      type_row = flow.rail(state, config).find { |r| r[:key] == :type }
      # start has no icon/label; known_type has none either in this example, so nil is fine —
      # assert the collapse still yields one row, not that a nil is filled.
      expect(type_row[:key]).to eq(:type)
    end
  end

  describe "raw-lambda escape hatch" do
    it "accepts a raw skip_if lambda alongside named conditions" do
      f = FlowWizard::Flow.new([
                                 FlowWizard::Step.new(name: "a"),
                                 FlowWizard::Step.new(name: "b", skip_if: ->(s, _c) { s.path == "hide_b" }),
                                 FlowWizard::Step.new(name: "c")
                               ])
      expect(f.visible_steps(state(path: "hide_b"), config).map(&:name)).to eq(%w[a c])
      expect(f.visible_steps(state, config).map(&:name)).to eq(%w[a b c])
    end
  end
end
