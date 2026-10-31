#!/bin/bash
# config.example.sh — 安装后复制为 ~/Library/Application Support/FinderToolbox/config.sh 后按需修改
# 所有配置项都有默认值，只改需要改的。
#
# 注意：v1.1 起「在终端中打开」已移除，终端由系统服务「新建位于文件夹的终端窗口」提供。

# VS Code 应用与 CLI 路径（默认自动探测 /Applications/Visual Studio Code.app）
# FT_VSCODE_APP="/Applications/Visual Studio Code.app"
# FT_VSCODE_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"

# HBuilderX 应用路径
# FT_HBUILDERX_APP="/Applications/HBuilderX.app"

# Xcode 应用路径（默认自动探测 /Applications/Xcode.app 与 Xcode-beta）
# FT_XCODE_APP="/Applications/Xcode.app"

# 新建文件的默认文件名（不含扩展名）
# FT_NEW_FILE_BASENAME="未命名"

# 菜单最多保持打开的秒数；超时自动关闭
# FT_MENU_TIMEOUT=300

# 等待菜单弹出的秒数，超时自动降级为对话框
# FT_MENU_START_TIMEOUT=5

# 无选区时是否向 Finder 询问当前文件夹（首次会触发一次自动化授权）
# FT_USE_INSERTION_LOCATION=1

# 切换隐藏文件后是否重启 Finder：relaunch | prefonly
# FT_TOGGLE_METHOD="relaunch"

# 复制路径时是否给文件夹补尾斜杠：0 | 1
# FT_COPY_TRAILING_SLASH=0

# 是否发送成功提示（通知中心）：0 | 1
# FT_NOTIFY=1

# 安装时是否关闭系统「新建位于文件夹位置的终端标签页」（终窗口版保留）：0 | 1
# FT_DISABLE_TERMINAL_TAB_SERVICE=1

# 调试：强制使用对话框菜单（1 = 强制降级）
# FT_FORCE_FALLBACK=0
