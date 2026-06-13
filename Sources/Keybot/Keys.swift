import CoreGraphics

enum Keys {
    static let a: CGKeyCode = 0
    static let s: CGKeyCode = 1
    static let f: CGKeyCode = 3
    static let z: CGKeyCode = 6
    static let x: CGKeyCode = 7
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9
    static let q: CGKeyCode = 12
    static let w: CGKeyCode = 13
    static let r: CGKeyCode = 15
    static let l: CGKeyCode = 37
    static let escape: CGKeyCode = 53
    static let f5: CGKeyCode = 96

    // Ctrl → Cmd 全局映射的按键集合（只改 modifier，key code 不变）
    static let ctrlToCmd: Set<CGKeyCode> = [c, v, x, z, a, s, f]
}
