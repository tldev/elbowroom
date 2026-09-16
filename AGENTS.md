# Elbowroom Repository Guidance

Elbowroom explains every gigabyte on a small-disk Mac, reclaims what regenerates,
and offloads the rest. Build, test, and layout: see README.

- Tom (the founder) runs `dist/Elbowroom.app` with his real data. Never reset its
  state or quit/relaunch it without asking. Verify UI with
  `swift run ElbowroomSnapshots`, not by driving his live app.
- Every user-facing string goes through `Copy/CopyDeck.swift` with a Japanese
  pair and an audit entry. Plain and literal, verbs on buttons, no em-dashes,
  no exclamation points, no marketing. Tests enforce this.
- New surfaces are items on the existing rails (suggestions, Items table,
  headroom) - never bespoke cards or chrome.
- The product's identity: explain before acting, show the literal command,
  verify before destroying, measure rather than promise.
