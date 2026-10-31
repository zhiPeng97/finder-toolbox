// ToolboxHost — 宿主 App：接收扩展的 URL 请求，执行 CLI，随后立即退出（不常驻）
// 也提供两个无 GUI 子命令：--status（扩展是否启用）、--open-settings（打开扩展设置）

import Cocoa
import FinderSync

@main
final class ToolboxHost: NSObject, NSApplicationDelegate {
    static func main() {
        let args = CommandLine.arguments

        if args.contains("--status") {
            exit(reportStatus())
        }
        if args.contains("--open-settings") {
            FIFinderSyncController.showExtensionManagementInterface()
            exit(0)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = ToolboxHost()
        app.delegate = delegate

        if let index = args.firstIndex(of: "--run"), index + 1 < args.count,
           let url = URL(string: args[index + 1]) {
            delegate.pending = [url]
        }

        app.run()
    }

    private var pending: [URL] = []

    // MARK: - 生命周期

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !pending.isEmpty {
            handle(pending)
            pending = []
            return
        }
        // 正常由 URL 唤起；10 秒内没收到请求就退出，绝不常驻
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { exit(0) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handle(urls)
    }

    // MARK: - 执行

    private func handle(_ urls: [URL]) {
        restoreFinderFocus()
        for url in urls {
            guard let request = ActionRequest(url: url), request.isFresh() else { continue }
            run(request)
        }
        exit(0)
    }

    private func run(_ request: ActionRequest) {
        let home = realUserHome()
        let cli = home + "/Library/Application Support/FinderToolbox/bin/toolbox"
        guard FileManager.default.isExecutableFile(atPath: cli) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["action", request.action] + request.paths
        process.environment = [
            "HOME": home,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "FT_FROM_EXTENSION": "1"
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("FinderToolbox: run failed \(error)")
        }
    }

    private func restoreFinderFocus() {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first?.activate(options: [])
    }

    /// 宿主不沙盒，但 `NSHomeDirectory()` 在从 Finder 唤起时仍可能是真实家目录；
    /// 为稳妥起见用 passwd 兜底。
    private func realUserHome() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    // MARK: - 状态

    private static func reportStatus() -> Int32 {
        let bundle = Bundle.main.bundleURL
        let appex = bundle.appendingPathComponent("Contents/PlugIns/ToolboxFinder.appex")
        let enabled = FIFinderSyncController.isExtensionEnabled
        // isExtensionEnabled 在「直接执行二进制」的场景下可能返回 false，
        // 因此把「扩展进程已在运行」也视为已启用。
        let running = !NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.adam.findertoolbox.finder").isEmpty
        print("app=\(bundle.path)")
        print("appex=\(FileManager.default.fileExists(atPath: appex.path) ? "present" : "missing")")
        print("enabled=\(enabled ? 1 : 0)")
        print("running=\(running ? 1 : 0)")
        return (enabled || running) ? 0 : 1
    }
}
