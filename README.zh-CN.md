# Stats Compact 部署指南

[English](README.md) · [分支说明与验证范围](FORK.md) · [日历性能与验证范围](PERFORMANCE.md)

Stats Compact 是基于 [exelban/stats](https://github.com/exelban/stats) v3.0.22 的独立定制分支，保留上游 MIT 许可证和作者声明。它提供独立的紧凑菜单栏项目、弹窗工具和连续滚动日历，应用标识为 `eu.exelban.Stats.Compact`。

在时钟日历标题中，点击年份或月份即可打开对应的 macOS 原生选择菜单。选年保留月份，选月保留年份。年份列表包含当前浏览年份前后各 50 年，每次打开时重新居中；滚动、月份箭头和“今天”会同步两个选择器。

设置现在有具名的侧栏入口，通用、菜单栏、高级选项和设置数据分组统一对齐。每个指标的弹窗快捷工具提供四个独立槽位，使用显示应用名称与图标的 macOS 原生菜单。各小组件的尺寸、间距输入会同步紧凑模式的默认值，并保留自定义数值；恢复按钮只作用于当前小组件或当前指标的工具。验证范围见 [FORK.md](FORK.md#settings-interface)。

目前只有开发机上的本地构建 ZIP，尚未在 GitHub 发布定制版二进制安装包。现有 ZIP 是临时签名的开发包，没有作为公证安装包发布，也未验证其他机器的系统策略是否允许运行。请在目标 Mac 上按本指南构建和预检。

## 环境与官方资源基线

需要 Apple Silicon Mac、macOS 14 或更新版本、Apple Command Line Tools、Python 3 和 Git。构建脚本的编译目标是 `arm64-apple-macos12.0`，但本指南要求每次手动启动前使用 `/usr/bin/gktool` 预检，因此部署要求为 macOS 14+。

可以先检查工具；如尚未安装 Command Line Tools，再运行 `xcode-select --install` 并完成系统安装流程。

```sh
uname -m
sw_vers -productVersion
xcode-select -p
xcrun --find swiftc
python3 --version
git --version
test -x /usr/bin/gktool
```

从[官方 v3.0.22 发布页](https://github.com/exelban/stats/releases/tag/v3.0.22)取得官方 Stats **3.0.22**，放在 `/Applications/Stats.app`。若该路径已有官方安装，先核对版本并保留原包；不要为了部署 Compact 覆盖现有官方应用。版本不符时先解决资源基线，再继续。不要用自动指向最新版的下载地址或 Homebrew 安装结果代替这个固定版本。读取版本，确认输出恰为 `3.0.22`：

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "/Applications/Stats.app/Contents/Info.plist"
```

构建脚本不会自动核对官方 app 的版本。初次构建从它复制保留的资源、辅助程序和桌面小组件；已有 `build/Stats Compact.app` 时，后续构建以该既有输出作为资源模板。主应用及监控框架仍会按本指南全量重编。保留官方资源基线，Compact 始终安装到独立路径，不能用定制版覆盖 `/Applications/Stats.app`。

## 获取源码并全量构建

若 Compact 正在运行，先通过应用菜单退出，再构建或替换安装包。以下使用新的 `stats-compact` 目录；目录已存在时，请使用既有仓库或选择新的目标目录。

```sh
git clone --branch codex/stats-compact --single-branch https://github.com/lilongsky/stats.git stats-compact &&
cd stats-compact &&
python3 build-local.py &&
python3 check-local-app.py "build/Stats Compact.app"
```

以下命令均从 `stats-compact` 仓库根目录运行。

`build-local.py` 会在 `build` 中创建新的临时 app 和 modules 目录，重编主应用与监控框架，再进行本地临时签名、签名验证和完整 app 预检。输出为 `build/Stats Compact.app`。本指南统一使用 `python3 build-local.py` 全量构建。

编译、签名或预检失败时，脚本尚未替换既有 app 和 modules；查看终端提示及 `build/*.log`。通过这些阶段后，脚本顺序移动 app 与 modules，旧输出保存在 `build/.previous-app-*` 下。两个目录的替换不是一次原子事务；若替换阶段中断，先核对输出和备份目录，不要直接启动。

## 安装独立应用

安装位置为 `~/Applications/Stats Compact.app`。先退出正在运行的 Compact。下面的命令会检查构建输出；若已有安装，先将**整个旧 app** 移到新建的备份目录，再用 `ditto` 将完整新 bundle 复制到空目标路径，最后预检实际安装路径并启动。

```sh
(
    set -eu
    compact_install="$HOME/Applications/Stats Compact.app"
    python3 check-local-app.py "build/Stats Compact.app"
    mkdir -p "$HOME/Applications"
    if [ -L "$compact_install" ]; then
        printf '%s\n' '安装目标是符号链接；请先核对实际安装位置。' >&2
        exit 1
    fi
    if [ -e "$compact_install" ]; then
        compact_backup=$(mktemp -d "$HOME/Applications/Stats-Compact-backup.XXXXXX")
        mv "$compact_install" "$compact_backup/Stats Compact.app"
        printf '旧安装备份：%s\n' "$compact_backup/Stats Compact.app"
    fi
    ditto "build/Stats Compact.app" "$compact_install"
    python3 check-local-app.py "$compact_install" && open "$compact_install"
)
```

不要将 `ditto` 直接指向已有旧 bundle 来合并覆盖，也不要单独替换其中的可执行文件或 framework。保留终端打印的完整旧安装备份路径；复制或检查失败时，先处理失败原因。

## 每次启动前检查实际路径

`check-local-app.py` 只检查，不启动目标。它要求严格签名验证通过，并且 Gatekeeper 明确允许该路径；仅签名通过还不够。每次手动启动已安装版本，都运行：

```sh
python3 check-local-app.py "$HOME/Applications/Stats Compact.app" && open "$HOME/Applications/Stats Compact.app"
```

若选择直接运行构建目录中的版本，则同样检查该实际路径：

```sh
python3 check-local-app.py "build/Stats Compact.app" && open "build/Stats Compact.app"
```

保留 `&&`，检查失败就不会执行 `open`。构建目录的通过结果不能代替安装后路径的检查；复制、移动或更新后需要重新预检。

## 升级

1. 通过应用菜单退出 Compact。
2. 在原来的 `stats-compact` 仓库中快进更新，然后全量构建、预检：

   ```sh
   git pull --ff-only &&
   python3 build-local.py &&
   python3 check-local-app.py "build/Stats Compact.app"
   ```

3. 按上面的“安装独立应用”命令整包替换安装。它会保留当前安装的完整备份，并在启动前再次检查实际安装路径。
4. 完成人工验收，再决定是否清理旧备份。

若 `git pull --ff-only` 失败，先保留并处理本地改动或分支状态，不要直接覆盖工作目录。首次初始化默认将自动更新设为 `Never`；请保持关闭，使用这里的源码升级流程，避免改用官方版更新包。

## 回滚到确切备份

### 只回滚已安装应用

使用“安装独立应用”步骤打印的确切安装备份路径。安装复制或最终预检失败时，也可按此恢复。先退出 Compact，将占位路径替换为实际备份，再从仓库根目录执行：

```sh
(
    set -eu
    compact_saved="$HOME/Applications/Stats-Compact-backup.替换为实际目录名/Stats Compact.app"
    compact_install="$HOME/Applications/Stats Compact.app"
    test -d "$compact_saved"
    test ! -L "$compact_install"
    python3 check-local-app.py "$compact_saved"
    if [ -e "$compact_install" ]; then
        compact_displaced=$(mktemp -d "$HOME/Applications/Stats-Compact-before-restore.XXXXXX")
        mv "$compact_install" "$compact_displaced/Stats Compact.app"
        printf '被替换的安装保存在：%s\n' "$compact_displaced"
    fi
    ditto "$compact_saved" "$compact_install"
    python3 check-local-app.py "$compact_install" && open "$compact_install"
)
```

这条流程保留构建目录和用户数据。应用包已包含运行所需的 framework；独立的 `build/modules` 用于增量编译，运行已安装应用时不需要它。

### 成套回滚构建输出

先退出 Compact。构建备份在 `build/.previous-app-*`，每个可用备份应包含同一次构建的 `Stats Compact.app` 和 `modules`。先列出目录，并选择你要恢复的**确切目录**，不要仅凭“最新目录”自动选择：

```sh
ls -d build/.previous-app-*
```

将下方 `compact_restore` 的占位目录换成实际路径。命令会确认备份成套、预检备份 app，保存当前输出，再一起恢复 app 和 modules：

```sh
(
    set -eu
    compact_restore="build/.previous-app-替换为实际目录名"
    test -d "$compact_restore/Stats Compact.app"
    test -d "$compact_restore/modules"
    python3 check-local-app.py "$compact_restore/Stats Compact.app"
    compact_current=$(mktemp -d "build/.before-rollback.XXXXXX")
    if [ -e "build/Stats Compact.app" ]; then
        mv "build/Stats Compact.app" "$compact_current/Stats Compact.app"
    fi
    if [ -e "build/modules" ]; then
        mv "build/modules" "$compact_current/modules"
    fi
    ditto "$compact_restore/Stats Compact.app" "build/Stats Compact.app"
    ditto "$compact_restore/modules" "build/modules"
    python3 check-local-app.py "build/Stats Compact.app"
    printf '回滚前输出保存在：%s\n' "$compact_current"
)
```

首次构建产生的备份可能没有上一版 app 和 modules，不能用于上述成套恢复。不要混用不同备份中的 app 与 modules。恢复成功后，再执行“安装独立应用”的整包替换命令；它仍会预检 `~/Applications/Stats Compact.app`，通过后才启动。仅恢复 `build` 目录不会改变已安装版本。

## 偏好与历史数据

Compact 使用独立的偏好与数据路径：

- 偏好：`~/Library/Preferences/eu.exelban.Stats.Compact.plist`
- 历史数据库：`~/Library/Application Support/Stats Compact/history-v1/history.sqlite`

首次启动会从官方 Stats 复制指定模块前缀的偏好，再设置 Compact 的布局默认值；官方版的登录设置、登录项、更新设置和认证信息不迁移。此后两者使用各自的偏好与数据目录。

构建和复制 app 不会注册登录项。如需登录时启动，应先完成最终路径的安装，再从 Compact 设置中手动开启。macOS 登录项不会自动运行本指南的 Python 预检；上面的 `预检 && open` 命令覆盖手动启动。

正常更新或回滚 app 与 modules 不会重置上述数据。`build/.previous-app-*` 和安装 app 的备份均不包含用户数据；如需额外备份，先退出 Compact，再保存整个 `~/Library/Application Support/Stats Compact` 目录及偏好 plist。完整支持目录包含 SQLite 的相关文件和缓存，不要只复制 `history.sqlite`。

## 人工验收

预检允许启动后，检查实际安装版本：

- 菜单栏各模块是可独立配置的项目，CPU、GPU 的图表设置分别生效。
- CPU 弹窗在频率数据出现、反复打开、调整进程数量或区块顺序后没有重叠或裁切。
- 弹窗底栏工具槽能保存配置，点击后打开所配置的应用。
- 日历能快速滚动并继续惯性滑动；惯性未结束时反向滚动，日期连续，固定的星期栏与底栏位置正常。
- 日历的“今天”按钮能回到当前日期，今天标记正常；原有偏好和历史数据仍可读取。

模型、布局和日历脚本的验证范围见 [FORK.md](FORK.md)，性能数据及触控板验收的边界见 [PERFORMANCE.md](PERFORMANCE.md)。自动化的滚动增量回放不能代替目标 Mac 上的真实触控板验收。

## 出现“已损坏”或预检失败

停止反复双击或重试启动。保留预检错误和 `build/*.log`，核对官方资源版本，并检查或重新构建完整应用包。如果旧输出使用了错误版本的资源，先成套保存其 app 和 modules，再以正确的官方资源从空输出构建。构建输出预检通过后，按“安装独立应用”步骤将旧安装整包备份、复制到空路径，再预检实际安装路径。不要关闭 Gatekeeper 或移除隔离属性来绕过检查。

只有该实际路径的检查通过，才使用 `python3 check-local-app.py "目标路径" && open "目标路径"` 启动；仍未通过时先解决错误，保留备份。
