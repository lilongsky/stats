# UI validation coverage

Review date: 2026-10-23. This record distinguishes live inspection of the running
app from isolated AppKit checks. A **Popup settings tab** and an **actual
menu-bar popup** are separate surfaces. Live inspection uses Simplified Chinese
with light appearance; other languages, appearances and widths are covered only
where the relevant offscreen runner states so.

The currently available main UI has been reviewed within the limits below. The
rebuilt app passed live rechecks of the GPU, Battery and Clock fixes. Opening a
page establishes coverage only for its visible controls and current data state.
Apple Human Interface Guidelines informed the design; this record is not Apple
certification or a claim about every macOS release.

## Module coverage

| Module | Settings pages inspected live | Actual menu-bar popup | Result / limits |
| --- | --- | --- | --- |
| CPU | Module, Widgets, Popup, Notifications | Complete top/bottom inspection | Current displayed state covered |
| GPU | Module, Widgets, Popup, Notifications | All three circles update with clear percentage text | Post-fix live check passed |
| RAM | Module, Widgets, Popup, Notifications | Inspected | Disabled Swap threshold layout inspected live; enabled state checked offscreen |
| Disk | Module, Widgets, Popup, Notifications | Inspected | Current displayed state covered |
| Net | Module, Widgets, Popup, Notifications | Complete top/bottom inspection | Disabled unit-threshold layout inspected live; enabled state checked offscreen |
| Sensors | Module, Popup, Notifications; Widgets empty state | Current temperature list inspected | No active widget in Widgets; physical fan controls not exercised |
| Battery | Module, Widgets, Popup, Notifications | Top/bottom, adapter, health and details inspected; footer remains fixed | Post-fix live check passed; sections do not overlap |
| Bluetooth | Module, Widgets, Popup, Notifications | Disabled/no-device state inspected | Connected-device rows and live battery readings not covered |
| Clock | Module, Widgets, Popup; no Notifications tab | Current calendar popup inspected; Today and month/year selectors visible | Post-fix Module check passed at 760 × 540: all five columns and both enabled checkboxes visible, compact rows; Widgets and Popup settings top/bottom reviewed |
| Remote | Widget selector and unauthenticated introduction | Not verified in this review | No four-tab settings layout; authenticated Machines/Hosts lists and remote popup not covered |

The four GPU/RAM/Disk/Net settings pages were also reviewed in the preceding
layout pass, including the tops and bottoms of long Widgets and Popup pages.
Scrolling over the GPU popup-section list moved the outer settings page, and
reversing restored its initial position. That is live displacement evidence;
the offscreen scroll runner establishes responder routing separately.

## Other surfaces and interactions

| Surface | Live coverage | Boundary |
| --- | --- | --- |
| Dashboard | Top and bottom at 760 × 540; full-width groups, horizontal labels and wrapping values | Offscreen tests use synthetic device data |
| General | Complete top/bottom inspection | Current visible preference state |
| General import/export | Native open/save panels opened and cancelled | No settings imported or overwritten |
| Reset settings | Confirmation displayed; No selected | Reset and restart not performed |
| More menu | Native menu items inspected | External destinations not opened; no issue or PR submitted |
| History | 1-hour → 24-hour range, CPU → user CPU, peak on → off; native CSV save panel opened and cancelled | No file exported during this review; earlier CSV model/export checks are separate |
| Footer tools | Native Choose Application panel opened and cancelled; tool 1 remained Activity Monitor. Earlier checks covered replacement, hiding and restoring presets | No custom application selected or preference changed during this review |
| Standard window interactions | Command-comma, Command-W, Command-Q and preview state after reopening previously checked | No claim about all keyboard-navigation paths |
| Clock calendar | Current popup inspected with Today and month/year selectors visible; native selection, Escape and Today previously exercised | The user previously confirmed smooth trackpad motion; see [performance scope](../PERFORMANCE.md) |

## Isolated checks

| Check group | Result | Scope |
| --- | --- | --- |
| Existing regression group | Previous 6,742 assertions passed; not rerun in this final pass because Kit did not change | Settings 1,769 per language; Dashboard 1,381 per language; popup scroll 26; CPU popup 96; calendar 320 |
| Clock settings | 211 assertions passed | Actual Clock settings in Chinese, synthetic lists, multiple widths, light/dark appearance, table-column geometry and existing callbacks |
| GPU percentage transitions | 35 checks passed | One-time probe of the actual GPU popup: four synthetic readings and cache replay; default 250 ms fade confirmed, corrected charts have no transition |
| Battery popup | 251 assertions passed in Chinese and 251 in English (502 total) | Actual popup layout regression in isolated light/dark views; rebuilt-app live verification also passed |

The reusable-settings runner compiles the real Sensors settings, popup and
notification views as well as common production controls. It does not
instantiate every module's complete settings window. Dashboard checks use
synthetic formatted device values; they do not query the real serial number.
Temporary helpers use separate preference identities and execution preflight.
See [FORK.md](../FORK.md#validation) for commands and detailed runner scope.

Uncovered states include authenticated Remote operation, connected Bluetooth
devices, physical fan actuation and OS notification delivery. Enabled threshold
states are checked in isolated views without enabling alerts in the user's
configuration. First-launch setup and update/install flows are outside this UI
review. Private screenshots, local paths and telemetry are not published here.

## 中文

本记录区分设置里的“弹出窗口”页和菜单栏点击后出现的真实弹窗。实机检查使用
简体中文、浅色外观；其他语言、浅深色与多档宽度的覆盖以各离屏测试的实际范围
为准。当前可用的主要 UI 已按下列边界补查，三项修复均通过新应用实机复测。
Apple 人机界面指南提供设计参考，不代表 Apple 认证或所有 macOS 版本均已验收。

| 模块 | 已实机检查的设置页与弹窗 | 当前边界 |
| --- | --- | --- |
| CPU | 四个设置页；真实弹窗完整上下端 | 当前显示状态已检查 |
| GPU | 四个设置页；真实弹窗三个圆环更新数字清晰 | 修复后实机通过 |
| 内存 | 四个设置页；真实弹窗 | Swap 关闭状态实机检查，开启状态离屏检查 |
| 磁盘 | 四个设置页；真实弹窗 | 当前显示状态已检查 |
| 网络 | 四个设置页；真实弹窗完整上下端 | 带单位阈值关闭状态实机检查，开启状态离屏检查 |
| 传感器 | 模块、弹出窗口、通知；小组件空状态；真实温度列表弹窗 | 当前无启用的小组件；未操作物理风扇 |
| 电池 | 四个设置页；真实弹窗顶部、底部、适配器、健康、详情及固定底栏 | 修复后实机通过，各分区无重叠 |
| 蓝牙 | 四个设置页及真实弹窗的禁用/无设备状态 | 未覆盖已连接设备的行和电量更新 |
| 时钟 | 三个设置页，无通知页；小组件和弹出窗口页上下端正常；日历显示“今天”及年月选择器 | 修复后在 760 × 540 实机通过：五列、两条记录的启用复选框完整可见，行高已收紧；日历交互另有此前实机记录 |
| 远程 | 小组件选择器及未登录介绍页 | 没有四页签结构；未登录，不覆盖认证后列表或远程弹窗 |

仪表盘已在 760 × 540 窗口检查顶部、底部、满宽分组、标签横排和数值换行。
通用设置已检查完整上下端；导入、导出的原生文件面板均打开后取消，重置确认选择
“否”，“更多”菜单仅检查原生项目。历史窗口已切换 1 小时到 24 小时、CPU 到用户
CPU、关闭峰值，并打开后取消 CSV 保存面板。底栏“选择应用”的原生面板已展开并
取消，返回后快捷工具 1 仍为活动监视器，未修改配置；工具替换、隐藏和恢复默认有
此前实机记录。日历惯性滚动的手感此前已由用户确认顺畅。

原回归组 6,742 项断言仍有效，本轮因 Kit 未变而未重复运行。新增时钟设置中文多宽、
浅深色与回调检查 211 项，GPU 百分比切换专项 35 项，电池弹窗中英文浅深色各
251 项（合计 502 项）通过。上述三项修复后的新应用实机检查也已通过；这些数量
不能等同于所有状态下的全部 UI 验收。
通知送达、物理风扇执行、蓝牙连接设备、远程认证后状态、首次设置和更新安装流程
不在本轮覆盖内。截图、本机路径和遥测保留在公开仓库之外。
