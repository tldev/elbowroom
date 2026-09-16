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
Local credentials stay in Keychain. GitHub-hosted releases use encrypted repository
secrets and a disposable runner Keychain. Never commit passwords or private keys.

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

Merging into `main` runs `.github/workflows/release.yml`. A new version in
`release.json` triggers tests, a universal build, Developer ID signing, Apple
notarization, a GitHub release, and an update-feed commit. Ordinary merges with
an already published version do not publish another release.

1. Fetch and synchronize with `origin/main`, preserving uncommitted work.
2. Review existing releases, the new version/build, and dated changelog notes.
3. Run tests and review the installer preview.
4. Commit changes in a pull request and merge after its tests pass.
5. Watch the **Release** workflow through completion and verify the downloads.

The workflow tags the exact triggering commit. It serializes releases and never
replaces a published tag or assets. GitHub's token publishes the feed without
triggering another workflow. Updates are advertised only after downloads exist.

### GitHub-hosted signing setup

Repository Actions secrets:

- `DEVELOPER_ID_P12`: base64-encoded Developer ID Application certificate and private key.
- `DEVELOPER_ID_PASSWORD`: password protecting that PKCS#12 export.
- `SPARKLE_PRIVATE_KEY`: Elbowroom's exported Sparkle signing key.
- `APPLE_ID`: Apple Developer account email.
- `APPLE_APP_PASSWORD`: app-specific password for notarization.

Secrets are used only by the release job on `main`, never by pull-request tests.
`Scripts/ci-signing.py` imports them into a temporary runner keychain and removes
that keychain after the job. The workflow uses GitHub's temporary token with
`contents: write` to publish; no long-lived GitHub token is needed.

### Recovery and local fallback

The workflow supports **Run workflow** on `main` to retry before publication.
If a tag or release already exists after a partial failure, inspect the remote
state first. Never delete a tag, retarget it, or overwrite published downloads.
The job retains packaging output as an Actions artifact for 14 days, including
notarization results. Use those checksummed artifacts to finish an incomplete
upload. If only the feed commit failed, recover `appcast.xml` from the release
asset and commit it onto current main after checking its version and history.

For an explicitly requested local fallback, run `./release.sh X.Y.Z --check`,
then `./release.sh X.Y.Z --publish` from clean, synchronized main. This rebuilds,
publishes, and updates the feed. Do not race it against a GitHub release job.

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
