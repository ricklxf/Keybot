import Foundation
import Combine

final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published var mappings: [KeyMapping] {
        didSet { save() }
    }

    private let storePath: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Keybot")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storePath = dir.appendingPathComponent("config.json")
        mappings = Self.load(from: storePath) ?? Self.defaultMappings()
    }

    var enabledMappings: [KeyMapping] {
        mappings.filter(\.enabled)
    }

    private static func load(from url: URL) -> [KeyMapping]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([KeyMapping].self, from: data)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        try? data.write(to: storePath, options: .atomic)
    }

    func resetToDefaults() {
        mappings = Self.defaultMappings()
    }

    static func defaultMappings() -> [KeyMapping] {
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
                action: .remap(keyCode: kc, modifiers: [.command])
            )
        }

        result.append(KeyMapping(
            name: "Ctrl+L → 锁屏+休眠",
            trigger: KeyTrigger(keyCode: 37, modifiers: [.control]),
            action: .lockAndSleep
        ))

        result.append(KeyMapping(
            name: "ESC → Cmd+W（访达/微信/QQ）",
            trigger: KeyTrigger(keyCode: 53, modifiers: []),
            action: .remap(keyCode: 13, modifiers: [.command]),
            condition: .only(["com.apple.finder", "com.tencent.xinWeChat", "com.tencent.qq"])
        ))

        result.append(KeyMapping(
            name: "F5 → Cmd+R（Edge）",
            trigger: KeyTrigger(keyCode: 96, modifiers: []),
            action: .remap(keyCode: 15, modifiers: [.command]),
            condition: .only(["com.microsoft.edgemac"])
        ))

        return result
    }
}
