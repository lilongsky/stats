# Stats Compact

This branch is an independent customization of exelban/stats v3.0.22
(`1282cd52d5bc3b40ca631069e348f8a2c1c8aad9`). It keeps the upstream MIT license
and author notices. It is not an official Stats release.

## Changes

- Independent menu items with per-widget compact sizing, graph dimensions and spacing. CPU and GPU keep their own configurable graph widgets.
- Repeated Compact launches reuse an earlier registered instance before readers or preferences are initialized, including launches from another build path.
- Contextual popup application shortcuts, with four configurable slots per module.
- Popup section visibility and ordering with an actual popup preview.
- Local SQLite history for four time ranges, mean/peak display and CSV export.
- Sustained notification thresholds and optional per-fan temperature curves.
- A continuous Clock calendar with native year/month selectors, a Today button, bounded reusable date views and one hover target.
- A labeled Settings sidebar entry, aligned settings groups and contextual native controls for widget sizing and popup shortcuts.

The menu padding implementation probes private AppKit selectors at runtime and
falls back to the system behavior when unavailable. It needs revalidation after
macOS changes. It does not change global menu-bar spacing preferences.

Fan curves are disabled by default. The development machine has no controllable
fan, so physical fan actuation was not tested. OS notification delivery was not
triggered in the automated model checks.

The calendar uses AppKit's [NSPopUpButton](https://developer.apple.com/documentation/appkit/nspopupbutton)
for independent year and month selection, following Apple's
[pop-up button guidance](https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons).
It retains system menu rendering, keyboard interaction and accessibility, uses
localized month names and field order, and builds the year list only when opened.
The calendar checks dispatch native control actions and verify date navigation
and geometry; they do not drive pointer-based menu tracking or Escape dismissal.
Live UI checks also opened both native menus, changed the month and year while
preserving the other field, canceled a menu with Escape without closing the
popup, and used Today to restore the current month.

## Settings interface

The Settings page is available in the sidebar. A compact app identity row leaves
more room for General, Menu bar, Advanced menu bar and Settings Data groups.
Related controls share aligned rows; explanatory captions wrap to the available
width. Each widget has a small labeled header and its own size and spacing
controls. Popup sections use named rows with visibility switches on the right.

Each module has four independent application shortcut slots. Native macOS
pop-up menus display application names and icons, support hiding a slot or
choosing another application, and offer a reset for that module's tools. Size
and spacing have a separate reset scoped to the current widget. When compact
mode or its global default changes, the displayed switch and numeric defaults
update together; explicit custom dimensions and spacing are retained.

These changes follow the useful organization seen in iStat Menus: separate
global and module settings, keep controls with the object they affect, and make
reset scope clear. Controls are implemented in AppKit; proprietary UI resources
are not reused. Offscreen checks of the reusable settings views and popup
editors pass 71 assertions in each of Chinese and English, at 540- and 680-point
widths in light and dark appearances. They cover alignment, wrapping, complete
first/last table rows, section actions, tool choices and size/default/reset
synchronization. The renderer also exposed and verified a fix for the last
section row being clipped by automatic table insets. These renders are isolated
views. The final Chinese light-appearance application window was also checked
live: General and CPU module cards fill the pane, section actions and switches
remain visible, and all four application shortcut rows align within the form.

A subsequent full-window review found that a hidden combined-item preview
constrained the General page width, while module tab contents and older module
cards did not fill their viewport. The General scroll view now pins to its
container; the fixed-width preview has a flexible wrapper, and module panes,
tabs and cards follow the available width. The ordinary module-stack regression
covers two cards with different content lengths without manual card widths.

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
python3 Tests/run-settings-checks.py
python3 Tests/run-settings-checks.py --locale en_US --language en
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
96 assertions, including process counts of 0, 3, 8, 10 and 20. The original 89
layout checks are retained, with seven explicit async-completion checks. The
helper waits for callback completion instead of assuming a 20 ms run-loop delay.

After the shared settings layout changes, the full build, strict signature
verification and Gatekeeper preflight passed. The settings checks above, 96 CPU
popup checks and 320 calendar checks passed against that final build. The
settings runner writes offscreen PNGs under the build directory by default;
it uses isolated preferences and never opens the production settings window.

The final deployed app was also launched from a second build directory while
the existing copy was running: it returned successfully without initializing a
second instance. Native menu-bar inspection confirmed one Compact process with
seven independent items.

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
