# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class UpdateWorkflowTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  WORKFLOW_PATH = File.join(ROOT, ".github/workflows/update-casks.yml")

  def setup
    @source = File.read(WORKFLOW_PATH)
  end

  def test_workflow_is_valid_yaml
    workflow = YAML.safe_load(@source, aliases: false)

    assert_kind_of Hash, workflow
    assert workflow.key?("jobs")
  end

  def test_actions_are_pinned_to_full_commit_hashes
    action_refs = @source.scan(/^\s*uses:\s*(\S+)/).flatten

    assert_equal 2, action_refs.length
    action_refs.each { |reference| assert_match(/@[0-9a-f]{40}\z/, reference) }
  end

  def test_workflow_has_minimal_write_permission
    assert_match(/^permissions:\n  contents: write$/, @source)
  end

  def test_workflow_runs_the_complete_test_suite
    assert_includes @source, "ruby test/update_casks_test.rb"
    assert_includes @source, "ruby test/brew_upgrade_test.rb"
    assert_includes @source, "ruby test/update_workflow_test.rb"
  end

  def test_verified_commit_mutation_is_race_safe_and_atomic
    assert_includes @source, "createCommitOnBranch"
    assert_includes @source, "expectedHeadOid: context.sha"
    assert_includes @source, 'message: { headline: "Update casks from upstream" }'
    assert_includes @source, '["Casks/claude-code.rb", "Casks/codex.rb"]'
    refute_match(/\b(?:author|committer):/, @source)
  end
end
