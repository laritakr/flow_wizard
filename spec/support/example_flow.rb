# frozen_string_literal: true

# A representative flow mirroring the deposit-wizard shape (the engine's origin), so
# the navigator specs exercise real branching: an add path with a parent step, a
# work_type prerequisite that detours, and a files-conditional metadata step.
#
# A tiny struct stands in for the app's State — the gem is state-agnostic, so any
# object the conditions understand works.
ExampleState = Struct.new(:path, :work_type, :uploaded_file_ids, keyword_init: true) do
  def initialize(**args)
    super
    self.uploaded_file_ids ||= []
  end
end

def example_flow
  FlowWizard::Flow.build do
    condition :adding,    ->(s, _c) { s.path == "add" }
    condition :has_files, ->(s, _c) { !s.uploaded_file_ids.empty? }
    prerequisite :work_type, ->(s, _c) { !(s.work_type.nil? || s.work_type == "") }, detour: :known_type

    step :start, rail: :type
    step :select_parent, skip_unless: :adding, on_skip: :entry, rail: :parent,
                         icon: "fa-sitemap", label_key: "parent"
    step :known_type, rail: :type
    step :files, rail: :upload, icon: "fa-upload", label_key: "upload"
    step :details, requires: :work_type, rail: :detail, icon: "fa-pencil", label_key: "detail"
    step :file_meta, requires: :work_type, skip_unless: :has_files,
                     rail: :file_detail, rail_if: :has_files, icon: "fa-file", label_key: "file_detail"
    step :review, requires: :work_type, rail: :review, icon: "fa-check", label_key: "review"
    step :done, terminal: true
  end
end

# A flow with a declared `branch` — one decision variable (`type_mode`) forking into
# two mutually-exclusive steps — so the diagram specs can exercise real fork edges,
# not just the linear spine.
BranchState = Struct.new(:type_mode, keyword_init: true)

def branching_flow
  FlowWizard::Flow.build do
    branch :type_mode, on: ->(s, _c) { s.type_mode },
                       known: :known_type, guided: :guided_confirm

    step :start, rail: :type
    step :known_type, rail: :type
    step :guided_confirm, rail: :type
    step :details, rail: :detail
    step :done, terminal: true
  end
end

# A flow with a declared `decision` — the `start` step routes on `path` to already-
# gated, partly-shared downstream steps (add -> parent, standalone -> item, new ->
# straight to files), which reconverge. Exercises draw-only fork edges + convergence.
def routing_flow
  FlowWizard::Flow.build do
    condition :adding, ->(s, _c) { s.path == "add" }
    condition :on_new, ->(s, _c) { s.path == "new" }
    decision :path, from: :start,
                    add: :select_parent, standalone: :item_start, new: :files

    step :start, rail: :type
    step :select_parent, skip_unless: :adding, rail: :parent
    step :item_start, skip_if: :on_new, rail: :type
    step :files, rail: :upload
    step :details, rail: :detail
    step :done, terminal: true
  end
end
