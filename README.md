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

For a local-only tap, register this repository under the
`tjcrone/unquarantined` identifier:

```sh
brew tap tjcrone/unquarantined "$(pwd)"
```

If the repository is published as `tjcrone/homebrew-unquarantined`, this is
simply:

```sh
brew tap tjcrone/unquarantined
```

For a differently named remote repository, supply its Git URL as the second
argument to `brew tap`.

Install the fully qualified casks so Homebrew records this tap as their source:

```sh
brew install --cask tjcrone/unquarantined/codex
brew install --cask tjcrone/unquarantined/claude-code
```

If the official casks are already installed, switch their recorded source with
`reinstall`:

```sh
brew reinstall --cask tjcrone/unquarantined/codex
brew reinstall --cask tjcrone/unquarantined/claude-code
```

A fully qualified install also trusts only those named casks on current
Homebrew releases. It does not require trusting every package in the tap.

Homebrew records the originating tap in each cask's install receipt. Normal
commands then keep using these definitions:

```sh
brew update
brew upgrade
```

You can confirm the source with:

```sh
brew info --cask tjcrone/unquarantined/codex tjcrone/unquarantined/claude-code
```

The `From:` lines should name `tjcrone/unquarantined`.

## Update from upstream

Run:

```sh
script/update-casks
git diff -- Casks
ruby test/update_casks_test.rb
```

The updater downloads the two current casks from
`Homebrew/homebrew-cask`, validates the expected cask token and artifact shape,
and inserts the local `preflight_steps` block immediately before the binary
artifact. It builds both results before writing either file. It refuses to
proceed if an expected anchor is missing or duplicated, if upstream adds its
own preflight hook, or if Claude Code gains a generated-completion artifact.
Those cases require a manual review because hook placement may no longer be
unambiguous.

This synchronization is intentionally explicit: `brew update` updates only
the committed contents of this tap; it does not merge changes from the official
`homebrew/cask` repository. Run `script/update-casks` periodically, review and
commit its changes, and push them if the tap uses GitHub. A tapped clone will
receive the commit on the next `brew update`, after which `brew upgrade` sees
the new cask versions.

To check for upstream drift without changing files, run:

```sh
script/update-casks --check
```

It exits nonzero when either local cask is behind its patched upstream result.

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
brew untrust --cask tjcrone/unquarantined/codex tjcrone/unquarantined/claude-code
brew untap tjcrone/unquarantined
```

The next official upgrade may restore the Gatekeeper behavior described above.
