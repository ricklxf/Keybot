#!/usr/bin/env swift
import AppKit

let canvas: CGFloat = 1024

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// 背景：深蓝 → 紫色渐变，圆角矩形裁剪
let bgPath = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: canvas, height: canvas),
    xRadius: 225, yRadius: 225
)
let bg = NSGradient(
    colors: [
        NSColor(red: 0.10, green: 0.17, blue: 0.35, alpha: 1),
        NSColor(red: 0.28, green: 0.14, blue: 0.50, alpha: 1)
    ],
    atLocations: [0, 1],
    colorSpace: .sRGB
)!
bg.draw(in: bgPath, angle: -50)

// 半透明圆形光晕（增加层次感）
let glowRect = NSRect(x: 162, y: 162, width: 700, height: 700)
let glowGrad = NSGradient(
    colors: [
        NSColor(red: 0.55, green: 0.45, blue: 1.0, alpha: 0.18),
        NSColor(red: 0.55, green: 0.45, blue: 1.0, alpha: 0.00)
    ],
    atLocations: [0, 1],
    colorSpace: .sRGB
)!
glowGrad.draw(in: glowRect, relativeCenterPosition: NSPoint(x: 0.5, y: 0.5))

// ⌘ 符号
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)

let font = NSFont.systemFont(ofSize: 580, weight: .thin)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(white: 1.0, alpha: 0.96),
    .shadow: shadow
]
let str = NSAttributedString(string: "⌘", attributes: attrs)
let strSize = str.size()
str.draw(at: NSPoint(
    x: (canvas - strSize.width) / 2,
    y: (canvas - strSize.height) / 2
))

image.unlockFocus()

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let tiff = image.tiffRepresentation!
let rep  = NSBitmapImageRep(data: tiff)!
let png  = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("✅ \(outPath)")
