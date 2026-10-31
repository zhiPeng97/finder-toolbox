// MenuDiagnostics — 无 GUI 诊断/测试入口（menucheck）
//   menucheck list --kind container|items [--paths p…]   → TSV: group|id|title|enabled
//   menucheck ids                                        → 每行一个 action id
//   menucheck encode --action <id> [--paths p…]           → URL
//   menucheck decode <url>                                → 解码结果
//   menucheck version

import Foundation

func argument(_ args: [String], _ name: String) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func argumentList(_ args: [String], _ name: String) -> [String] {
    guard let start = args.firstIndex(of: name) else { return [] }
    var values: [String] = []
    var index = start + 1
    while index < args.count, !args[index].hasPrefix("--") {
        values.append(args[index])
        index += 1
    }
    return values
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

@main
struct MenuCheck {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else { fail("usage: menucheck list|ids|encode|decode|version") }

        let bundleURL = Bundle.main.bundleURL
        let bundled = bundleURL.appendingPathComponent("Contents/Resources/menu.json")
        let menuURL = FileManager.default.fileExists(atPath: bundled.path)
            ? bundled
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ui/menu.json")

        switch args[1] {
        case "version":
            print("1.2.0")

        case "ids":
            guard let model = MenuModel.load(from: menuURL) else { fail("cannot load menu.json at \(menuURL.path)") }
            for id in model.allActionIDs { print(id) }

        case "list":
            guard let model = MenuModel.load(from: menuURL) else { fail("cannot load menu.json at \(menuURL.path)") }
            let kind = argument(args, "--kind") ?? "items"
            let isContainer = (kind == "container")
            let paths = argumentList(args, "--paths")
            let hasZip = MenuModel.containsZip(paths)
            // --xcode 0|1 用于测试覆盖；不传则按本机实际情况探测
            let xcode = argument(args, "--xcode").map { $0 == "1" } ?? MenuModel.xcodeInstalled()
            for group in model.groups {
                for item in group.items {
                    let enabled = MenuModel.isEnabled(actionID: item.id, isContainer: isContainer,
                                                      hasZip: hasZip, xcodeAvailable: xcode)
                    print([group.key, item.id, item.title, enabled ? "1" : "0"].joined(separator: "|"))
                }
            }

        case "encode":
            guard let action = argument(args, "--action") else { fail("missing --action") }
            let request = ActionRequest(action: action, paths: argumentList(args, "--paths"))
            guard let url = request.url else { fail("encode failed") }
            print(url.absoluteString)

        case "decode":
            guard args.count >= 3, let url = URL(string: args[2]) else { fail("missing url") }
            guard let request = ActionRequest(url: url) else { fail("decode failed") }
            print("action=\(request.action)")
            for path in request.paths { print("path=\(path)") }

        default:
            fail("unknown command: \(args[1])")
        }
    }
}
