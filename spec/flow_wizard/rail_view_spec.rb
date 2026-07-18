# frozen_string_literal: true

require "spec_helper"
require "support/example_flow"

# Flow#rail_view enriches #rail with per-phase status (:done / :current / :upcoming)
# and a 1-based position, so a host view can render a progress strip without
# recomputing where the user is. It adds no dependency — it returns plain hashes.
RSpec.describe "FlowWizard::Flow#rail_view" do
  subject(:flow) { example_flow }

  # example_flow's rail phases (in order): type, parent, upload, detail, file_detail,
  # review — though which appear depends on state (parent only when adding, file_detail
  # only with files).
  def view(current_step:, **slots)
    state = ExampleState.new(**slots)
    flow.rail_view(state, {}, current_step: current_step)
  end

  it "returns the same phases as #rail, in the same order, with extra keys" do
    state = ExampleState.new(path: "add", work_type: "Book", uploaded_file_ids: ["f"])
    plain = flow.rail(state, {})
    enriched = flow.rail_view(state, {}, current_step: "start")

    expect(enriched.map { |p| p[:key] }).to eq(plain.map { |p| p[:key] })
    expect(enriched.first).to include(:key, :icon, :label_key, :status, :position)
  end

  it "numbers phases from 1 in rail order" do
    positions = view(current_step: "start", path: "add",
                     work_type: "Book", uploaded_file_ids: ["f"]).map { |p| p[:position] }
    expect(positions).to eq((1..positions.length).to_a)
  end

  it "marks the current step's phase :current, earlier phases :done, later :upcoming" do
    # walking at `details` (rail_key :detail). Phases before it are done, after upcoming.
    rows = view(current_step: "details", path: "add",
                work_type: "Book", uploaded_file_ids: ["f"])
    by_key = rows.to_h { |p| [p[:key], p[:status]] }

    expect(by_key[:type]).to eq(:done)      # before detail
    expect(by_key[:parent]).to eq(:done)    # before detail
    expect(by_key[:detail]).to eq(:current) # the current step's phase
    expect(by_key[:review]).to eq(:upcoming) # after detail
  end

  it "marks the first phase :current at the start of the flow" do
    rows = view(current_step: "start", path: "add",
                work_type: "Book", uploaded_file_ids: ["f"])
    expect(rows.first[:status]).to eq(:current)
    expect(rows.drop(1)).to all(include(status: :upcoming))
  end

  it "handles a current step whose phase is not visible (all upcoming/done, none current)" do
    # `select_parent` (phase :parent) is skipped when not adding, so a rail built for a
    # non-adding state has no :parent phase. Asking for it as current marks nothing
    # current rather than raising.
    rows = view(current_step: "select_parent", path: "standalone",
                work_type: "Book", uploaded_file_ids: ["f"])
    expect(rows.map { |p| p[:status] }).not_to include(:current)
  end

  it "reflects the collapsed rail (several steps, one phase)" do
    # start and known_type both map to :type — one phase. Current at known_type still
    # marks the single :type phase current.
    rows = view(current_step: "known_type", path: "standalone",
                work_type: "Book", uploaded_file_ids: ["f"])
    type_row = rows.find { |p| p[:key] == :type }
    expect(type_row[:status]).to eq(:current)
  end
end
