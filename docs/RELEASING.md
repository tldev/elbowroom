# Releasing Elbowroom

This is the direct-download part of Dorso's release process, adapted for a free
Elbowroom app. There is one build, no paid tier, no App Store submission, and no
external-drive offloading.

## Once per release machine

Install Xcode command-line tools, Python 3, GitHub CLI, and `create-dmg`:

```sh
brew install gh create-dmg
gh auth login
swift package resolve
./release.sh --setup-key
```

A Developer ID Application certificate must be in the login Keychain. The
release uses the existing `notarytool-dorso` notarytool profile on this Mac;
its Apple credentials are account-wide, not specific to Dorso. Override with
`NOTARY_PROFILE=your-profile` or change `notary_profile` in `release.json`.
Credentials stay in Keychain. Do not put passwords or private keys in this repo.

Elbowroom uses a separate Sparkle signing key with Keychain account `elbowroom`.
The setup command creates it only if absent and records its **public** key in
`release.json`. Preserve/back up the signing key securely when moving to another
Mac. Never generate a replacement for an app already distributed to users
without following Sparkle's key-rotation procedure.

## Versions and notes

`release.json` is the source of truth for the app's semantic version and integer
build number. Info.plist, artifact names, GitHub release, and update feed use it.
Sparkle compares the build number, which must increase on every release.

Write concise, user-facing entries in `CHANGELOG.md` under `[Unreleased]`, grouped
under `### Added`, `### Changed`, or `### Fixed`. Explain the benefit rather than
copying implementation details or commit messages. Credit contributors where
applicable. Then promote the notes and increment both version and build:

```sh
./release.sh --bump patch   # fixes: 1.1.0 -> 1.1.1
./release.sh --bump minor   # compatible features: 1.1.0 -> 1.2.0
./release.sh --bump major   # breaking changes: 1.1.0 -> 2.0.0
```

Choose one bump, not all three. Only stable `X.Y.Z` releases are supported.
Review the generated date and notes before committing. Version 1.1.0 is already
prepared for the initial installer release; do not bump it again just to ship it.
The matching changelog section supplies the GitHub and in-app release notes.

## Preview the installer

```sh
./test-dmg.sh
open dist/previews/1.1.0/Elbowroom-v1.1.0.dmg
```

This builds a host-architecture preview with Dorso's drag-to-Applications layout,
Elbowroom's icon, and the Applications shortcut. It does not notarize, publish,
or start automatic updates. Preview builds are not distribution artifacts.

## Build signed, notarized downloads locally

```sh
swift test
python3 -m unittest discover -s Tests/ReleaseTests -v
./release.sh 1.1.0
```

The normal command builds both Apple Silicon and Intel, signs nested Sparkle
components and the app-move helper before the app, notarizes and staples the app,
creates a ZIP with `ditto`, and builds/signs/notarizes/staples the DMG. It verifies
the app with Gatekeeper and signs/verifies the final ZIP for Sparkle.

Artifacts go to `dist/releases/1.1.0/`:

- `Elbowroom-v1.1.0.dmg`: drag-to-Applications installer.
- `Elbowroom-v1.1.0.zip`: the same stapled app, preserving framework symlinks.
- `release-notes.md` and `release-notes.html`: notes from the changelog.
- `SHA256SUMS`: checksums for the two downloads.
- `appcast.xml`: candidate update feed; building alone does not publish it.
- `release-manifest.json`: source commit, dirty-state flag, version/build, hashes.
- Notarization results, for troubleshooting.

Local packaging may include uncommitted changes, but those artifacts cannot be
published by the script. The running `dist/Elbowroom.app` is not replaced or
quit. To rebuild the same candidate, move the existing output directory aside;
the script deliberately does not overwrite it. Failed builds remain in a hidden
work directory beside the destination for diagnosis.

## Ship it

When the user explicitly requests a release:

1. Fetch and rebase on `origin/main`, preserving any uncommitted work first.
2. Check `gh release list --repo tldev/elbowroom --limit 5` and existing tags.
3. Review the semantic version, increased build number, and dated changelog.
4. Run the tests and review the installer preview.
5. Commit the reviewed changes and merge to `main` if needed.
6. Run `./release.sh 1.1.0 --check`, then `./release.sh 1.1.0 --publish`.

Use the desired version in those commands. `--publish` rebuilds from the clean
commit, atomically pushes main and the new annotated tag, uploads the notarized
DMG/ZIP and notes to a GitHub release, then commits and pushes the appcast.
Updates are advertised only after the downloads exist. It refuses existing
versions/tags and never deletes or replaces a release. A build alone is not
permission to publish or send messages to contributors.

If a network failure occurs after the tag or release is published, inspect the
remote state before continuing. Do not delete the tag or change its target.
Use the preserved, checksummed artifacts to finish an incomplete upload. If only
the final appcast push failed, push its existing commit after resolving the
remote branch; do not rebuild and overwrite the published downloads.

## Automatic updates

Sparkle is linked only into the app executable, so tests, benchmarks, and
snapshot renderers never start an updater. Only distribution bundles enable it.
They check automatically, allow users to disable checks in General settings,
and offer **Check for updates** in the application menu. Installing a found
update requires user interaction; automatic installation is disabled.

The feed is `https://raw.githubusercontent.com/tldev/elbowroom/main/appcast.xml`.
It becomes available when this workflow is first published; local builds do not
change the public feed. Until then, a manual check in a distribution candidate
can report a feed error. Never point Elbowroom at Dorso's feed.

The existing bundle identifier `dev.elbowroom.app` is preserved to retain app
preferences and macOS permission identity. User data and permissions are never
reset during packaging or installation.

References: [Dorso's release workflow](https://github.com/tldev/dorso/blob/main/release.sh),
[Sparkle setup and signing](https://sparkle-project.org/documentation/), and
[Sparkle programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/).

The adapted workflow and copied artwork retain Dorso's [MIT notice](licenses/Dorso-MIT.txt).
