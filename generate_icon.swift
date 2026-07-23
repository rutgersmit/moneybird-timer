#!/usr/bin/env swift
import AppKit
import CoreGraphics

let size = 1024
let center = CGPoint(x: 512, y: 512)
let colorSpace = CGColorSpaceCreateDeviceRGB()

let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// ── Background gradient ──────────────────────────────────────────────────────
let bgColors = [
    CGColor(red: 0.008, green: 0.22, blue: 0.55, alpha: 1),  // deep blue
    CGColor(red: 0.012, green: 0.451, blue: 0.902, alpha: 1), // #0373E6
] as CFArray

let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: CGFloat(size)),
    end: CGPoint(x: CGFloat(size), y: 0),
    options: []
)

// ── Outer glow ring ──────────────────────────────────────────────────────────
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: CGColor(red: 0.012, green: 0.451, blue: 0.902, alpha: 0.6))
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
ctx.setLineWidth(3)
ctx.addArc(center: center, radius: 440, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()
ctx.restoreGState()

// ── Clock face (frosted glass look) ──────────────────────────────────────────
let faceRadius: CGFloat = 370

// subtle radial fill inside clock
let faceColors = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.06),
] as CFArray
let faceGradient = CGGradient(colorsSpace: colorSpace, colors: faceColors, locations: [0.0, 1.0])!
ctx.saveGState()
ctx.addArc(center: center, radius: faceRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.clip()
ctx.drawRadialGradient(
    faceGradient,
    startCenter: CGPoint(x: 480, y: 560),
    startRadius: 0,
    endCenter: center,
    endRadius: faceRadius,
    options: []
)
ctx.restoreGState()

// clock face border with glow
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 24, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
ctx.setLineWidth(10)
ctx.addArc(center: center, radius: faceRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()
ctx.restoreGState()

// ── Tick marks ───────────────────────────────────────────────────────────────
for i in 0..<60 {
    let angle = CGFloat(i) * .pi / 30 - .pi / 2
    let isMajor = i % 5 == 0
    let isQuarter = i % 15 == 0

    let tickLen: CGFloat = isQuarter ? 52 : (isMajor ? 36 : 18)
    let lineW: CGFloat = isQuarter ? 13 : (isMajor ? 8 : 4)
    let alpha: CGFloat = isQuarter ? 1.0 : (isMajor ? 0.8 : 0.35)

    let outerR = faceRadius - 16
    let innerR = outerR - tickLen

    let start = CGPoint(x: center.x + outerR * cos(angle), y: center.y + outerR * sin(angle))
    let end   = CGPoint(x: center.x + innerR * cos(angle), y: center.y + innerR * sin(angle))

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
    ctx.setLineWidth(lineW)
    ctx.setLineCap(.round)
    ctx.move(to: start)
    ctx.addLine(to: end)
    ctx.strokePath()
}

// ── Clock hands ───────────────────────────────────────────────────────────────
func drawHand(angle: CGFloat, length: CGFloat, width: CGFloat, color: CGColor, shadowAlpha: CGFloat = 0.4) {
    let tip = CGPoint(
        x: center.x + length * cos(angle),
        y: center.y + length * sin(angle)
    )
    // counter-weight tail
    let tail = CGPoint(
        x: center.x - (length * 0.15) * cos(angle),
        y: center.y - (length * 0.15) * sin(angle)
    )
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 12,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: shadowAlpha))
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.move(to: tail)
    ctx.addLine(to: tip)
    ctx.strokePath()
    ctx.restoreGState()
}

// 10:10 position — "happy" clock, shows off both hands nicely
let hourAngle   = CGFloat(10) / 12 * 2 * .pi - .pi / 2 + (.pi / 6 * 10 / 60)  // add minute offset
let minuteAngle = CGFloat(10) / 60 * 2 * .pi - .pi / 2

drawHand(angle: hourAngle,   length: 210, width: 24, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
drawHand(angle: minuteAngle, length: 300, width: 16, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))

// second hand (pointing toward 30s = bottom) — adds dynamism
let secondAngle: CGFloat = .pi / 2   // pointing down
drawHand(angle: secondAngle, length: 310, width: 5,
         color: CGColor(red: 1.0, green: 0.35, blue: 0.25, alpha: 1), shadowAlpha: 0.3)

// ── Center cap ───────────────────────────────────────────────────────────────
let capR: CGFloat = 26
// teal fill
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
ctx.setFillColor(CGColor(red: 0.012, green: 0.451, blue: 0.902, alpha: 1))
ctx.addArc(center: center, radius: capR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.fillPath()
ctx.restoreGState()
// white ring
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(5)
ctx.addArc(center: center, radius: capR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()

// ── Moneybird "M" lettermark (bottom of clock face, subtle) ──────────────────
// CoreGraphics: y=0 is at BOTTOM. To place "M" below clock center (512 from top),
// we need CG y = 1024 - yFromTop. "Below center" = yFromTop > 512.
// Target: 680px from top → CG y = 344. M opens upward in CG = opens downward visually.
let mCX: CGFloat = 512
let mCY: CGFloat = 344    // CG coords: 1024 - 680 = 344 (680px from top = below center)
let mW: CGFloat  = 86
let mH: CGFloat  = 56
let mAlpha: CGFloat = 0.5

ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: mAlpha))

// Left vertical leg
ctx.fill(CGRect(x: mCX - mW/2, y: mCY, width: 13, height: mH))
// Right vertical leg
ctx.fill(CGRect(x: mCX + mW/2 - 13, y: mCY, width: 13, height: mH))

// In CG coords (y up), "top of M" is at mCY + mH, peak of V is at mCY.
// Left diagonal: top-left corner → peak-center
let pathL = CGMutablePath()
pathL.move(to:    CGPoint(x: mCX - mW/2,      y: mCY + mH))
pathL.addLine(to: CGPoint(x: mCX - mW/2 + 13, y: mCY + mH))
pathL.addLine(to: CGPoint(x: mCX,             y: mCY + 13))
pathL.addLine(to: CGPoint(x: mCX,             y: mCY))
pathL.addLine(to: CGPoint(x: mCX - mW/2,      y: mCY + mH - 13))
pathL.closeSubpath()
ctx.addPath(pathL); ctx.fillPath()

// Right diagonal: top-right corner → peak-center
let pathR = CGMutablePath()
pathR.move(to:    CGPoint(x: mCX + mW/2,      y: mCY + mH))
pathR.addLine(to: CGPoint(x: mCX + mW/2 - 13, y: mCY + mH))
pathR.addLine(to: CGPoint(x: mCX,             y: mCY + 13))
pathR.addLine(to: CGPoint(x: mCX,             y: mCY))
pathR.addLine(to: CGPoint(x: mCX + mW/2,      y: mCY + mH - 13))
pathR.closeSubpath()
ctx.addPath(pathR); ctx.fillPath()

// ── Export ───────────────────────────────────────────────────────────────────
let cgImage = ctx.makeImage()!
let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
let pngData = bitmapRep.representation(using: .png, properties: [:])!

let outputPath = "/Users/rutger/repos/rusm/moneybird-timer/MoneybirdTimer/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Icon written to \(outputPath)")
