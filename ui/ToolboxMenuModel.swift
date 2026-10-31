// ToolboxMenuModel — 菜单树与请求载荷的唯一 Swift 侧模型
// 被扩展（渲染菜单）、宿主（解析 URL）、menucheck（无 GUI 测试）三处共用。

import Foundation

// MARK: - 菜单树

struct MenuModel: Decodable {
    struct Item: Decodable {
        let id: String
        let title: String
        let symbol: String
    }

    struct Group: Decodable {
        let key: String
        let title: String
        let symbol: String
        let items: [Item]
    }

    let version: Int
    let groups: [Group]

    static func load(from url: URL) -> MenuModel? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MenuModel.self, from: data)
    }

    /// 上下文相关的启用规则：
    /// - 空白处：只放行「新建文件」、终端（当前位置）与「切换隐藏文件」
    /// - 选中项：全部可用，但「解压 ZIP」要求选中 .zip、「用 Xcode 打开」要求已装 Xcode
    static func isEnabled(actionID: String, isContainer: Bool, hasZip: Bool, xcodeAvailable: Bool = true) -> Bool {
        if isContainer {
            if actionID.hasPrefix("new:") { return true }
            if actionID == "fs:toggle" { return true }
            return actionID == "dev:terminal"
        }
        if actionID == "fs:unzip" { return hasZip }
        if actionID == "dev:xcode" { return xcodeAvailable }
        return true
    }

    /// Xcode 是否可用（扩展沙盒内只做路径探测，不触发 TCC）
    static func xcodeInstalled() -> Bool {
        let candidates = [
            "/Applications/Xcode.app",
            "/Applications/Xcode-beta.app"
        ]
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    static func containsZip(_ paths: [String]) -> Bool {
        paths.contains { $0.lowercased().hasSuffix(".zip") }
    }

    var allActionIDs: [String] {
        groups.flatMap { $0.items.map(\.id) }
    }
}

// MARK: - 请求载荷（扩展 → 宿主）

struct ActionRequest: Codable {
    var v: Int = 1
    var action: String
    var paths: [String]
    var ts: Double

    init(action: String, paths: [String], ts: Double = Date().timeIntervalSince1970) {
        self.action = action
        self.paths = paths
        self.ts = ts
    }

    static let scheme = "findertoolbox"

    /// base64url(JSON) 走 query，彻底绕开空格/中文/换行/#?&% 的转义问题
    var url: URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = ActionRequest.scheme
        components.host = "run"
        components.queryItems = [URLQueryItem(name: "d", value: encoded)]
        return components.url
    }

    init?(url: URL) {
        guard url.scheme == ActionRequest.scheme, url.host == "run",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "d" })?.value
        else { return nil }

        var base64 = raw.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let decoded = try? JSONDecoder().decode(ActionRequest.self, from: data)
        else { return nil }
        self = decoded
    }

    /// 拒绝过期请求，避免宿主重启后补投历史动作
    func isFresh(maxAge: TimeInterval = 60) -> Bool {
        abs(Date().timeIntervalSince1970 - ts) <= maxAge
    }
}
