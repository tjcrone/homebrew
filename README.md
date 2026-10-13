# Quarantine-clearing Homebrew casks

This tap tracks Homebrew's official `codex` and `claude-code` casks with one
local change: on macOS, each cask recursively removes only the
`com.apple.quarantine` extended attribute from its staged directory.

This deliberately bypasses Gatekeeper's quarantine check for these two
downloaded packages. Homebrew still downloads the upstream artifacts and
verifies their SHA-256 checksums, but you should review every cask update before
installing it. The workaround does not change Gatekeeper or any system-wide
security setting.

## Why the hook is in `preflight_steps`

Homebrew first downloads and extracts a cask into its versioned Caskroom
directory, then installs its artifacts in a fixed order. `preflight_steps` runs
after extraction but before binary links, generated completions, apps, or other
activatable artifacts.

The official Codex cask contains both:

```ruby
binary "bin/codex"
generate_completions_from_executable "bin/codex", "completion"
```

The second artifact executes the newly staged Codex binary once for each of
bash, zsh, and fish. That—not creation of `/opt/homebrew/bin/codex`—explains why
Gatekeeper can appear during the upgrade itself. The `preflight_steps` hook is
ordered before both artifacts.

The command named `claude` comes from the official `claude-code` cask. That
cask has a binary artifact but no generated-completion or installer artifact,
so Homebrew links it without running it. Its first later invocation is
therefore the first execution. (The separate official `claude` cask is the
Claude desktop app and is not customized here.)

## Set up the tap

The public repository is named `tjcrone/homebrew`. Because that name does not
follow Homebrew's `homebrew-<tap>` GitHub convention, register it with an
explicit URL:

```sh
brew tap tjcrone/homebrew https://github.com/tjcrone/homebrew.git
```

Install the fully qualified casks so Homebrew records this tap as their source:

```sh
brew install --cask tjcrone/homebrew/codex
brew install --cask tjcrone/homebrew/claude-code
```

If the official casks are already installed, switch their recorded source with
`reinstall`:

```sh
brew reinstall --cask tjcrone/homebrew/codex
brew reinstall --cask tjcrone/homebrew/claude-code
```

A fully qualified install also trusts only those named casks on current
Homebrew releases. It does not require trusting every package in the tap.

Homebrew records the originating tap in each cask's install receipt, so later
upgrades continue using these definitions.

You can confirm the source with:

```sh
brew info --cask tjcrone/homebrew/codex tjcrone/homebrew/claude-code
```

The casks should resolve from `tjcrone/homebrew`.

## Automatic upgrades

Add this wrapper to `~/.zshrc` and start a new shell (or run
`source ~/.zshrc`):

```zsh
brew() {
  if (( $# > 0 )) && [[ $1 == upgrade ]]; then
    shift
    "/Volumes/Macintosh HD CS/github/tjcrone/homebrew/script/brew-upgrade" "$@"
  else
    command brew "$@"
  fi
}
```

The wrapper changes only `brew upgrade`. All other `brew` commands go directly
to Homebrew. The wrapper runs the real `brew update` first so the tap checkout
receives any automated cask commits, then runs the real `brew upgrade` with the
original arguments. If `brew update` fails, the upgrade does not run.

To bypass this automation deliberately, invoke `command brew upgrade` from
zsh.

## Automated upstream updates

The `Update casks` GitHub Action runs hourly at minute 17 and can also be run
manually. It:

1. Downloads and patches the current official Codex and Claude Code casks.
2. Runs the complete test suite.
3. Refuses to publish if the updater changes anything outside the two casks.
4. Creates one atomic `Update casks from upstream` commit when either cask
   changed.

The updater validates the expected cask tokens and artifact shapes before
inserting the local `preflight_steps` blocks. It refuses to proceed if an
expected anchor is missing or duplicated, if upstream adds its own preflight
hook, or if Claude Code gains a generated-completion artifact. Those cases
leave the Action failed without changing the repository.

The Action has only `contents: write` permission. It uses GitHub's
`createCommitOnBranch` mutation without custom author or committer data, so
GitHub creates a verified bot-signed commit. The mutation includes the expected
current commit SHA and fails instead of overwriting a concurrent update.

To request an immediate check from the command line after the repository is
published:

```sh
gh workflow run update-casks.yml --repo tjcrone/homebrew
```

## Manual maintenance

To check for upstream drift without changing files, run:

```sh
script/update-casks --check
```

It exits nonzero when either local cask is behind its patched upstream result.

To regenerate manually and run all tests:

```sh
script/update-casks
ruby test/update_casks_test.rb
ruby test/brew_upgrade_test.rb
ruby test/update_workflow_test.rb
```

For an offline consistency check against cask sources in a directory:

```sh
script/update-casks --check --source-dir /path/to/homebrew-cask/Casks/c
```

## Revert to the official casks

Switch the installed casks back to Homebrew's official definitions before
removing this tap:

```sh
brew reinstall --cask homebrew/cask/codex
brew reinstall --cask homebrew/cask/claude-code
brew untrust --cask tjcrone/homebrew/codex tjcrone/homebrew/claude-code
brew untap tjcrone/homebrew
```

The next official upgrade may restore the Gatekeeper behavior described above.
