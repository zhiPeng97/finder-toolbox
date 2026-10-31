// ToolboxFinderExtension — 访达右键菜单（顶级三项 + 二级动作）
// 职责仅限：构造菜单、判断启用态、把动作请求交给宿主 App。
// 所有真实操作在 shell 侧（bin/toolbox action …）执行。

import Cocoa
import FinderSync
import os

@objc(ToolboxFinderExtension)
final class ToolboxFinderExtension: FIFinderSync {
    private let logger = Logger(subsystem: "com.adam.findertoolbox", category: "extension")
    private var model: MenuModel?
    private var tagToAction: [Int: String] = [:]
    private var contextPaths: [String] = []
    private var contextIsContainer = false

    override init() {
        super.init()
        model = loadModel()
        updateDirectoryURLs()
        observeVolumes()
        log("INIT groups=\(model?.groups.count ?? -1)")
    }

    // MARK: - 监控范围

    private func updateDirectoryURLs() {
        var urls: Set<URL> = [URL(fileURLWithPath: "/", isDirectory: true)]
        let options: FileManager.VolumeEnumerationOptions = [.skipHiddenVolumes]
        if let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: options) {
            urls.formUnion(volumes)
        }
        FIFinderSyncController.default().directoryURLs = urls
    }

    private func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.addObserver(self, selector: #selector(volumesChanged), name: name, object: nil)
        }
    }

    @objc private func volumesChanged(_ note: Notification) {
        updateDirectoryURLs()
    }

    // MARK: - 菜单

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let isContainer = (menuKind == .contextualMenuForContainer)
        contextIsContainer = isContainer

        let urls: [URL]
        if isContainer {
            // 空白处右键：系统给的是当前文件夹本身
            if let target = controller.targetedURL() {
                urls = [target]
            } else {
                urls = controller.selectedItemURLs() ?? []
            }
        } else {
            urls = controller.selectedItemURLs() ?? []
        }
        contextPaths = urls.map(\.path)

        guard let model = model ?? loadModel() else {
            log("MENU abort: no menu.json")
            return NSMenu(title: "")
        }

        let hasZip = MenuModel.containsZip(contextPaths)
        let xcode = MenuModel.xcodeInstalled()
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        tagToAction.removeAll()

        var nextTag = 1
        for group in model.groups {
            let parent = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            parent.image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: nil)
            parent.isEnabled = true

            let submenu = NSMenu(title: group.title)
            submenu.autoenablesItems = false

            for item in group.items {
                let action = NSMenuItem(title: title(for: item, isContainer: isContainer),
                                        action: #selector(handleMenuClick(_:)), keyEquivalent: "")
                action.target = self
                action.tag = nextTag
                action.isEnabled = MenuModel.isEnabled(actionID: item.id, isContainer: isContainer, hasZip: hasZip, xcodeAvailable: xcode)
                action.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
                tagToAction[nextTag] = item.id
                nextTag += 1
                submenu.addItem(action)
            }

            parent.submenu = submenu
            menu.addItem(parent)
        }

        log("MENU container=\(isContainer) paths=\(contextPaths.count)")
        return menu
    }

    /// 隐藏文件开关的标题跟随真实状态（状态由 CLI 写入扩展容器）
    private func title(for item: MenuModel.Item, isContainer: Bool) -> String {
        guard item.id == "fs:toggle" else { return item.title }
        return hiddenFilesShown() ? "隐藏隐藏文件" : "显示隐藏文件"
    }

    private func hiddenFilesShown() -> Bool {
        let path = NSHomeDirectory() + "/Library/Application Support/FinderToolbox/hidden-state"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    // MARK: - 点击

    @objc private func handleMenuClick(_ sender: NSMenuItem) {
        guard let actionID = tagToAction[sender.tag] else {
            log("HIT unknown tag \(sender.tag)")
            return
        }
        let request = ActionRequest(action: actionID, paths: contextPaths)
        guard let url = request.url else {
            log("HIT encode failed \(actionID)")
            return
        }
        log("HIT \(actionID) paths=\(contextPaths.count)")
        NSWorkspace.shared.open(url)
    }

    private func loadModel() -> MenuModel? {
        guard let url = Bundle.main.url(forResource: "menu", withExtension: "json") else { return nil }
        return MenuModel.load(from: url)
    }

    private func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
