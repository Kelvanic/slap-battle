import AppKit
import CoreGraphics
import Foundation

// Original vector artwork rendered at each native icon size; no fonts or external assets.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = output.appendingPathComponent("SlapBattle.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) throws -> Data {
  guard let context = CGContext(data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: size * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    throw NSError(domain: "Icon", code: 1)
  }
  context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  context.translateBy(x: 0, y: 1024)
  context.scaleBy(x: 1, y: -1)

  let tile = CGPath(roundedRect: CGRect(x: 80, y: 80, width: 864, height: 864),
    cornerWidth: 190, cornerHeight: 190, transform: nil)
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: 10), blur: 20,
    color: NSColor.black.withAlphaComponent(0.17).cgColor)
  context.addPath(tile)
  context.setFillColor(NSColor(srgbRed: 0.29, green: 0.40, blue: 0.49, alpha: 1).cgColor)
  context.fillPath()
  context.restoreGState()
  context.saveGState()
  context.addPath(tile)
  context.clip()
  let colors = [NSColor(srgbRed: 0.34, green: 0.45, blue: 0.54, alpha: 1).cgColor,
                NSColor(srgbRed: 0.24, green: 0.34, blue: 0.42, alpha: 1).cgColor]
  let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: colors as CFArray, locations: [0, 1])!
  context.drawLinearGradient(gradient, start: CGPoint(x: 220, y: 90),
    end: CGPoint(x: 780, y: 940), options: [])
  context.restoreGState()

  // Rounded fingers and thumb form one continuous silhouette, legible at 16px.
  context.saveGState()
  context.translateBy(x: 512, y: 512)
  context.rotate(by: -0.13)
  context.translateBy(x: -566, y: -491)
  let hand = CGMutablePath()
  hand.move(to: CGPoint(x: 416, y: 790))
  hand.addLine(to: CGPoint(x: 660, y: 790))
  hand.addLine(to: CGPoint(x: 660, y: 716))
  hand.addCurve(to: CGPoint(x: 764, y: 521), control1: CGPoint(x: 734, y: 656), control2: CGPoint(x: 764, y: 592))
  hand.addLine(to: CGPoint(x: 764, y: 340))
  hand.addCurve(to: CGPoint(x: 714, y: 340), control1: CGPoint(x: 764, y: 302), control2: CGPoint(x: 714, y: 302))
  hand.addLine(to: CGPoint(x: 714, y: 483))
  hand.addLine(to: CGPoint(x: 699, y: 483))
  hand.addLine(to: CGPoint(x: 699, y: 238))
  hand.addCurve(to: CGPoint(x: 645, y: 238), control1: CGPoint(x: 699, y: 198), control2: CGPoint(x: 645, y: 198))
  hand.addLine(to: CGPoint(x: 645, y: 451))
  hand.addLine(to: CGPoint(x: 627, y: 451))
  hand.addLine(to: CGPoint(x: 627, y: 188))
  hand.addCurve(to: CGPoint(x: 571, y: 188), control1: CGPoint(x: 627, y: 148), control2: CGPoint(x: 571, y: 148))
  hand.addLine(to: CGPoint(x: 571, y: 448))
  hand.addLine(to: CGPoint(x: 553, y: 448))
  hand.addLine(to: CGPoint(x: 553, y: 224))
  hand.addCurve(to: CGPoint(x: 499, y: 224), control1: CGPoint(x: 553, y: 184), control2: CGPoint(x: 499, y: 184))
  hand.addLine(to: CGPoint(x: 499, y: 498))
  hand.addLine(to: CGPoint(x: 478, y: 518))
  hand.addLine(to: CGPoint(x: 428, y: 452))
  hand.addCurve(to: CGPoint(x: 366, y: 490), control1: CGPoint(x: 383, y: 396), control2: CGPoint(x: 329, y: 440))
  hand.addLine(to: CGPoint(x: 424, y: 582))
  hand.addCurve(to: CGPoint(x: 447, y: 657), control1: CGPoint(x: 449, y: 618), control2: CGPoint(x: 447, y: 632))
  hand.addLine(to: CGPoint(x: 416, y: 790))
  hand.closeSubpath()
  context.setShadow(offset: CGSize(width: 0, height: 14), blur: 18,
    color: NSColor.black.withAlphaComponent(0.18).cgColor)
  context.addPath(hand)
  context.setFillColor(NSColor(srgbRed: 0.96, green: 0.92, blue: 0.83, alpha: 1).cgColor)
  context.fillPath()
  context.setShadow(offset: .zero, blur: 0)

  // One palm crease, not tiny decorative lines that disappear at small sizes.
  let crease = CGMutablePath()
  crease.move(to: CGPoint(x: 493, y: 566))
  crease.addCurve(to: CGPoint(x: 635, y: 552), control1: CGPoint(x: 530, y: 529), control2: CGPoint(x: 587, y: 531))
  context.addPath(crease)
  context.setStrokeColor(NSColor(srgbRed: 0.66, green: 0.61, blue: 0.52, alpha: 0.55).cgColor)
  context.setLineWidth(12)
  context.setLineCap(.round)
  context.strokePath()
  context.restoreGState()

  // A compact high-five spark; restrained warm colour rather than neon confetti.
  context.setStrokeColor(NSColor(srgbRed: 0.78, green: 0.69, blue: 0.48, alpha: 1).cgColor)
  context.setLineWidth(18)
  context.setLineCap(.round)
  for (from, to) in [(CGPoint(x: 290, y: 271), CGPoint(x: 249, y: 235)),
                     (CGPoint(x: 270, y: 329), CGPoint(x: 217, y: 319)),
                     (CGPoint(x: 343, y: 230), CGPoint(x: 328, y: 180))] {
    context.move(to: from)
    context.addLine(to: to)
    context.strokePath()
  }
  guard let image = context.makeImage() else { throw NSError(domain: "Icon", code: 2) }
  let bitmap = NSBitmapImageRep(cgImage: image)
  guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Icon", code: 3) }
  return png
}

for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let suffix = scale == 2 ? "@2x" : ""
    let png = try render(size: points * scale)
    try png.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
  }
}
try render(size: 1024).write(to: output.appendingPathComponent("AppIcon.png"))
print("Generated original Slap Battle icon sizes in \(output.path)")
