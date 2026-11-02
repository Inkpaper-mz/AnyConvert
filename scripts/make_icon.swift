#!/usr/bin/env swift
import AppKit
import Foundation

// 生成 App 图标：渐变圆角方块 + 双向箭头
let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.iconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// 底板
let inset: CGFloat = 88
let rect = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let radius: CGFloat = 198
let plate = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

NSGraphicsContext.saveGraphicsState()
plate.addClip()
let blue = NSColor(srgbRed: 0.29, green: 0.47, blue: 0.98, alpha: 1)
let violet = NSColor(srgbRed: 0.57, green: 0.38, blue: 0.96, alpha: 1)
NSGradient(starting: blue, ending: violet)?.draw(in: rect, angle: -62)

// 顶部高光
let gloss = NSBezierPath(ovalIn: NSRect(x: rect.minX - 120,
                                        y: rect.midY + 90,
                                        width: rect.width + 240,
                                        height: rect.height * 0.95))
NSColor.white.withAlphaComponent(0.14).setFill()
gloss.fill()
NSGraphicsContext.restoreGraphicsState()

// 内描边
NSColor.white.withAlphaComponent(0.18).setStroke()
plate.lineWidth = 6
plate.stroke()

// 双向箭头
let arrowColor = NSColor.white.withAlphaComponent(0.97)
arrowColor.set()

func arrow(y: CGFloat, from x1: CGFloat, to x2: CGFloat, pointingRight: Bool) {
    let thickness: CGFloat = 58
    let headLength: CGFloat = 104
    let headHeight: CGFloat = 142

    let body = NSBezierPath()
    body.lineWidth = thickness
    body.lineCapStyle = .round
    if pointingRight {
        body.move(to: NSPoint(x: x1, y: y))
        body.line(to: NSPoint(x: x2 - headLength * 0.72, y: y))
    } else {
        body.move(to: NSPoint(x: x2, y: y))
        body.line(to: NSPoint(x: x1 + headLength * 0.72, y: y))
    }
    body.stroke()

    let head = NSBezierPath()
    if pointingRight {
        head.move(to: NSPoint(x: x2, y: y))
        head.line(to: NSPoint(x: x2 - headLength, y: y + headHeight / 2))
        head.line(to: NSPoint(x: x2 - headLength, y: y - headHeight / 2))
    } else {
        head.move(to: NSPoint(x: x1, y: y))
        head.line(to: NSPoint(x: x1 + headLength, y: y + headHeight / 2))
        head.line(to: NSPoint(x: x1 + headLength, y: y - headHeight / 2))
    }
    head.close()
    head.fill()
}

let leftX = rect.minX + 168
let rightX = rect.maxX - 168
arrow(y: rect.midY + 108, from: leftX, to: rightX, pointingRight: true)
arrow(y: rect.midY - 108, from: leftX, to: rightX, pointingRight: false)

image.unlockFocus()

// 输出各尺寸
let variants: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (pixelSize, name) in variants {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixelSize,
                                     pixelsHigh: pixelSize,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { continue }
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    if let context = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    }
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: outputDir).appendingPathComponent(name))
    }
}

print("iconset written to \(outputDir)")
