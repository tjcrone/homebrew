# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class BrewUpgradeTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "script/brew-upgrade")

  def setup
    @tempdir = Dir.mktmpdir("brew-upgrade-test")
    @bin = File.join(@tempdir, "bin")
    @brew_log = File.join(@tempdir, "brew.log")
    FileUtils.mkdir_p(@bin)
    write_fake_brew
  end

  def teardown
    FileUtils.remove_entry(@tempdir)
  end

  def test_updates_before_upgrading_and_forwards_arguments
    output, status = run_orchestrator("--cask", "codex")

    assert_predicate status, :success?, output
    assert_equal [["update"], ["upgrade", "--cask", "codex"]], brew_invocations
  end

  def test_update_failure_stops_before_upgrade
    output, status = run_orchestrator(update_failure: true)

    refute_predicate status, :success?
    assert_includes output, "brew update failed"
    assert_equal [["update"]], brew_invocations
  end

  private

  def write_fake_brew
    path = File.join(@bin, "brew")
    File.write(path, <<~'RUBY')
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require "json"

      File.open(ENV.fetch("BREW_UPGRADE_TEST_LOG"), "a") { |file| file.puts(JSON.generate(ARGV)) }
      exit 1 if ARGV == ["update"] && ENV["BREW_UPGRADE_TEST_UPDATE_FAILURE"] == "1"
    RUBY
    FileUtils.chmod(0o755, path)
  end

  def run_orchestrator(*arguments, update_failure: false)
    env = {
      "BREW_UPGRADE_TEST_LOG" => @brew_log,
      "BREW_UPGRADE_TEST_UPDATE_FAILURE" => update_failure ? "1" : "0",
      "PATH" => [@bin, ENV.fetch("PATH")].join(File::PATH_SEPARATOR),
    }
    stdout, stderr, status = Open3.capture3(env, [SCRIPT, SCRIPT], *arguments, chdir: ROOT)
    [stdout + stderr, status]
  end

  def brew_invocations
    return [] unless File.exist?(@brew_log)

    File.readlines(@brew_log, chomp: true).map { |line| JSON.parse(line) }
  end
end
