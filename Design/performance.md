# Performance baseline

Measured on September 7, 2026, with a release build on Mac16,10, 16 GiB RAM,
macOS 27.0 (26A5425a). These are local baselines, not cross-machine guarantees.

## Run the harnesses

```sh
swift build -c release
.build/release/ElbowroomBench metrics /path/to/fixture --items 10000 --iters 5
.build/release/ElbowroomSnapshots /tmp/elbowroom-ui --performance --items 10000
```

Run them sequentially with other heavy work idle. The first command measures
cache serialization, pure Items projections, treemap layout, and repeated real
scans. The synthetic inventory size is independent of the scan fixture. The
second measures an offscreen AppKit/SwiftUI fixture and writes `performance.txt`.
It uses isolated stores and cache files, with production startup services disabled.
Neither harness needs to restart the live application.

To reproduce the scan fixture, create 100 projects, each with a package manifest
and 100 small files under `node_modules`:

```sh
python3 - <<'PY'
from pathlib import Path
from tempfile import mkdtemp
root = Path(mkdtemp(prefix="elbowroom-perf-tree-"))
for project in range(100):
    directory = root / f"project-{project}" / "node_modules"
    directory.mkdir(parents=True)
    (directory.parent / "package.json").write_text('{}')
    for item in range(100):
        (directory / f"file-{item}.js").write_bytes(b'x' * 1024)
print(root)
PY
```

Pass the printed directory to `metrics`. The measured fixture contained 10,100
files and 41.4 MB of allocated data. Scan post-passes can also inspect host system
metadata, so results vary with the host. OS filesystem caches are not flushed;
the first scan is not a controlled cold-cache measurement.

## Recorded results

Headless harness, 10,000 inventory rows, five samples:

| Operation | Median | p95 |
| --- | ---: | ---: |
| Cache save | 19.794 ms | 23.100 ms |
| Cache load | 27.816 ms | 30.027 ms |
| Items projection and sort | 7.643 ms | 8.815 ms |
| Items search and sort | 32.289 ms | 37.032 ms |
| Treemap layout | 0.004 ms | 0.110 ms |

The first scan took 309 ms; subsequent scans took 245, 236, 238, and 222 ms.
Peak process RSS was 46.3 MiB. The treemap fixture groups inventory into a small
set of visible regions; its timing does not represent rendering 10,000 rectangles.
Five samples provide a coarse baseline; the reported p95 is effectively the
slowest sample.

UI harness, 10,000 rows:

| Operation | Time |
| --- | ---: |
| Model and fixture setup | 12.929 ms |
| Process entry to first fixture layout | 152.725 ms |
| Search to layout, median / maximum | 70.225 / 89.991 ms |
| Ordinary scroll step, median / p95 | 4.976 / 7.997 ms |
| Full-list jump, median / p95 | 71.764 / 88.432 ms |
| Cached model restore | 38.873 ms |

Peak process RSS was 257.3 MiB. Search uses five updates; scrolling uses 30
60-point steps and 30 jumps across the list. These are synchronous layout timings,
not display frame-rate measurements. Process-entry timing excludes dynamic-loader
work and does not represent full production launch. Cache restore includes model
publication, while the headless cache-load measurement covers decoding alone.

## Decisions

Search computation alone can exceed a frame budget at 10,000 rows. Items now
projects outside the main actor and retains the result until its inputs change.
Request ordering and cancellation prevent older queries replacing newer ones.
Hover and selection reuse the retained rows.

Keep `ScrollView` with `LazyVStack` and an explicit 52-point row height. A native
`List` experiment regressed first layout and search in this harness and produced
AppKit reentrancy warnings. Large jumps still take noticeably longer than ordinary
scroll steps; profile a real inventory before adopting a different table renderer.

Keep debounced full scans for now. This small fixture does not establish how a
large real home directory behaves. Measure those scans and event bursts before
introducing subtree invalidation, a database, or additional caching. Future
comparisons should use the same fixture, build configuration, host, and harness,
and distinguish computational work from UI layout and filesystem cache effects.
