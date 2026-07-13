import Foundation
import Combine

struct GlobalSettings: Codable {
    var excludedBundleIDs: [String] = []
}

final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published var mappings: [KeyMapping] {
        didSet { save() }
    }

    @Published var globalSettings: GlobalSettings {
        didSet { saveSettings() }
    }

    private let storePath: URL
    private let settingsPath: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Keybot")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storePath = dir.appendingPathComponent("config.json")
        settingsPath = dir.appendingPathComponent("settings.json")

        let loaded = Self.load(from: storePath) ?? Self.defaultMappings()
        mappings = loaded
        globalSettings = Self.loadSettings(from: settingsPath) ?? GlobalSettings()

        if !FileManager.default.fileExists(atPath: storePath.path) {
            if let data = try? JSONEncoder().encode(loaded) {
                try? data.write(to: storePath, options: .atomic)
            }
        }
    }

    var enabledMappings: [KeyMapping] {
        mappings.filter(\.enabled)
    }

    func isGloballyExcluded(_ bundleID: String) -> Bool {
        globalSettings.excludedBundleIDs.contains(bundleID)
    }

    private static func load(from url: URL) -> [KeyMapping]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([KeyMapping].self, from: data)
    }

    private static func loadSettings(from url: URL) -> GlobalSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GlobalSettings.self, from: data)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        // 不用 .atomic：atomic 写入是"写临时文件再 rename"，rename 会把 dotfiles 符号链接替换成普通文件，导致同步静默失效
        try? data.write(to: storePath)
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(globalSettings) else { return }
        try? data.write(to: settingsPath)
    }

    func resetToDefaults() {
        mappings = Self.defaultMappings()
    }

    static func defaultMappings() -> [KeyMapping] {
        let terminalIDs = ["com.apple.Terminal", "com.googlecode.iterm2"]

        let ctrlToCmd: [(String, Int)] = [
            ("Ctrl+C → Cmd+C", 8),
            ("Ctrl+V → Cmd+V", 9),
            ("Ctrl+X → Cmd+X", 7),
            ("Ctrl+Z → Cmd+Z", 6),
            ("Ctrl+A → Cmd+A", 0),
            ("Ctrl+S → Cmd+S", 1),
            ("Ctrl+F → Cmd+F", 3),
            ("Ctrl+P → Cmd+P", 35),
        ]

        var result = ctrlToCmd.map { name, kc in
            KeyMapping(
                name: name,
                trigger: KeyTrigger(keyCode: kc, modifiers: [.control]),
                action: .remap(keyCode: kc, modifiers: [.command]),
                // Ctrl+C 在 Terminal/iTerm2 里交给下面那条选中态规则处理，这里排除掉
                condition: kc == 8 ? .except(terminalIDs) : .all
            )
        }

        // Terminal/iTerm2 里 Ctrl+C：选中文本时复制，没选中时保留中断（SIGINT）
        result.insert(KeyMapping(
            name: "Ctrl+C → Cmd+C (Terminal, if selected)",
            trigger: KeyTrigger(keyCode: 8, modifiers: [.control]),
            action: .remap(keyCode: 8, modifiers: [.command]),
            condition: .only(terminalIDs),
            requireTextSelection: true
        ), at: 0)

        result.append(KeyMapping(
            name: "Ctrl+L → Lock & Sleep",
            trigger: KeyTrigger(keyCode: 37, modifiers: [.control]),
            action: .lockAndSleep
        ))

        result.append(KeyMapping(
            name: "ESC → Cmd+W (Finder/WeChat/QQ)",
            trigger: KeyTrigger(keyCode: 53, modifiers: []),
            action: .remap(keyCode: 13, modifiers: [.command]),
            condition: .only(["com.apple.finder", "com.tencent.xinWeChat", "com.tencent.qq"])
        ))

        result.append(KeyMapping(
            name: "F5 → Cmd+R (Edge)",
            trigger: KeyTrigger(keyCode: 96, modifiers: []),
            action: .remap(keyCode: 15, modifiers: [.command]),
            condition: .only(["com.microsoft.edgemac"])
        ))

        return result
    }
}
