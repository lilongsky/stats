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

For the complete deployment, upgrade and rollback procedure, see the
[English README](README.md#deployment) or [中文 README](README.zh-CN.md).

Requirements for that workflow: Apple Silicon, macOS 14 or later, Apple Command
Line Tools, Python 3, and an official Stats 3.0.22 installation at
`/Applications/Stats.app`. The app targets macOS 12, but the execution preflight
requires macOS 14 or later. Verify the installed official version yourself; the
builder does not check its version number.

```sh
python3 build-local.py &&
python3 check-local-app.py "build/Stats Compact.app"
```

Quit the running Compact app before rebuilding. The script compiles into a
fresh temporary application and module directory, signs and checks the complete
bundle, then replaces the output. The previous app and modules remain in a
hidden `.previous-app-*` folder for rollback. Compilation, signing and preflight
failures occur before output replacement. The final app and module moves are
sequential, not an atomic transaction; inspect the outputs and backups before
continuing if replacement is interrupted.

The script compiles the main application and all monitoring frameworks. The
first build uses the installed official app for unchanged resources, helpers and
desktop widgets; later builds copy those from the existing Compact output.
It creates an ad-hoc signed `build/Stats Compact.app` with bundle identifier
`eu.exelban.Stats.Compact`; it does not replace the official installation.
On macOS 14 or later, the build also verifies the signature and pre-scans the
complete app with Gatekeeper. Run `check-local-app.py` before each manual launch;
it checks without launching the target and stops unless system policy allows
it. All local test runners check their generated executables before running;
the AppKit runners also check the framework app before compilation. The
preflight-guarded runners require macOS 14 or later. Signature integrity alone does not prove that system policy permits
execution.

The ordinary upstream Xcode configuration retains upstream naming, so use this
script when you need the separate Compact identity and preferences.

The local app initializes preferences for allowlisted monitoring modules from
Stats once, then sets up the compact layout and uses its own preferences and
data directory. Automatic updates default to Never for the custom build; keep
that setting when deploying updates manually. Login credentials and login/update
settings are not migrated.

After a Clock-only change, `python3 build-local.py --only Clock Stats` can rebuild
the affected targets when a matching app and module directory already exist.
Use a full build after Kit changes because the build does not enable Swift
library evolution. Explicitly selecting Kit with `--only` also expands to a full
build; the script does not detect source changes for other partial selections.

## Validation

After building, run:

```sh
python3 Tests/run-feature-models.py
python3 Tests/run-cpu-popup-checks.py
python3 Tests/run-calendar-checks.py
python3 Tests/run-calendar-gestures.py
python3 Tests/run-calendar-performance.py
```

Calendar tests compile the actual private production views into isolated AppKit
checks. The gesture check replays inertial delta curves and abrupt reversals
through the native clip view. It does not simulate a physical trackpad or measure
AppKit's native momentum animator. See [PERFORMANCE.md](PERFORMANCE.md) for the
measured scope and performance comparison.

The CPU popup regression check compiles the real production popup in a hidden
AppKit window with isolated preferences. It covers late frequency arrival,
reopening, saved section order, hide/restore and process-count changes, checking
content heights and section geometry. Frequency participates in customization
and defaults to the position before top processes. Its zero-height placeholder
also makes it configurable before the first telemetry sample. The check passes
89 assertions, including process counts of 0, 3, 8, 10 and 20.

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
