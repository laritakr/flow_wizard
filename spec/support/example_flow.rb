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
