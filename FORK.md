# Stats Compact

This branch is an independent customization of exelban/stats v3.0.22
(`1282cd52d5bc3b40ca631069e348f8a2c1c8aad9`). It keeps the upstream MIT license
and author notices. It is not an official Stats release.

## Changes

- Independent menu items with per-widget compact sizing, graph dimensions and spacing. CPU and GPU keep their own configurable graph widgets.
- Contextual popup application shortcuts, with four configurable slots per module.
- Popup section visibility and ordering with an actual popup preview.
- Local SQLite history for four time ranges, mean/peak display and CSV export.
- Sustained notification thresholds and optional per-fan temperature curves.
- A continuous Clock calendar with a Today button, bounded reusable date views and one hover target.

The menu padding implementation probes private AppKit selectors at runtime and
falls back to the system behavior when unavailable. It needs revalidation after
macOS changes. It does not change global menu-bar spacing preferences.

Fan curves are disabled by default. The development machine has no controllable
fan, so physical fan actuation was not tested. OS notification delivery was not
triggered in the automated model checks.

## Build a separate local application

Requirements: Apple Silicon, macOS 12 or later, Apple Command Line Tools, Python 3,
and an official Stats 3.0.22 installation at `/Applications/Stats.app`.

```sh
python3 build-local.py
```

The script compiles the main application and all monitoring frameworks. It uses
the installed official app for unchanged resources, helpers and desktop widgets.
It creates an ad-hoc signed `build/Stats Compact.app` with bundle identifier
`eu.exelban.Stats.Compact`; it does not replace the official installation.
The ordinary upstream Xcode configuration retains upstream naming, so use this
script when you need the separate Compact identity and preferences.

The local app initializes display choices from Stats once, then uses its own
preferences and data directory. Automatic updates are disabled for the custom
build. Login credentials and login/update settings are not migrated.

After a Clock-only change, `python3 build-local.py --only Clock Stats` can rebuild
the affected targets. Kit changes always rebuild all dependent frameworks because
the build does not enable Swift library evolution.

## Validation

After building, run:

```sh
python3 Tests/run-feature-models.py
python3 Tests/run-calendar-checks.py
python3 Tests/run-calendar-gestures.py
python3 Tests/run-calendar-performance.py
```

Calendar tests compile the actual private production views into isolated AppKit
checks. The gesture check replays inertial delta curves and abrupt reversals
through the native clip view. It does not simulate a physical trackpad or measure
AppKit's native momentum animator. See [PERFORMANCE.md](PERFORMANCE.md) for the
measured scope and performance comparison.

## Implementation provenance and contribution policy

Some interface behavior was informed by other system monitors, including iStat
Menus. The implementation uses Stats source and AppKit. No iStat Menus binaries,
icons, proprietary source, string dumps or decompiler output are included in this
repository. Stats' MIT license is retained; it does not license another product's
materials.

The upstream project's current policy is [open source, but not open contribution](https://github.com/exelban/stats#open-source-but-not-open-contribution).
It requires an existing issue and prior discussion before a feature PR; its PR
page currently restricts creation to collaborators. Publishing this fork does not
imply upstream approval. A focused calendar contribution can be discussed first;
the private menu-padding API and broader UI/fan-control additions should be
reviewed separately with the maintainer.

Referencing another monitor is not automatically rejected: [upstream issue #1194](https://github.com/exelban/stats/issues/1194)
describes iStat-style history, and the maintainer said in November 2022 that he
planned that feature. That historical reply is not approval of this fork or a PR.
