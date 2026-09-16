# Elbowroom

Elbowroom explains every gigabyte on a small-disk Mac and reclaims what
regenerates. Build, test, and layout: see README.

- Distribution is direct download only: Developer ID signing and notarization.
  The Mac App Store and App Sandbox are explicitly out of scope. Do not add
  sandbox builds, App Store submission work, or App Store permissions.
- All features are free, with no paid tier, purchase flow, or reclaim allowance.
- Offloading to external drives is retired. Do not reintroduce it.
- Keep task completion inside Elbowroom. Request macOS authorization in context
  when needed; do not substitute Finder or Terminal instructions for an operation
  the user requested in the app. Never bypass OS authorization or collect passwords.
- Tom (the founder) runs `dist/Elbowroom.app` with his real data. Never reset its
  state or quit/relaunch it without asking. Verify UI with
  `swift run ElbowroomSnapshots`, not by driving his live app.
- Every user-facing string goes through `Copy/CopyDeck.swift` with a Japanese
  pair and an audit entry. Plain and literal, verbs on buttons, no em-dashes,
  no exclamation points, no marketing. Tests enforce this.
- New surfaces are items on the existing rails (suggestions, Items table,
  headroom) — never bespoke cards or chrome.
- The product's identity: explain before acting, show the literal command,
  verify before destroying, measure rather than promise.

## Releases

- Follow `docs/RELEASING.md` for Dorso-style DMG/ZIP releases and semantic versions.
- `release.json` owns version and build; `CHANGELOG.md` owns user-facing notes.
  Increase both version and build for every release. Never replace a published tag.
- "Ship it" means synchronize main, review notes, test, commit, then run
  `./release.sh X.Y.Z --publish`. Building an installer alone does not publish it.
- Preserve `dev.elbowroom.app`, the Elbowroom Sparkle key, and existing user data.
  Never copy Dorso's App Store targets, feed, paid features, or reset commands.
- Use isolated `dist/releases/` or `dist/previews/` output for packaging so the
  founder's running app is not replaced. Never reset permissions or preferences.
