// ToolboxMenu — Finder 右键工具箱的原生级联菜单渲染器
//
// 设计约束：本程序只负责「显示菜单 + 回传所选动作 id」，不含任何业务逻辑。
// 菜单结构与动作实现全部在 shell 侧（lib/menu.sh、lib/dispatch.sh）。
//
// 退出码：0 已选（写入 result 文件） / 2 用户取消 / 3 规格异常 / 4 内部异常 / 5 分组不存在或为空

import AppKit

// MARK: - 规格模型

struct ActionSpec {
    let id: String
    let title: String
    let symbol: String
    let enabled: Bool
}

struct GroupSpec {
    let key: String
    let title: String
    let symbol: String
    var actions: [ActionSpec]
}

func parseSpec(_ text: String) -> (header: String?, groups: [GroupSpec]) {
    var header: String?
    var groups: [GroupSpec] = []

    for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
        let line = String(rawLine)
        if line.isEmpty { continue }
        let parts = line.components(separatedBy: "|")
        switch parts[0] {
        case "H":
            if parts.count >= 2, !parts[1].isEmpty { header = parts[1] }
        case "G":
            if parts.count >= 4 {
                groups.append(GroupSpec(key: parts[1], title: parts[2], symbol: parts[3], actions: []))
            }
        case "I":
            if parts.count >= 5, !groups.isEmpty {
                let enabled = parts.count >= 6 ? parts[5] == "1" : true
                groups[groups.count - 1].actions.append(
                    ActionSpec(id: parts[2], title: parts[3], symbol: parts[4], enabled: enabled)
                )
            }
        default:
            continue
        }
    }
    return (header, groups.filter { !$0.actions.isEmpty })
}

// MARK: - 菜单构建

final class MenuTarget: NSObject {
    var chosen: String?

    @objc func pick(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String {
            chosen = id
        }
    }
}

func symbolImage(_ name: String) -> NSImage? {
    guard !name.isEmpty else { return nil }
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)
}

func buildMenu(header: String?, groups: [GroupSpec], target: MenuTarget) -> NSMenu {
    let menu = NSMenu(title: "开发者工具箱")
    // 关键：关闭自动启用，否则未接入响应链的菜单项会全部变灰
    menu.autoenablesItems = false

    if let header = header, !header.isEmpty {
        let titleItem = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())
    }

    for group in groups {
        let parent = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
        parent.image = symbolImage(group.symbol)

        let submenu = NSMenu(title: group.title)
        submenu.autoenablesItems = false
        for action in group.actions {
            let item = NSMenuItem(title: action.title, action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = action.id
            item.isEnabled = action.enabled
            item.image = symbolImage(action.symbol)
            submenu.addItem(item)
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }
    return menu
}

/// 单组模式：把该组动作直接铺在一级菜单（三个入口各自只显示自己那一组）
func buildFlatMenu(header: String?, group: GroupSpec, target: MenuTarget) -> NSMenu {
    let menu = NSMenu(title: group.title)
    menu.autoenablesItems = false

    if let header = header, !header.isEmpty {
        let titleItem = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())
    }

    for action in group.actions {
        let item = NSMenuItem(title: action.title, action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = action.id
        item.isEnabled = action.enabled
        item.image = symbolImage(action.symbol)
        menu.addItem(item)
    }
    return menu
}

/// 鼠标点可能落在任何屏幕；若不在任何屏幕内，退到主屏右上角附近
func clampedPoint(_ point: NSPoint) -> NSPoint {
    for screen in NSScreen.screens where screen.frame.contains(point) {
        return point
    }
    guard let reference = NSScreen.main ?? NSScreen.screens.first else { return point }
    let visible = reference.visibleFrame
    return NSPoint(x: visible.maxX - 24, y: visible.maxY - 24)
}

// MARK: - 应用

final class AppDelegate: NSObject, NSApplicationDelegate {
    let specPath: String
    let resultPath: String
    let shownPath: String
    let groupKey: String?
    private let target = MenuTarget()

    init(specPath: String, resultPath: String, shownPath: String, groupKey: String?) {
        self.specPath = specPath
        self.resultPath = resultPath
        self.shownPath = shownPath
        self.groupKey = groupKey
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let text = try? String(contentsOfFile: specPath, encoding: .utf8) else {
            FileHandle.standardError.write(Data("cannot read spec: \(specPath)\n".utf8))
            exit(3)
        }

        let (header, groups) = parseSpec(text)
        var menu: NSMenu

        if let key = groupKey, !key.isEmpty {
            guard let group = groups.first(where: { $0.key == key }), !group.actions.isEmpty else {
                FileHandle.standardError.write(Data("group not found or empty: \(key)\n".utf8))
                exit(5)
            }
            menu = buildFlatMenu(header: header, group: group, target: target)
        } else {
            guard !groups.isEmpty else {
                FileHandle.standardError.write(Data("empty spec\n".utf8))
                exit(3)
            }
            menu = buildMenu(header: header, groups: groups, target: target)
        }

        // 主动激活：菜单需要在前台才能可靠接收键盘与鼠标跟踪
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])

        // 告诉调用方「菜单已就绪」，用于区分崩溃与用户取消
        try? "1".write(toFile: shownPath, atomically: true, encoding: .utf8)

        DispatchQueue.main.async {
            let point = clampedPoint(NSEvent.mouseLocation)
            menu.popUp(positioning: nil, at: point, in: nil)

            if let chosen = self.target.chosen, !chosen.isEmpty {
                try? chosen.write(toFile: self.resultPath, atomically: true, encoding: .utf8)
                exit(0)
            }
            exit(2)
        }
    }
}

// MARK: - 入口

func argumentValue(_ args: [String], _ name: String) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: ToolboxMenu menu|version\n".utf8))
    exit(64)
}

if arguments[1] == "version" {
    print("1.1.0")
    exit(0)
}

guard arguments[1] == "menu",
      let specPath = argumentValue(arguments, "--spec"),
      let resultPath = argumentValue(arguments, "--result"),
      let shownPath = argumentValue(arguments, "--shown") else {
    FileHandle.standardError.write(Data("usage: ToolboxMenu menu --spec <path> --result <path> --shown <path> [--group <key>]\n".utf8))
    exit(64)
}

let groupKey = argumentValue(arguments, "--group")

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate(specPath: specPath, resultPath: resultPath, shownPath: shownPath, groupKey: groupKey)
application.delegate = delegate
application.run()
