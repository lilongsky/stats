# Stats Compact

Independent fork of [exelban/stats](https://github.com/exelban/stats), based on **v3.0.22**. It adds configurable compact menu items, popup tools, local history and continuous calendar navigation. The upstream MIT license and author notices are preserved.

**[中文部署指南](README.zh-CN.md)** · **[Changes, validation and provenance](FORK.md)**

In the Clock calendar, click the year or month in the header to choose it from a native macOS pop-up menu. Selecting a year keeps the month, and selecting a month keeps the year. The year list offers 50 years on either side of the displayed year and recenters whenever it opens; scrolling, arrows and Today keep both selectors in sync.

Settings use a native source-list sidebar, a compact More menu and a native tab view for module panes. The widget-style selector appears only in Widgets, and Enable module stays inside the window content. Related options share equal-width, single-column groups. Use Command-comma to open general settings, Command-W to close the window and Command-Q to quit. Sensors settings keep their width when constructed before being attached to a window; fan preferences follow the physical fans reported by the reader, with an explanatory empty state when none are detected.

The Dashboard uses a compact device header and full-width Hardware and Device Information groups. Labels stay on one line; selectable values wrap within their own column. GPU, memory, disk and network preferences group monitoring, processes, transfer rates and connectivity controls by purpose. Network settings distinguish the traffic source, probe protocol, data format and rate unit. Scrolling over a fully visible popup-section list scrolls the surrounding settings page.

Each module's popup tools have four independent slots with application names and icons in native macOS menus. Per-widget size and spacing controls stay in sync with compact-mode defaults while preserving custom values; restore buttons apply only to the widget or tools being edited. The redesign follows Apple's [Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [Tab views](https://developer.apple.com/design/human-interface-guidelines/tab-views) and [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles) guidance. It uses tabs for pane switching, as recommended in the macOS section of [Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls). The 24-point content margins and 20-point group spacing are this fork's design choices, not numerical requirements from Apple. See [FORK.md](FORK.md#settings-interface) for implementation and validation scope.

Opening another copy of Compact checks for an earlier registered Compact instance and reuses it before initializing readers or settings. Quit Compact first when switching to a newly built version; official Stats keeps its separate application identity.

## Deployment

Build locally using the steps below. This fork currently has no custom GitHub release binary. The locally validated ZIP is an ad-hoc signed development package, not a notarized public release; validation on one Mac does not establish that another Mac will allow it.

### 1. Prepare the Mac and the official resource dependency

Use an **Apple Silicon Mac with macOS 14 or later**, Apple Command Line Tools, Python 3 and Git. The compiler targets macOS 12, but the required launch preflight uses `gktool`, which requires macOS 14 or later. This deployment procedure therefore requires macOS 14+.

Install Command Line Tools if needed with `xcode-select --install`, then confirm that `xcrun --find swiftc`, `python3 --version` and `git --version` work.

An official **Stats 3.0.22** bundle must be available at `/Applications/Stats.app`. Download that fixed version from the [upstream v3.0.22 release](https://github.com/exelban/stats/releases/tag/v3.0.22). If `/Applications/Stats.app` already exists, inspect its version first and preserve it; do not overwrite an existing official installation as part of deploying Compact. A different version must be resolved before continuing. Confirm the version with:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "/Applications/Stats.app/Contents/Info.plist"
```

The result must be `3.0.22`. **The build script does not validate this version for you.** Do not substitute a Homebrew or `latest` download for this fixed dependency.

The first build copies unchanged resources, helpers and desktop widgets from the official bundle. Later builds use the existing `build/Stats Compact.app` as their resource template. A full build recompiles the main app and all monitoring frameworks; it does not regenerate every copied resource. The original `/Applications/Stats.app` is not modified.

### 2. Clone and build

The clone command refuses to reuse a nonempty `stats-compact` directory. Use a new destination or your existing checkout as appropriate.

```sh
mkdir -p "$HOME/Developer" &&
cd "$HOME/Developer" &&
git clone --branch codex/stats-compact --single-branch \
  https://github.com/lilongsky/stats.git stats-compact &&
cd stats-compact
```

**Quit every running copy of Stats Compact before building.** From the repository root, run the full build:

```sh
python3 build-local.py &&
python3 check-local-app.py "build/Stats Compact.app"
```

The script compiles in a fresh staging bundle, ad-hoc signs the complete app, verifies its signature, and runs the Gatekeeper preflight when `gktool` is available. Compilation, signing and preflight failures occur before replacement of the existing build output. On success, the prior app and Swift modules are saved under `build/.previous-app-*`, then the new outputs are moved into place. These moves are sequential, not an atomic transaction across both directories; an interrupted replacement needs manual inspection.

### 3. Install the complete bundle and launch

**Quit Stats Compact before replacing an installed copy.** Run this from the repository root. It preserves an existing installation in a unique backup directory, then copies the entire bundle to an empty destination. `ditto` must not merge a new build into an existing app bundle.

```sh
(
  set -eu
  python3 check-local-app.py "build/Stats Compact.app"
  compact_install="$HOME/Applications/Stats Compact.app"
  mkdir -p "$HOME/Applications"
  if [ -L "$compact_install" ]; then
    printf '%s\n' "Stop: the installation path is a symbolic link; resolve it before installing." >&2
    exit 1
  fi
  if [ -e "$compact_install" ]; then
    compact_backup="$(mktemp -d "$HOME/Applications/Stats-Compact-backup.XXXXXX")"
    mv "$compact_install" "$compact_backup/Stats Compact.app"
    printf 'Previous installation saved to: %s\n' "$compact_backup"
  fi
  ditto "build/Stats Compact.app" "$compact_install"
  python3 check-local-app.py "$compact_install" && open "$compact_install"
)
```

The final check assesses the **installed path**. A failed copy or preflight stops the sequence before launch. Keep the printed backup path until the new installation has passed your checks.

Before **every manual launch**, use the same guarded command from the repository root:

```sh
python3 check-local-app.py "$HOME/Applications/Stats Compact.app" &&
open "$HOME/Applications/Stats Compact.app"
```

The preflight does not launch the app. It requires both a valid signature and an explicit Gatekeeper allowance. If you want launch at login, configure it in Compact's settings only after installing at the final path. Login settings are not migrated or registered by the build script; login launches do not run this Python command automatically.

### Identity, settings and data

| Item | Compact location or behavior |
| --- | --- |
| Bundle identifier and preference domain | `eu.exelban.Stats.Compact` |
| Preferences | `~/Library/Preferences/eu.exelban.Stats.Compact.plist` |
| Application data | `~/Library/Application Support/Stats Compact/` |
| History database | `~/Library/Application Support/Stats Compact/history-v1/history.sqlite` |
| Automatic updates | Initially set to `Never`; keep disabled and upgrade from source |

At first initialization, Compact copies preferences with the official app's `CPU_`, `GPU_`, `RAM_`, `Disk_`, `Network_`, `Battery_`, `Clock_`, `Sensors_` and `Bluetooth_` prefixes, then applies its compact layout defaults. Official authentication, login-item and update settings are not migrated. The separate bundle identifier keeps subsequent Compact preferences and local history separate from official Stats.

Normal app replacement does not reset these user data locations. For important data, quit Compact first and back up its **entire application-support directory**, including SQLite WAL files and the `lldb` cache, plus its preferences. Export the `eu.exelban.Stats.Compact` preference domain with `defaults export` to a new backup file. The `.previous-app-*` folders contain build outputs, not user data.

### Upgrade and roll back

Quit Compact, update the existing checkout, and perform a full build:

```sh
(
  set -eu
  cd "$HOME/Developer/stats-compact"
  git pull --ff-only
  python3 build-local.py
  python3 check-local-app.py "build/Stats Compact.app"
)
```

Then repeat the complete-bundle installation in step 3. Keep automatic updates set to `Never`: the upstream updater is not the deployment path for this fork.

To roll back **only the installed app**, use the exact installation backup printed in step 3. This is also the recovery path if installation or its final preflight fails. Quit Compact, replace the placeholder, and run from the repository root:

```sh
(
  set -eu
  compact_saved="$HOME/Applications/Stats-Compact-backup.REPLACE_WITH_EXACT_NAME/Stats Compact.app"
  compact_install="$HOME/Applications/Stats Compact.app"
  test -d "$compact_saved"
  test ! -L "$compact_install"
  python3 check-local-app.py "$compact_saved"
  if [ -e "$compact_install" ]; then
    compact_displaced="$(mktemp -d "$HOME/Applications/Stats-Compact-before-restore.XXXXXX")"
    mv "$compact_install" "$compact_displaced/Stats Compact.app"
    printf 'Displaced installation saved to: %s\n' "$compact_displaced"
  fi
  ditto "$compact_saved" "$compact_install"
  python3 check-local-app.py "$compact_install" && open "$compact_install"
)
```

This preserves the build directory and user data. The installed app already contains its runtime frameworks; the separate `build/modules` directory is needed for incremental compilation, not for launching an installed bundle.

For a build rollback, choose one exact `build/.previous-app-*` directory that contains **both** `Stats Compact.app` and `modules`. A first-build backup may be empty. Replace the placeholder below with the chosen directory name, keep Compact quit, and run from the repository root:

```sh
(
  set -eu
  compact_restore="build/.previous-app-REPLACE_WITH_EXACT_NAME"
  test -d "$compact_restore/Stats Compact.app"
  test -d "$compact_restore/modules"
  python3 check-local-app.py "$compact_restore/Stats Compact.app"
  compact_current="$(mktemp -d "build/.before-rollback.XXXXXX")"
  if [ -e "build/Stats Compact.app" ]; then
    mv "build/Stats Compact.app" "$compact_current/Stats Compact.app"
  fi
  if [ -e "build/modules" ]; then
    mv "build/modules" "$compact_current/modules"
  fi
  ditto "$compact_restore/Stats Compact.app" "build/Stats Compact.app"
  ditto "$compact_restore/modules" "build/modules"
  python3 check-local-app.py "build/Stats Compact.app"
)
```

Restore the app and modules from the **same** backup; do not mix builds. Repeat step 3 to deploy the restored bundle, including preflight on the actual installed path. This restores build artifacts only, so keep a separate user-data backup when needed.

For development after a Clock-only change, `python3 build-local.py --only Clock Stats` is available when a matching app and modules already exist. First builds, deployment upgrades and any Kit source change should use the full command. `--only` does not inspect changed source files; explicitly including `Kit` in its arguments expands to a full rebuild.

### Check the installation and handle failures

The currently available main UI has been reviewed in Simplified Chinese with light appearance, within the limits in the [UI coverage matrix](Tests/ui-validation.md). The rebuilt app passed live rechecks of GPU percentage updates, Battery popup layout and the Clock table's enabled column. English/Simplified Chinese, light/dark and multiple-width automated coverage is offscreen; see [validation scope](FORK.md#validation) for results and limits.

- Confirm that preflight prints `Signature verified; Gatekeeper allows:` for `~/Applications/Stats Compact.app`, then launch through the guarded command.
- Check that menu items remain independently movable and configurable, including CPU/GPU graphs, pie size and spacing. Check live data and the CPU popup after frequency samples arrive, section reordering and process-count changes; sections should remain separate.
- Open the Dashboard, General, GPU, memory, disk, network and Sensors settings, switch module panes and use keyboard navigation in the sidebar. Check that every settings group fills the same form width, labels and controls remain separate, and the widget-style selector appears only in Widgets. Scroll over the popup-section list in both directions and check numeric thresholds with unit selectors. Dashboard labels should remain horizontal and long values should wrap. Fan preferences should match the detected hardware.
- Check that footer tool choices persist and open the selected apps. In the Clock calendar, check fast scrolling, momentum, abrupt reversal and Today. Quit and reopen through preflight to check that preferences and history persist. See [FORK.md](FORK.md) for the automated checks and their scope.
- For build failures, read the relevant `build/*.log` file, including `sign.log`, `verify-signature.log` or `preflight.log`. Confirm the official resource dependency is exactly 3.0.22. If an earlier output was based on the wrong resource version, preserve its app and modules together before rebuilding from a clean output with the correct official dependency.
- If macOS reports that the app is damaged or altered, or preflight refuses it, **stop and do not launch it**. Preserve the failing output and logs, and inspect or rebuild the complete bundle. Do not disable Gatekeeper or remove quarantine attributes to bypass the check. An interrupted installation may leave a partial target; use the saved complete bundle for recovery.

## Upstream reference

The remaining README is retained from **official Stats** for its features, FAQs, credits and license. Its installation, download, Homebrew, SSH, requirements, updater and support instructions describe the upstream application. Use the Compact deployment guide above for this fork.

---

# Official Stats

<a href="https://github.com/exelban/stats/releases"><p align="center"><img src="https://github.com/exelban/stats/raw/master/Stats/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="120"></p></a>

[![Stats](https://cdn.mac-stats.com/assets/images/menus.png)](https://github.com/exelban/stats/releases)
[![Stats](https://cdn.mac-stats.com/assets/images/popups.png)](https://github.com/exelban/stats/releases)

macOS system monitor in your menu bar

## Official Stats installation

These download, Homebrew and SSH instructions install **official Stats**, not Stats Compact.

### Official download
You can download the latest version [here](https://github.com/exelban/stats/releases/latest/download/Stats.dmg).
This will download a file called `Stats.dmg`. Open it and move the app to the application folder.

### Official Homebrew package
To install it using Homebrew, open the Terminal app and type:
```bash
brew install stats
```

### Official headless (SSH) installer
To install Stats remotely over SSH and set it up as a remote monitoring agent, run:
```bash
curl -fsSL https://cdn.mac-stats.com/install.sh | bash
```
The script installs the app, enables the Remote module and prints a URL with an authorization code - open it on any device and sign in to your System Stats account to authorize the machine. After that Stats starts streaming metrics to your account and is registered to launch automatically at login and restart if it stops.
The Mac needs an active user session (a locked screen is fine) to run the app; on a fully headless machine Stats will start at the next login.

### Official Stats uninstall
Run the uninstall script bundled with the app (requires administrator privileges to remove the SMC helper):
```bash
sh /Applications/Stats.app/Contents/Resources/Scripts/uninstall.sh
```

### Legacy version
Legacy version for older systems could be found [here](https://mac-stats.com/downloads).

## Official Stats requirements
Stats is supported on macOS 12 (Monterey) and newer.
Beta versions of macOS are not supported - only stable releases.

## Features
Stats is an application that allows you to monitor your macOS system.

 - CPU utilization
 - GPU utilization
 - Memory usage
 - Disk utilization
 - Network usage
 - Battery level
 - Fan's control (not maintained)
 - Sensors information (Temperature/Voltage/Power)
 - Bluetooth devices
 - Multiple time zone clock

## FAQs

### How do you change the order of the menu bar icons?
macOS decides the order of the menu bar items not `Stats` - it may change after the first reboot after installing Stats.

To change the order of any menu bar icon - macOS Mojave (version 10.14) and up.

1. Hold down ⌘ (command key).
2. Drag the icon to the desired position on the menu bar.
3. Release ⌘ (command key)

### Stats icons do not appear in the menu bar
macOS 26 introduced a new privacy control under System Settings → Menu Bar. Apps must be explicitly allowed there to display menu bar items. If Stats is running with at least one module active and one widget enabled, but none of its icons show up in the menu bar, this is almost certainly the cause. More details you can find [here](https://github.com/exelban/stats/issues/3120).

**Solution:** open **System Settings → Menu Bar** and toggle **Stats** ON.

### Desktop widgets not showing the data
Due to a problem with high data load in the system process (`chronod`) responsible for communication between the app and widgets, communication is disabled by default on the Stats side. To enable it, the `macOS widgets` option must be enabled in the Stats settings. More details you can find [here](https://github.com/exelban/stats/issues/2733).

**Solution:** open **Stats Settings** and toggle **macOS widgets** ON.

### Wi-Fi network name shows Unknown
macOS requires Location Services permission to read the Wi-Fi network name. If access for Stats is disabled, the network name may show as `Unknown` without a permission popup.

**Solution:** open **System Settings → Privacy & Security → Location Services**, make sure Location Services is enabled, and toggle **Stats** ON. Then quit and reopen Stats.

### How to reduce energy impact or CPU usage of Stats?
Stats tries to be efficient as it's possible. But reading some data periodically is not a cheap task. Each module has its own "price". So, if you want to reduce energy impact from the Stats you need to disable some Stats modules. The most inefficient modules are Sensors and Bluetooth. Disabling these modules could reduce CPU usage and power efficiency by up to 50% in some cases.

### Fan control
Fan control is in legacy mode. It does not receive any updates or fixes. It's not dropped from the app just because in the old Macs it works pretty acceptable. I'm open to accepting fixed or improvements (via PR) for this feature in case someone would like to help with that. But have no option and time to provide support for this feature.

### Sensors show incorrect CPU/GPU core count
CPU/GPU sensors are simply thermal zones (sensors) on the CPU/GPU. They have no relation to the number of cores or specific cores.
For example, a CPU is typically divided into two clusters: efficiency and performance. Each cluster contains multiple temperature sensors, and Stats simply displays these sensors. However, "CPU Efficient Core 1" does not represent the temperature of a single efficient core—it only indicates one of the temperature sensors within the efficiency core cluster.
Additionally, with each new SoC, Apple changes the sensor keys. As a result, it takes time to determine which SMC values correspond to the appropriate sensors. If anyone knows how to accurately match the sensors for Apple Silicon, please contact me.

### App crash – what to do?
First, ensure that you are using the latest version of Stats. There is a high chance that a fix preventing the crash has already been released. If you are already running the latest version, search both [open and closed issues](https://github.com/exelban/stats/issues?q=is%3Aissue). If the crash has already been reported, add new diagnostic information to the existing issue when comments are open instead of opening a duplicate. Otherwise, use the [bug report form](https://github.com/exelban/stats/issues/new?template=bug_report.yml) and include your Mac model, chip, macOS version and build, Stats version, steps to reproduce, and the complete crash report from Console.

### Why my issue was closed without any response?
Most probably because it's a duplicated issue and there is an answer to the question, report, or proposition. Please use a search by closed issues to get an answer.
So, if your issue was closed without any response, most probably it already has a response.

### External API
Stats does not collect any telemetry or analytics. The only external requests it makes are to the following APIs:

- https://api.mac-stats.com – For update checks and retrieving the public IP address
- https://api.github.com – Fallback for update checks

Both of these APIs are used to check for updates. Additionally, an external request is required to obtain the public IP address. I do not want to use any third-party providers for retrieving the public IP address, so I use my own server for this purpose.

If you have concerns about these requests, you have a few options:

- propose a PR that allows these features to work without an external server
- block both of these servers using any network filtering app (if you're reading this, you're likely using something like Little Snitch, so you can easily do this). In this case do not expect to receive any updates or see your public IP in the network module.

### How to contribute to the project?
If you want to develop a new feature, or you've found something that doesn't work, the first step is to open an issue so the feature or problem can be discussed. Pull requests should only be opened for existing issues and after discussion; otherwise, they may be closed automatically. There are a few cases where this can be skipped: language changes, and contributors who have already made significant contributions and whose implementations align well with the project.

## Open source, but not open contribution
Stats is an open-source project: the full source code is available under the MIT license, and you are free to read it, learn from it, fork it, and build your own version of the app.

However, it is not an open-contribution project. Stats is developed and maintained by a single person, and keeping the project stable and coherent takes priority over accepting every proposed change. Reviewing external code, testing it across different Macs and macOS versions, and maintaining it afterward often takes more time than writing it in the first place.

For that reason, unsolicited pull requests are generally not accepted and may be closed without review. If you want to change or add something, please open an issue first so it can be discussed. The exceptions are translations and language fixes, which are always welcome, and contributions from people who have already made significant contributions to the project.

The best ways to support the project are reporting bugs, improving translations, and proposing ideas through issues.

## Supported languages
- English
- Polski
- Українська
- Русский
- 中文 (简体) (thanks to [chenguokai](https://github.com/chenguokai), [Tai-Zhou](https://github.com/Tai-Zhou), and [Jerry](https://github.com/Jerry23011))
- Türkçe (thanks to [yusufozgul](https://github.com/yusufozgul) and [setanarut](https://github.com/setanarut))
- 한국어 (thanks to [escapeanaemia](https://github.com/escapeanaemia) and [iamhslee](https://github.com/iamhslee))
- German (thanks to [natterstefan](https://github.com/natterstefan) and [aneitel](https://github.com/aneitel))
- 中文 (繁體) (thanks to [iamch15542](https://github.com/iamch15542) and [jrthsr700tmax](https://github.com/jrthsr700tmax))
- Spanish (thanks to [jcconca](https://github.com/jcconca))
- Vietnamese (thanks to [HXD.VN](https://github.com/xuandung38))
- French (thanks to [RomainLt](https://github.com/RomainLt))
- Italian (thanks to [gmcinalli](https://github.com/gmcinalli))
- Portuguese (Brazil) (thanks to [marcelochaves95](https://github.com/marcelochaves95) and [pedroserigatto](https://github.com/pedroserigatto))
- Norwegian Bokmål (thanks to [rubjo](https://github.com/rubjo))
- 日本語 (thanks to [treastrain](https://github.com/treastrain))
- Portuguese (Portugal) (thanks to [AdamModus](https://github.com/AdamModus))
- Czech (thanks to [mpl75](https://github.com/mpl75))
- Magyar (thanks to [moriczr](https://github.com/moriczr))
- Bulgarian (thanks to [zbrox](https://github.com/zbrox))
- Romanian (thanks to [razluta](https://github.com/razluta))
- Dutch (thanks to [ngohungphuc](https://github.com/ngohungphuc))
- Hrvatski (thanks to [milotype](https://github.com/milotype))
- Danish (thanks to [casperes1996](https://github.com/casperes1996) and [aleksanderbl29](https://github.com/aleksanderbl29))
- Catalan (thanks to [davidalonso](https://github.com/davidalonso))
- Indonesian (thanks to [yooody](https://github.com/yooody))
- Hebrew (thanks to [BadSugar](https://github.com/BadSugar))
- Slovenian (thanks to [zigapovhe](https://github.com/zigapovhe))
- Greek (thanks to [sudoxcess](https://github.com/sudoxcess) and [vaionicle](https://github.com/vaionicle))
- Persian (thanks to [ShawnAlisson](https://github.com/ShawnAlisson))
- Slovenský (thanks to [martinbernat](https://github.com/martinbernat))
- Thai (thanks to [apiphoomchu](https://github.com/apiphoomchu))
- Estonian (thanks to [postylem](https://github.com/postylem))
- Hindi (thanks to [patiljignesh](https://github.com/patiljignesh))
- Finnish (thanks to [eightscrow](https://github.com/eightscrow))
- Bengali (thanks to [adnan29979](https://github.com/adnan29979))
- Tamil (thanks to [sabapathy7](https://github.com/sabapathy7))

You can help by adding a new language or improving the existing translation.

## License
[MIT License](https://github.com/exelban/stats/blob/master/LICENSE)
