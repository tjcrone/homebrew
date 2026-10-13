# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class BrewUpgradeTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "script/brew-upgrade")
  CASK_PATHS = ["Casks/claude-code.rb", "Casks/codex.rb"].freeze

  def setup
    @tempdir = Dir.mktmpdir("brew-upgrade-test")
    @root = File.join(@tempdir, "repository")
    @bin = File.join(@tempdir, "bin")
    @brew_log = File.join(@tempdir, "brew.log")
    @git_log = File.join(@tempdir, "git.log")
    @updater_log = File.join(@tempdir, "updater.log")
    @test_log = File.join(@tempdir, "test.log")
    @real_git = executable_on_path("git")

    FileUtils.mkdir_p([File.join(@root, "Casks"), File.join(@root, "script"), File.join(@root, "test"), @bin])
    FileUtils.cp(SCRIPT, File.join(@root, "script/brew-upgrade"))
    CASK_PATHS.each { |path| write(path, "cask fixture\n") }
    write_fake_updater
    write_fake_tests
    write_fake_git
    write_fake_brew

    git("init", "--quiet")
    git("config", "user.name", "Test User")
    git("config", "user.email", "test@example.com")
    git("config", "commit.gpgsign", "false")
    git("add", ".")
    git("commit", "--quiet", "-m", "Initial fixture")
  end

  def teardown
    FileUtils.remove_entry(@tempdir)
  end

  def test_unchanged_casks_run_brew_without_a_commit
    output, status = run_orchestrator("--cask", "codex")

    assert_predicate status, :success?, output
    refute git_invocations.any? { |arguments| arguments.first == "commit" }
    assert_equal [["update"], ["upgrade", "--cask", "codex"]], brew_invocations
    assert_empty log_lines(@test_log)
  end

  def test_updated_casks_are_tested_and_committed_before_brew_runs
    output, status = run_orchestrator(mode: "changed")

    assert_predicate status, :success?, output
    commit = git_invocations.find { |arguments| arguments.first == "commit" }
    assert_equal ["commit", "-S", "-m", "Update casks from upstream"], commit
    assert_equal ["tests"], log_lines(@test_log)
    assert_equal "Update casks from upstream", git("log", "-1", "--format=%s").strip
    assert_equal [["update"], ["upgrade"]], brew_invocations
  end

  def test_unrelated_repository_changes_stop_the_upgrade
    write("notes.txt", "unrelated\n")

    output, status = run_orchestrator

    refute_predicate status, :success?
    assert_includes output, "repository has unrelated changes"
    assert_empty log_lines(@updater_log)
    assert_empty brew_invocations
  end

  def test_ambiguous_upstream_change_stops_the_upgrade
    output, status = run_orchestrator(mode: "ambiguous")

    refute_predicate status, :success?
    assert_includes output, "update-casks failed"
    assert_empty brew_invocations
    assert_empty git_invocations.select { |arguments| arguments.first == "commit" }
  end

  def test_matching_generated_changes_can_retry_a_failed_commit
    CASK_PATHS.each { |path| File.open(File.join(@root, path), "a") { |file| file << "# generated update\n" } }

    output, status = run_orchestrator(mode: "retry")

    assert_predicate status, :success?, output
    assert_equal ["--check"], updater_invocations.first
    assert git_invocations.any? { |arguments| arguments.first == "commit" && arguments.include?("-S") }
    assert_equal [["update"], ["upgrade"]], brew_invocations
  end

  def test_signing_failure_stops_before_brew_runs
    output, status = run_orchestrator(mode: "changed", signing_failure: true)

    refute_predicate status, :success?
    assert_includes output, "git commit -S"
    assert_empty brew_invocations
    assert_equal CASK_PATHS, git("diff", "--cached", "--name-only").lines(chomp: true).sort
  end

  private

  def executable_on_path(name)
    path = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).find do |directory|
      candidate = File.join(directory, name)
      File.file?(candidate) && File.executable?(candidate)
    end
    raise "could not find #{name}" unless path

    File.join(path, name)
  end

  def write(relative_path, contents)
    path = File.join(@root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def write_executable(path, contents)
    File.write(path, contents)
    FileUtils.chmod(0o755, path)
  end

  def write_fake_updater
    write_executable(File.join(@root, "script/update-casks"), <<~'RUBY')
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require "json"

      root = File.expand_path("..", __dir__)
      paths = ["Casks/claude-code.rb", "Casks/codex.rb"].map { |path| File.join(root, path) }
      File.open(ENV.fetch("ORCHESTRATOR_UPDATER_LOG"), "a") { |file| file.puts(JSON.generate(ARGV)) }

      if ARGV == ["--check"]
        exit(paths.all? { |path| File.read(path).include?("# generated update") } ? 0 : 1)
      end

      case ENV.fetch("ORCHESTRATOR_UPDATE_MODE")
      when "changed"
        paths.each { |path| File.open(path, "a") { |file| file << "# generated update\n" } }
      when "ambiguous"
        warn "upstream shape is ambiguous"
        exit 1
      end
    RUBY
  end

  def write_fake_tests
    write("test/update_casks_test.rb", <<~'RUBY')
      # frozen_string_literal: true

      File.open(ENV.fetch("ORCHESTRATOR_TEST_LOG"), "a") { |file| file.puts("tests") }
    RUBY
  end

  def write_fake_git
    write_executable(File.join(@bin, "git"), <<~'RUBY')
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require "json"

      File.open(ENV.fetch("ORCHESTRATOR_GIT_LOG"), "a") { |file| file.puts(JSON.generate(ARGV)) }
      exit 1 if ARGV.first == "commit" && ENV["ORCHESTRATOR_SIGNING_FAILURE"] == "1"

      arguments = ARGV.dup
      arguments.delete("-S") if arguments.first == "commit"
      exec(ENV.fetch("ORCHESTRATOR_REAL_GIT"), *arguments)
    RUBY
  end

  def write_fake_brew
    write_executable(File.join(@bin, "brew"), <<~'RUBY')
      #!/usr/bin/env ruby
      # frozen_string_literal: true

      require "json"

      File.open(ENV.fetch("ORCHESTRATOR_BREW_LOG"), "a") { |file| file.puts(JSON.generate(ARGV)) }
    RUBY
  end

  def run_orchestrator(*arguments, mode: "unchanged", signing_failure: false)
    env = {
      "PATH" => [@bin, ENV.fetch("PATH")].join(File::PATH_SEPARATOR),
      "ORCHESTRATOR_BREW_LOG" => @brew_log,
      "ORCHESTRATOR_GIT_LOG" => @git_log,
      "ORCHESTRATOR_REAL_GIT" => @real_git,
      "ORCHESTRATOR_SIGNING_FAILURE" => signing_failure ? "1" : "0",
      "ORCHESTRATOR_TEST_LOG" => @test_log,
      "ORCHESTRATOR_UPDATE_MODE" => mode,
      "ORCHESTRATOR_UPDATER_LOG" => @updater_log,
    }
    stdout, stderr, status = Open3.capture3(env, File.join(@root, "script/brew-upgrade"), *arguments, chdir: @root)
    [stdout + stderr, status]
  end

  def git(*arguments)
    stdout, stderr, status = Open3.capture3(@real_git, *arguments, chdir: @root)
    raise "git #{arguments.join(' ')} failed: #{stderr}" unless status.success?

    stdout
  end

  def log_lines(path)
    return [] unless File.exist?(path)

    File.readlines(path, chomp: true)
  end

  def git_invocations
    log_lines(@git_log).map { |line| JSON.parse(line) }
  end

  def brew_invocations
    log_lines(@brew_log).map { |line| JSON.parse(line) }
  end

  def updater_invocations
    log_lines(@updater_log).map { |line| JSON.parse(line) }
  end
end
