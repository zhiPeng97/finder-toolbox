# Finder 工具箱（Finder Toolbox）V1.2

macOS 访达右键工具箱：**三个一级入口 + 二级动作**，选中文件、选中文件夹、窗口空白处都能用。
无后台常驻进程、无第三方文件管理器、无需 sudo。

```
右键（文件 / 文件夹 / 空白处）
├─ 新建文件 ▸ Markdown / 文本 / JSON / JavaScript / Vue / CSS / HTML
├─ 开发工具 ▸ 在当前位置打开终端 / 用 Xcode 打开 / VS Code / HBuilderX / 复制绝对路径
└─ 文件管理 ▸ 压缩为 ZIP / 解压 ZIP / 显示或隐藏隐藏文件 / 在 Finder 中定位
```

V1.2 相对 V1.1：从「服务」子菜单迁移到**访达扩展**——三个分类直接出现在右键菜单第一层，点开就是动作，全程两层；空白处右键同样可用。V1.1 的「服务」入口会在扩展启用后自动清除。

## 环境要求

| 项目 | 要求 |
|---|---|
| 系统 | macOS 13 及以上（已在 macOS 27.2 / Apple Silicon 验证） |
| 编译 | Xcode 或 Command Line Tools（`swiftc`） |
| 权限 | 可写 `~/Applications`，**不需要 sudo** |

扩展使用 ad-hoc 签名，仅本机自用；不做公证、不面向分发。

## 安装

```bash
cd finder-toolbox
./install.sh
```

安装脚本：预检 → 构建宿主 App 与扩展 → 部署运行时 → 安装到 `~/Applications/FinderToolbox.app` → 注册扩展 → 判定是否启用 → 清理重复入口。

**启用扩展需要一次手动勾选**（系统限制，无法脚本化）：

> 系统设置 → 通用 → 登录项与扩展 → 扩展 → 访达 → 勾选「Finder 工具箱」

启用后如仍看到旧的「服务」入口，执行一次 `./install.sh --finalize` 即可清理。

**文件落点**

| 内容 | 路径 |
|---|---|
| 宿主 App + 扩展 | `~/Applications/FinderToolbox.app`（扩展在 `Contents/PlugIns/ToolboxFinder.appex`） |
| 运行时 | `~/Library/Application Support/FinderToolbox/`（`bin` `lib` `templates` `config.sh`） |
| 日志 | `~/Library/Logs/FinderToolbox/toolbox.log` |

## 验证

```bash
# 扩展是否在运行
pgrep -fl ToolboxFinder.appex

# App 侧自报状态
"$HOME/Applications/FinderToolbox.app/Contents/MacOS/FinderToolbox" --status

# 运行时自检
"$HOME/Library/Application Support/FinderToolbox/bin/toolbox" selftest
```

然后在访达里：

1. 右键文件 → 应直接看到「新建文件 / 开发工具 / 文件管理」，无第二层包装；
2. 「新建文件 → Markdown (.md)」→ 生成 `未命名.md` 并自动选中；
3. 空白处右键 → 三个入口仍在；开发工具里只有「在当前位置打开终端」可用，其余为灰；
4. 空白处点「在当前位置打开终端」→ 终端在该文件夹打开。

## 菜单与行为

### 新建文件（7 种）

| 菜单项 | 生成内容 |
|---|---|
| Markdown (.md) | `# 未命名` |
| 文本文件 (.txt) | 空文件 |
| JSON 文件 (.json) | `{}` |
| JavaScript (.js) | `// 未命名` |
| Vue 组件 (.vue) | `<template>` + `<script setup>` + `<style scoped>` 骨架 |
| 样式表 (.css) | `/* 未命名 */` |
| HTML 页面 (.html) | HTML5 骨架（`lang="zh-CN"`、UTF-8） |

命名固定 `未命名.<ext>`，重名自动递增（`未命名 2.md`），**绝不覆盖已有文件**；创建后立即在访达中定位并选中。选中文件夹 → 建在其内；选中文件 → 建在其父目录；空白处 → 建在当前文件夹。

### 开发工具

| 菜单项 | 行为 |
|---|---|
| 在当前位置打开终端 | 打开终端并 `cd` 到目标目录；多选时按去重后的目录开窗；可配置成 iTerm |
| 用 Xcode 打开 | 走 Xcode 自带的 `xed`，退回 `open -a Xcode`；**未安装 Xcode 时该项自动置灰** |
| 用 VS Code 打开 | 走 `code` CLI；文件夹多选 → 多根工作区 |
| 用 HBuilderX 打开 | 逐项 `open -a HBuilderX` |
| 复制绝对路径 | 多选换行分隔批量写入剪贴板 |

空白处右键时，只有「在当前位置打开终端」可用（其余需要选中对象）。找不到 VS Code 命令行会弹出可操作的中文提示。

### 文件管理

| 菜单项 | 行为 |
|---|---|
| 压缩为 ZIP | 每个选中项各自生成独立 zip，输出到源目录，重名自动加序号；目录保留自身层级 |
| 解压 ZIP | 解压到同目录同名新文件夹；仅处理 `.zip`；加密/损坏包不挂起 |
| 显示/隐藏隐藏文件 | 切换 `AppleShowAllFiles` 并刷新访达，菜单标题跟随真实状态 |
| 在 Finder 中定位 | `open -R`；多选时同窗全选 |

## 配置

编辑 `~/Library/Application Support/FinderToolbox/config.sh`（首次安装生成，升级不覆盖）：

| 变量 | 默认 | 说明 |
|---|---|---|
| `FT_TERMINAL_APP` | 系统 Terminal | 改成 `/Applications/iTerm.app` 等 |
| `FT_XCODE_APP` | 自动探测 | Xcode 装在非标准位置时指定 |
| `FT_VSCODE_APP` / `FT_VSCODE_CLI` | 自动探测 | VS Code 非标准位置 |
| `FT_HBUILDERX_APP` | `/Applications/HBuilderX.app` | HBuilderX 路径 |
| `FT_NEW_FILE_BASENAME` | `未命名` | 新建文件主名 |
| `FT_TOGGLE_METHOD` | `relaunch` | `prefonly` 则只改偏好不重启访达 |

## 命令行用法

```bash
TB="$HOME/Library/Application Support/FinderToolbox/bin/toolbox"

"$TB" actions                     # 列出全部动作 id（与菜单同源校验）
"$TB" action new:md <目录>        # 直接执行动作
"$TB" action dev:terminal <目录>
"$TB" selftest                    # 环境 + 扩展状态自检
```

动作 id：`new:md|txt|json|js|vue|css|html`、`dev:terminal|vscode|hbuilderx|copy`、`fs:zip|unzip|toggle|reveal`。

## 卸载

```bash
./uninstall.sh                    # 移除扩展、宿主 App、运行时，还原系统设置
./uninstall.sh --purge-logs
./uninstall.sh --keep-hidden-pref
```

卸载顺序：停扩展进程 → `pluginkit -r` 注销 → 删 App → `lsregister -u` → 删容器 → 还原隐藏文件与服务开关 → 重启访达。漏掉注销会留下点击无效的悬空菜单项。

## 实现原理

```
访达右键
  → ToolboxFinder.appex（沙盒，监控所有卷）
      构造菜单：menu.json + 上下文启用规则
      点击 → base64url(JSON) → findertoolbox://run?d=…
  → FinderToolbox.app（宿主，LSUIElement，无 Dock）
      解析 URL → 执行 `toolbox action <id> <paths…>` → 立即退出
```

- **为什么需要宿主**：扩展沙盒内的子进程继承沙箱，写用户文件会被拒（实测容器内写入成功、容器外 `rc=1`）。宿主非沙盒，负责执行。
- **为什么用 URL 传参**：沙盒调用 `openApplication(arguments:)` 时参数会被系统丢弃；base64url 同时规避了路径中空格、中文、换行、`#?&%` 的转义问题。
- **为什么用 tag 而非 representedObject**：菜单跨进程拷贝后 `representedObject` 丢失（实测点击拿到 `?`），`tag` 能存活。
- **菜单项来源**：`ui/menu.json` 是唯一清单；`menucheck` 与扩展、CLI 共用同一份，测试里做 id 集合比对防漂移。
- 所有外部命令使用绝对路径，避免 PATH 中的同名 shim。

### 为什么是访达扩展，而不是「服务 / 快速操作」

macOS 的 Services（右键「服务」子菜单）与 Automator 快速操作，**位置由系统决定**：它们永远只能待在子菜单里，第三方无法把条目提升到右键菜单顶层，也无法在窗口空白处提供入口。改 Info.plist、换服务类型都做不到。

只有 FinderSync 扩展能把菜单项直接插入右键菜单第一层，并同时拿到两种上下文（选中项 / 空白处）。代价是扩展要签名、要手动启用、会随访达常驻——这也是本项目从 v1.1 的「服务」方案迁到 v1.2 扩展方案的原因。

### 与旧方案的关系

V1.1 的 3 个「服务」入口仍保留在仓库中（`services/`、`tools/build-services.sh`），作为扩展无法启用时的回退：`./install.sh` 检测到扩展未启用会自动安装它们，保证右键可用；扩展就绪后跑 `--finalize` 清理。

## 已知限制

- 扩展为 ad-hoc 签名，仅本机可用；更换机器需重新启用。
- 扩展加载后会随访达一起常驻（约十几 MB），这是 FinderSync 的固有形态。
- 监控范围是整个磁盘，`/Volumes` 下的外接卷单独补齐。
- 解压仅支持 `.zip`；含单一顶层目录的包会多一层（与系统归档工具一致）。
- 首次在 `~/Desktop`、`~/Documents` 操作时系统可能要求文件访问授权。

## 目录结构

```
finder-toolbox/
├── install.sh / uninstall.sh
├── bin/toolbox                    CLI（action / actions / selftest / version）
├── lib/                           common paths menu dispatch services extension act_*
├── ui/
│   ├── menu.json                  菜单唯一真源
│   ├── ToolboxMenuModel.swift     菜单模型 + URL payload 编解码
│   ├── ToolboxFinderExtension.swift  访达扩展
│   ├── ToolboxHost.swift          宿主 App
│   ├── MenuDiagnostics.swift      menucheck（无 GUI 测试）
│   ├── Info.{host,appex}.plist / entitlements.{host,appex}.plist
│   └── build.sh                   构建 + ad-hoc 签名 + 校验
├── services/ + tools/build-services.sh   回退用「服务」入口
├── templates/                     7 种文件模板
└── tests/run-tests.sh             102 项无 GUI 回归测试
```
