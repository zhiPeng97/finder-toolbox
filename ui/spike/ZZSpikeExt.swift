// ZZSpikeExt — 一次性探针：验证访达扩展能否把菜单项插到右键菜单顶层
// 判据见 tools/spike.sh 输出与文档；验证完即卸载。

import Cocoa
import FinderSync
import os

@objc(ZZSpikeExtension)
final class ZZSpikeExtension: FIFinderSync {
    private let logger = Logger(subsystem: "com.adam.findertoolbox.spike", category: "ext")

    // 沙箱内 NSHomeDirectory() 指向容器，日志落在这里，外面可读
    private var logURL: URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("spike.log")
    }

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        write("INIT dirs=\(FIFinderSyncController.default().directoryURLs.count)")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let c = FIFinderSyncController.default()
        let kind = (menuKind == .contextualMenuForContainer) ? "container" : "items"
        let target = c.targetedURL()?.path ?? "-"
        let sel = (c.selectedItemURLs() ?? []).map(\.path).joined(separator: " | ")
        write("MENU kind=\(kind) target=\(target) sel=[\(sel)]")

        let menu = NSMenu(title: "")
        menu.autoenablesItems = false

        // 注意：representedObject 过不了 Finder 的跨进程菜单拷贝（实测 HIT ?），改用 tag
        let top = ["ZZSpike 顶层一", "ZZSpike 顶层二"]
        for (idx, title) in top.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(hit(_:)), keyEquivalent: "")
            item.target = self
            item.tag = 101 + idx
            item.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: nil)
            menu.addItem(item)
        }

        // 嵌套项：用于确认 Finder 是否会把子菜单也放在顶层
        let parent = NSMenuItem(title: "ZZSpike 父项", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "sub")
        sub.autoenablesItems = false
        let child = NSMenuItem(title: "ZZSpike 子项", action: #selector(hit(_:)), keyEquivalent: "")
        child.target = self
        child.tag = 201
        sub.addItem(child)
        parent.submenu = sub
        menu.addItem(parent)

        return menu
    }

    private func titleForTag(_ tag: Int) -> String {
        switch tag {
        case 101: return "顶层一"
        case 102: return "顶层二"
        case 201: return "子项"
        default: return "未知(\(tag))"
        }
    }

    @objc private func hit(_ sender: NSMenuItem) {
        write("HIT tag=\(sender.tag) name=\(titleForTag(sender.tag)) title=\(sender.title)")

        // A6：沙盒内能否起子进程、能否写到容器外
        spawn("/bin/echo ok > \"\(NSHomeDirectory())/Documents/spawn-inside.txt\"", label: "容器内写入")
        let realHome = realUserHome()
        spawn("/bin/echo ok > \"\(realHome)/Library/Logs/zzspike-outside.txt\"", label: "容器外写入")
    }

    private func spawn(_ cmd: String, label: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            write("spawn[\(label)] rc=\(p.terminationStatus)")
        } catch {
            write("spawn[\(label)] FAIL \(error)")
        }
    }

    /// 沙箱里 NSHomeDirectory 是容器路径；用 passwd 拿真实家目录
    private func realUserHome() -> String {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return "/Users" }
        return String(cString: dir)
    }

    private func write(_ line: String) {
        logger.notice("\(line, privacy: .public)")
        let text = "\(Date()) \(line)\n"
        if let data = text.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
