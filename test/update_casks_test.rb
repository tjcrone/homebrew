# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

class UpdateCasksTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "script/update-casks")
  WORKAROUND = [
    "  # Local workaround: clear quarantine after staging and before any executable artifact runs.",
    "  preflight_steps do",
    "    on_macos do",
    '      run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{staged_path}}"]',
    "    end",
    "  end",
  ].join("\n")

  def setup
    @tempdir = Dir.mktmpdir("update-casks-test")
    @source_dir = File.join(@tempdir, "upstream")
    FileUtils.mkdir_p(@source_dir)
    FileUtils.cp(File.join(ROOT, "Casks/codex.rb"), File.join(@source_dir, "codex.rb"))
    FileUtils.cp(File.join(ROOT, "Casks/claude-code.rb"), File.join(@source_dir, "claude-code.rb"))
    Dir.glob(File.join(@source_dir, "*.rb")).each do |path|
      source = File.read(path)
      removed = source.sub!("#{WORKAROUND}\n\n", "")
      raise "test fixture did not contain workaround" unless removed

      File.write(path, source)
    end
  end

  def teardown
    FileUtils.remove_entry(@tempdir)
  end

  def test_current_shape_is_accepted
    output, status = Open3.capture2e(SCRIPT, "--check", "--source-dir", @source_dir, chdir: ROOT)
    assert_predicate status, :success?, output
  end

  def test_successful_update_recreates_both_local_casks
    isolated_root = File.join(@tempdir, "repository")
    FileUtils.mkdir_p(File.join(isolated_root, "script"))
    FileUtils.cp(SCRIPT, File.join(isolated_root, "script/update-casks"))

    output, status = Open3.capture2e(
      RbConfig.ruby,
      File.join(isolated_root, "script/update-casks"),
      "--source-dir",
      @source_dir,
      chdir: isolated_root,
    )

    assert_predicate status, :success?, output
    assert_equal File.read(File.join(ROOT, "Casks/codex.rb")), File.read(File.join(isolated_root, "Casks/codex.rb"))
    assert_equal File.read(File.join(ROOT, "Casks/claude-code.rb")),
                 File.read(File.join(isolated_root, "Casks/claude-code.rb"))
  end

  def test_changed_binary_anchor_fails_without_writing
    path = File.join(@source_dir, "codex.rb")
    File.write(path, File.read(path).sub('binary "bin/codex"', 'binary "codex"'))
    before = Dir.glob(File.join(ROOT, "Casks/*.rb")).to_h { |file| [file, File.read(file)] }

    output, status = Open3.capture2e(SCRIPT, "--source-dir", @source_dir, chdir: ROOT)

    refute_predicate status, :success?
    assert_includes output, "expected exactly one"
    assert_equal before, current_casks
  end

  def test_new_upstream_preflight_fails_without_writing
    path = File.join(@source_dir, "claude-code.rb")
    File.write(path, File.read(path).sub('  binary "claude"', "  preflight_steps do\n  end\n\n  binary \"claude\""))
    before = Dir.glob(File.join(ROOT, "Casks/*.rb")).to_h { |file| [file, File.read(file)] }

    output, status = Open3.capture2e(SCRIPT, "--source-dir", @source_dir, chdir: ROOT)

    refute_predicate status, :success?
    assert_includes output, "merge requires review"
    assert_equal before, current_casks
  end

  private

  def current_casks
    Dir.glob(File.join(ROOT, "Casks/*.rb")).to_h { |file| [file, File.read(file)] }
  end
end
