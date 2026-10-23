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
- A native source-list settings sidebar, a More menu, native tabbed panes and equal-width forms, with contextual widget sizing, popup shortcuts and hardware-based fan preferences.

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

The window uses an AppKit source-list sidebar with native selection and keyboard
navigation. A compact More menu retains support, report, pause/resume and quit
actions. Module panes use a native tab view; the widget-style selector
appears only in Widgets. The Enable module switch is in the window body, while
the toolbar uses explicit Settings / Preview labels. Related options form one
column of equal-width groups with wrapping explanations, semantic system colors
and standard controls. The default window is larger, while valid saved window
frames are preserved. The settings window supports Command-comma for general
settings, Command-W to close the window and Command-Q to quit the app.

The design references Apple's [Settings](https://developer.apple.com/design/human-interface-guidelines/settings),
[Layout](https://developer.apple.com/design/human-interface-guidelines/layout),
[Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars),
[Tab views](https://developer.apple.com/design/human-interface-guidelines/tab-views)
and [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles)
guidance. Native tabs follow the macOS pane-switching recommendation in
[Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls).
The 24-point content margins and 20-point group spacing are local
design choices, not numerical requirements imposed by Apple. The window also
contains a monitoring Dashboard, so manual resizing remains available.

The Dashboard fills the content area with a compact device header and separate
Hardware and Device Information groups. Its labels share a single-line column;
selectable values wrap within the remaining width. The scroll viewport is pinned
to all four content edges. GPU and disk monitoring options share a group, memory
process refresh controls sit with process options, and network traffic and
connectivity preferences have distinct headings and field names. Unit thresholds
retain the natural widths of the numeric field, stepper and unit menu. A popup
section list that fits completely forwards wheel events to the settings page;
lists with more than eight rows retain their internal native scroll view.

The form container establishes card widths explicitly rather than inferring
its layout from an existing superview. Sensors builds static cards before being
attached to a window, then adds or replaces sensor groups when a reader list
arrives. Both paths use the same form width. Fan preferences depend on actual
physical Fan records in that list, rather than a Mac model or CPU architecture;
when none are reported, the form shows an explanatory empty state.

Each module has four independent application shortcut slots. Native macOS
pop-up menus display application names and icons, support hiding a slot or
choosing another application, and offer a reset for that module's tools. Size
and spacing have a separate reset scoped to the current widget. When compact
mode or its global default changes, the displayed switch and numeric defaults
update together; explicit custom dimensions and spacing are retained.

The organization also incorporates useful ideas observed in iStat Menus:
separate global and module settings, keep controls with the object they affect,
and make reset scope clear. The implementation uses Stats source and AppKit;
proprietary UI resources are not reused.

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
python3 Tests/run-dashboard-checks.py --output-dir build/dashboard-evidence
python3 Tests/run-dashboard-checks.py --output-dir build/dashboard-evidence-en --locale en_US --language en
python3 Tests/run-popup-scroll-checks.py
python3 Tests/run-cpu-popup-checks.py
python3 Tests/run-clock-settings-checks.py --output-dir build/clock-settings-evidence
python3 Tests/run-battery-popup-checks.py --language zh-Hans en
python3 Tests/run-calendar-checks.py
python3 Tests/run-calendar-gestures.py
python3 Tests/run-calendar-performance.py
```

Calendar tests compile the actual private production views into isolated AppKit
checks. The gesture check replays inertial delta curves and abrupt reversals
through the native clip view. It does not simulate a physical trackpad or measure
AppKit's native momentum animator. See [PERFORMANCE.md](PERFORMANCE.md) for the
measured scope and performance comparison.

The settings runner checks the reusable production forms and popup editors
with isolated preferences, then writes offscreen light/dark PNGs. It covers
wrapping, control alignment, complete table rows, section visibility/order,
shortcut choices and widget size/default/reset synchronization.

The Dashboard runner compiles the real view with synthetic formatted device data,
including long values, without querying the machine's serial number. It checks
420-, 540- and 760-point widths, light/dark appearance, construction order, full
width, single-line labels, complete wrapping, scrolling and uptime refresh. The
popup-scroll runner checks the real short-list responder chain in both directions,
plus long-list keyboard scrolling and section reorder controls. Offscreen wheel
events establish event routing; actual scrolling displacement is checked in the
running app. The settings runner also checks native unit thresholds in enabled
and disabled states at three widths and exercises their existing input callbacks.

It also compiles the actual internal Sensors module settings, popup settings,
notification settings and production sensor value models into a temporary app
with its own preference and notification identity. That regression constructs the real form
before a window exists, supplies reader lists both before and after mounting,
and exercises repeated refreshes, empty lists, widget changes and remounting.
It checks form edges, nonoverlapping cards, visible labels and native control
alignment at 420-, 540- and 680-point form widths in light and dark appearances.
Popup and notification cards also exercise their real construction and refresh
paths, including shortcut controls and the alert-duration group.
Sensor and Fan records are fixtures: the helper does not start telemetry
readers, load the application delegate, show a production window or command a
physical fan. These checks therefore establish layout and state behavior;
installed-window appearance and hardware behavior need separate live checks.

The redesigned settings checks pass 1,769 assertions in Chinese and 1,769 in
English. Each language exports 40 isolated previews. The checks include the
shortcut recorder button inside its composite control and a compact duration
editor, in addition to card and row alignment. Dashboard checks pass 1,381 assertions per language; popup scroll routing passes
26. CPU popup checks pass 96 assertions and calendar checks pass 320 against the
same rebuilt Kit: 6,742 assertions in that regression group. That group was not
rerun in the final UI pass because Kit did not change. The later Clock settings
check passes 211 assertions in Chinese across multiple widths and light/dark
appearance, including the existing callbacks. A one-time GPU popup probe passes
35 checks for the percentage-transition fix. Battery popup checks pass 251
assertions in Chinese and 251 in English (502 total) in isolated light/dark
views. GPU, Battery and Clock also passed post-fix live review in the rebuilt
app; the matrix records the tested states and remaining coverage limits.

The CPU popup regression check compiles the real production popup in a hidden
AppKit window with isolated preferences. It covers late frequency arrival,
reopening, saved section order, hide/restore and process-count changes, checking
content heights and section geometry. Frequency participates in customization
and defaults to the position before top processes. Its zero-height placeholder
also makes it configurable before the first telemetry sample. The helper waits
for callback completion instead of assuming a fixed run-loop delay.

A live Simplified Chinese light-appearance review checked the Dashboard,
General, the available module settings pages and actual menu-bar popups listed
in the [UI coverage matrix](Tests/ui-validation.md). A Popup settings tab and
the module's actual popup are recorded separately. CPU, GPU, RAM, Disk and Net
have each had all four settings pages reviewed. CPU and Net actual popups were
checked at both ends of their scroll range; RAM and Disk actual popups were
also reviewed. The Dashboard was checked at both ends in a 760 × 540 window:
groups fill the viewport, labels remain horizontal and long values wrap.

The broader review found three issues: percentage crossfades in the GPU popup,
overlapping Battery popup content, and a clipped enabled column in Clock
settings. The rebuilt app's live review confirms clean updates in all three GPU
circles, nonoverlapping Battery adapter/health/details sections and a fixed
footer, and all five Clock columns with both enabled checkboxes visible at
760 × 540. Clock rows also use a more compact height. Bluetooth coverage is
limited to the visible disabled/no-device state; Remote coverage is limited to
its unauthenticated settings page. Sensors Widgets was checked with no active
widget. The matrix also records dialog cancellation and the History
interactions actually tested. First-launch setup, update/install flows,
authenticated Remote operation and hardware actions remain outside this review.

Scrolling over the formerly trapped GPU popup-section list now moves the outer
settings page; reversing the scroll restores its original position. The disabled
RAM Swap and Net threshold controls keep the switch, number, stepper and unit
separate. Enabled threshold states are covered by the isolated production-view
tests, without enabling notifications in the user's preferences.

The shortcut recorder and compact duration editor align on the right.
Command-comma opens general settings, Command-W closes the window while
monitoring continues, and Command-Q exits. The settings/preview button retains
the correct state after closing and reopening the window. The running app has
one Compact process and seven independent menu items. The live review covers
Simplified Chinese in light appearance; English/Simplified Chinese, light/dark
and multiple-width coverage comes from the offscreen checks described above,
within each runner's stated scope. Apple Human Interface Guidelines informed
the design; this is not Apple certification. Use the README checklist to
validate the installed version on the target Mac.

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
