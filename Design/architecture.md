# Architecture

Elbowroom keeps one core Swift package and concrete types. The boundaries follow
ownership and I/O, rather than one abstraction layer per feature.

## Scan and inventory

`ScanNodeBuilder` belongs to the scan workers. Per-directory locks coordinate
aggregation while the worker pool walks the filesystem. Post-passes finish
classification before converting the retained tree into `ScanNode` values.

`ScanResult`, its tree, items, and findings are Sendable values. The `.finished`
event transfers a stable snapshot; retaining it for cache encoding cannot share
later UI mutations. Cache writes are queued in publication order. The cache envelope is versioned when classification changes, so restored
inventories cannot retain obsolete cleanup recommendations.

`Inventory` owns the UI's copy on the main actor. Replacement, enrichment, and
removal go through its methods. Findings have one source of truth inside the
snapshot. A revision prevents a late Docker measurement or cache load from
replacing newer data. Scan generations also reject events from cancelled scans.
Tree navigation resolves paths against the current snapshot.

## UI and actions

`ItemAction` resolves domain operations from an item and available tools. Its
localized title is presentation only. Overview suggestions, Items actions and
context menus, and Map actions use the same resolver and `AppModel.perform`.
Batch eligibility is deliberately narrower than individual action eligibility:
apps and managed data never join ordinary batch trays.

`LedgerProjection` is a pure mapping/filter/sort function. `LedgerModel` retains
one result keyed by inventory revision, query, sort, tier, and language. Projection
runs outside the main actor, propagates cancellation, and checks request order
before publication. Hover and selection do not rerun the query.

`AppModel` coordinates navigation and workflows. `ReclaimPlanner` handles filesystem
inspection for app removal and Messages/Photos trim plans. `CleanupPlanner`
handles tool-specific inspection. These planners do no destructive work. The
existing plan sheets remain the user's review step before execution.

Uninstall opens review without attempting to infer App Management permission from
`rename(path, path)`. Only a confirmed reclaim operation tests write access.
Access failures for top-level app bundles trigger an administrator prompt through
AppleScript's `do shell script ... with administrator privileges`. Passwords are
handled by macOS, never the app. A signed, bundled `ElbowroomAppMover` runs once
and exits; no daemon or background service is installed.

The helper only renames one app between `/Applications` and an existing private
`~/.Trash/Elbowroom Authorized <UUID>` folder. It validates the user, folder owner,
app identity, type, flags, and path components, retains directory descriptors,
and refuses to overwrite a destination. It neither changes ownership nor deletes
files recursively. Shell and AppleScript quoting treat all paths as data. Receipts
record the destination, and Put Back can request the same authorization in reverse.
Expiry never silently elevates to erase a protected app; unsuccessful expiry keeps
the receipt in Trash. Cancellation stops before app supporting data is removed.

This flow targets Developer ID direct distribution only. Mac App Store and App
Sandbox support have been abandoned; see `CLAUDE.md`. The production administrator
prompt and protected-app operation still require interactive verification on the
user's Mac; unit tests cover routing, cancellation, quoting, and the rename core
using temporary directories without elevated privileges.

## I/O and persistence

Directory sizing, cache reads, and disk-space refreshes execute outside the UI
actor. `DiskSnapshot.captureSpace` reads capacities without launching `tmutil`;
full background scans use `capture` when they need snapshot counts as well.

Receipt and history stores expose observable values on the main actor. Their
serial queues perform disk reads, encoding, and writes. Startup loads merge any
in-memory events recorded while the load was pending. Receipt expiry and restore
share a queue so they cannot operate on the same trash contents concurrently.
Tests can await `flush()` before reloading persisted state.

Tests and fixture rendering inject independent stores and cache paths and disable
production startup services. They do not initialize the live application's data.

## Adding a feature

1. Add its Atlas identity, classification, and bilingual copy.
2. Add a pure parser/planner when an external tool is involved.
3. Extend `ItemAction` only if it needs a new kind of action. Existing reclaim,
   cleanup, and teach actions should cover most integrations.
4. Add focused tests for classification, action routing, and plan safety.
5. Use the existing surfaces and benchmark larger inventories before adding caches.

FSEvents still debounces full scans. Subtree invalidation, databases, dynamic
plugins, and a general event bus remain unnecessary without measurements or a
concrete product requirement. See [performance.md](performance.md).

## Merged rows and app components

Items is a flat list. LedgerProjection merges the same reproducible storage type
across locations into one row; app caches must also share an owner. Recognition-only
system/shared-data rows can merge, but personal items and managed actions remain
independent. Each row retains its real member items, combined bytes and newest known
modification date. Search filters members before merging so row actions stay within
the visible search results. There are no synthetic filesystem targets.

Selection, range selection, context actions and cleanup review use every member.
Partially selected merged rows show a mixed checkbox. Optional previews list all
locations; there are no disclosure sections or expansion steps. The existing review
sheet remains the per-location deletion decision. LedgerModel computes and retains
the flat projection outside the main actor.

Overview combines smaller reproducible items into useful recommendations and
ranks these ahead of managed footprints that still require inspection. Managed
bytes are labeled as total storage and do not enter the ready-to-reclaim number.
Purgeable insights remain separate from merged file rows.

AppsPass separates app-owned Caches and supported disposable components before
publishing app totals. App totals exclude these components and already classified
nested assets. Explicit bundle-ID aliases are shared with uninstall planning;
website storage, history, settings and VM disks are not treated as cache components.
StorageRecognition then names known installations, system services and remaining
shared app data, counting only bytes not already attributed. These recognition-only
entries have no deletion action. Lenses exclude paths already claimed by post-passes.
