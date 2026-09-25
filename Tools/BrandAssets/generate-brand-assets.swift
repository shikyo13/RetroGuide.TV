#!/usr/bin/env swift
// Generates the tvOS app icon (layered image stacks) and Top Shelf images
// from the in-app RetroGuide.TV wordmark (see App/DesignSystem/Components/BrandMark.swift).
//
// Usage (from the repository root, on macOS):
//   swift Tools/BrandAssets/generate-brand-assets.swift App/Resources/Assets.xcassets

import AppKit
import CoreGraphics
import Foundation

// MARK: - Brand constants (mirror the app's Classic Cable theme and BrandMark)

enum Palette {
    static let backgroundTop = rgb(0x0A1A5C)
    static let backgroundBottom = rgb(0x050D33)
    static let accent = rgb(0xFFD23F)
    static let text = rgb(0xFFFFFF)
    static let secondaryText = rgb(0xB8C4F0)
    static let scanline = rgb(0x000000)

    static func rgb(_ hex: Int) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Keep in sync with `TVGlyph.Geometry` (fractions of the glyph width).
enum GlyphGeometry {
    static let aspectRatio: CGFloat = 1.18
    static let bodyHeight: CGFloat = 0.72
    static let bodyCornerRadius: CGFloat = 0.16
    static let frameThickness: CGFloat = 0.085
    static let screenGap: CGFloat = 0.05
    static let screenCornerRadius: CGFloat = 0.07
    static let standWidth: CGFloat = 0.44
    static let standHeight: CGFloat = 0.075
    static let standGap: CGFloat = 0.05
}

/// Keep in sync with `BrandMark` and `DesignTokens.Spacing.sm` relative to the headline size.
enum WordmarkSpec {
    static let name = "RetroGuide"
    static let suffix = ".TV"
    static let tagline = "Your library, on the air."
    static let glyphToTextRatio: CGFloat = 1.1
    static let spacingToTextRatio: CGFloat = 12.0 / 36.0
    static let fontWeight = NSFont.Weight.semibold
}

enum ScanlineSpec {
    static let period: CGFloat = 4
    static let thickness: CGFloat = 1.5
    static let alpha: CGFloat = 0.16
}

/// Output sizes in points; 2x variants are rendered for Apple TV 4K.
enum Canvas {
    static let homeIcon = CGSize(width: 400, height: 240)
    static let appStoreIcon = CGSize(width: 1280, height: 768)
    static let topShelf = CGSize(width: 1920, height: 720)
    static let topShelfWide = CGSize(width: 2320, height: 720)
    static let touchIcon = CGSize(width: 1024, height: 1024)
    /// Wordmark width as a fraction of the canvas: inside the icon's parallax safe zone.
    static let iconWordmarkWidth: CGFloat = 0.8
    static let shelfWordmarkWidth: CGFloat = 0.5
    static let shelfTaglineToText: CGFloat = 0.36
    static let shelfTaglineGapToText: CGFloat = 0.35
    /// Square iPhone/iPad icon: a large TV glyph above the wordmark text.
    static let touchGlyphWidth: CGFloat = 0.5
    static let touchWordmarkWidth: CGFloat = 0.78
    static let touchGapToGlyph: CGFloat = 0.14
}

// MARK: - Rendering

typealias Draw = (CGContext, CGSize) -> Void

func render(_ size: CGSize, scale: CGFloat, opaque: Bool, _ draw: Draw) -> Data {
    guard let context = CGContext(
        data: nil,
        width: Int(size.width * scale),
        height: Int(size.height * scale),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue
    ) else { fatalError("Could not create a bitmap context") }
    context.scaleBy(x: scale, y: scale)
    // Top-left origin, like SwiftUI.
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    draw(context, size)
    NSGraphicsContext.restoreGraphicsState()
    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { fatalError("Could not encode PNG") }
    return png
}

func drawBackground(_ context: CGContext, _ size: CGSize) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [Palette.backgroundTop, Palette.backgroundBottom] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    context.setFillColor(Palette.scanline.copy(alpha: ScanlineSpec.alpha)!)
    var y: CGFloat = 0
    while y < size.height {
        context.fill(CGRect(x: 0, y: y, width: size.width, height: ScanlineSpec.thickness))
        y += ScanlineSpec.period
    }
}

func glyphPath(in rect: CGRect) -> CGPath {
    let unit = rect.width
    let path = CGMutablePath()
    let body = CGRect(x: rect.minX, y: rect.minY, width: unit, height: GlyphGeometry.bodyHeight * unit)
    let frameInner = body.insetBy(dx: GlyphGeometry.frameThickness * unit, dy: GlyphGeometry.frameThickness * unit)
    let screen = frameInner.insetBy(dx: GlyphGeometry.screenGap * unit, dy: GlyphGeometry.screenGap * unit)
    let innerRadius = (GlyphGeometry.bodyCornerRadius - GlyphGeometry.frameThickness) * unit
    path.addRoundedRect(in: body, cornerWidth: GlyphGeometry.bodyCornerRadius * unit, cornerHeight: GlyphGeometry.bodyCornerRadius * unit)
    path.addRoundedRect(in: frameInner, cornerWidth: innerRadius, cornerHeight: innerRadius)
    path.addRoundedRect(in: screen, cornerWidth: GlyphGeometry.screenCornerRadius * unit, cornerHeight: GlyphGeometry.screenCornerRadius * unit)
    let standHeight = GlyphGeometry.standHeight * unit
    let stand = CGRect(x: rect.midX - GlyphGeometry.standWidth * unit / 2, y: body.maxY + GlyphGeometry.standGap * unit,
                       width: GlyphGeometry.standWidth * unit, height: standHeight)
    path.addRoundedRect(in: stand, cornerWidth: standHeight / 2, cornerHeight: standHeight / 2)
    return path
}

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

/// Lays out the wordmark at `fontSize` and returns its width plus a drawing closure.
/// Without the glyph, only the "RetroGuide.TV" text is drawn.
func wordmark(fontSize: CGFloat, includesGlyph: Bool = true) -> (width: CGFloat, height: CGFloat, draw: (CGContext, CGPoint) -> Void) {
    let font = roundedFont(size: fontSize, weight: WordmarkSpec.fontWeight)
    let text = NSMutableAttributedString(string: WordmarkSpec.name, attributes: [.font: font, .foregroundColor: NSColor(cgColor: Palette.text)!])
    text.append(NSAttributedString(string: WordmarkSpec.suffix, attributes: [.font: font, .foregroundColor: NSColor(cgColor: Palette.accent)!]))
    let textSize = text.size()
    let glyphWidth = includesGlyph ? fontSize * WordmarkSpec.glyphToTextRatio : 0
    let glyphHeight = glyphWidth / GlyphGeometry.aspectRatio
    let spacing = includesGlyph ? fontSize * WordmarkSpec.spacingToTextRatio : 0
    let width = glyphWidth + spacing + textSize.width
    let height = max(glyphHeight, textSize.height)
    return (width, height, { context, origin in
        if includesGlyph {
            let glyphRect = CGRect(x: origin.x, y: origin.y + (height - glyphHeight) / 2, width: glyphWidth, height: glyphHeight)
            context.addPath(glyphPath(in: glyphRect))
            context.setFillColor(Palette.accent)
            context.fillPath(using: .evenOdd)
        }
        text.draw(at: CGPoint(x: origin.x + glyphWidth + spacing, y: origin.y + (height - textSize.height) / 2))
    })
}

/// Largest wordmark that fits `targetWidth`.
func fittedWordmark(targetWidth: CGFloat, includesGlyph: Bool = true) -> (width: CGFloat, height: CGFloat, fontSize: CGFloat, draw: (CGContext, CGPoint) -> Void) {
    let probeSize: CGFloat = 100
    let probe = wordmark(fontSize: probeSize, includesGlyph: includesGlyph)
    let fontSize = probeSize * targetWidth / probe.width
    let fitted = wordmark(fontSize: fontSize, includesGlyph: includesGlyph)
    return (fitted.width, fitted.height, fontSize, fitted.draw)
}

// MARK: - Layers

let backLayer: Draw = { context, size in drawBackground(context, size) }
let frontLayer: Draw = { context, size in
    let mark = fittedWordmark(targetWidth: size.width * Canvas.iconWordmarkWidth)
    mark.draw(context, CGPoint(x: (size.width - mark.width) / 2, y: (size.height - mark.height) / 2))
}

let topShelf: Draw = { context, size in
    drawBackground(context, size)
    let mark = fittedWordmark(targetWidth: size.width * Canvas.shelfWordmarkWidth)
    let taglineFont = roundedFont(size: mark.fontSize * Canvas.shelfTaglineToText, weight: .medium)
    let tagline = NSAttributedString(string: WordmarkSpec.tagline,
                                     attributes: [.font: taglineFont, .foregroundColor: NSColor(cgColor: Palette.secondaryText)!])
    let taglineSize = tagline.size()
    let gap = mark.fontSize * Canvas.shelfTaglineGapToText
    let top = (size.height - mark.height - gap - taglineSize.height) / 2
    mark.draw(context, CGPoint(x: (size.width - mark.width) / 2, y: top))
    tagline.draw(at: CGPoint(x: (size.width - taglineSize.width) / 2, y: top + mark.height + gap))
}

/// The square icon: the glyph can't be read inside a full-width wordmark at
/// home-screen size, so it is drawn large with the wordmark text underneath.
let touchIcon: Draw = { context, size in
    drawBackground(context, size)
    let glyphWidth = size.width * Canvas.touchGlyphWidth
    let glyphHeight = glyphWidth / GlyphGeometry.aspectRatio
    let gap = glyphHeight * Canvas.touchGapToGlyph
    let mark = fittedWordmark(targetWidth: size.width * Canvas.touchWordmarkWidth, includesGlyph: false)
    let top = (size.height - glyphHeight - gap - mark.height) / 2
    context.addPath(glyphPath(in: CGRect(x: (size.width - glyphWidth) / 2, y: top, width: glyphWidth, height: glyphHeight)))
    context.setFillColor(Palette.accent)
    context.fillPath(using: .evenOdd)
    mark.draw(context, CGPoint(x: (size.width - mark.width) / 2, y: top + glyphHeight + gap))
}

// MARK: - Asset catalog output

guard CommandLine.arguments.count == 2 else {
    print("usage: swift generate-brand-assets.swift <path/to/Assets.xcassets>")
    exit(1)
}
let catalog = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default
let info: [String: Any] = ["author": "xcode", "version": 1]

func writeContents(_ object: [String: Any], to directory: URL) {
    try! fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: directory.appendingPathComponent("Contents.json"))
}

func writeImageSet(at directory: URL, size: CGSize, scales: [CGFloat], opaque: Bool, idiom: String = "tv", draw: Draw) {
    try! fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let images: [[String: Any]] = scales.map { scale in
        let name = scale == 1 ? "image.png" : "image@\(Int(scale))x.png"
        try! render(size, scale: scale, opaque: opaque, draw).write(to: directory.appendingPathComponent(name))
        return ["filename": name, "idiom": idiom, "scale": "\(Int(scale))x"]
    }
    writeContents(["images": images, "info": info], to: directory)
}

func writeImageStack(named name: String, in brand: URL, size: CGSize, scales: [CGFloat]) {
    let stack = brand.appendingPathComponent("\(name).imagestack")
    let layers: [(name: String, draw: Draw, opaque: Bool)] = [
        ("Front", frontLayer, false), ("Back", backLayer, true),
    ]
    for layer in layers {
        let directory = stack.appendingPathComponent("\(layer.name).imagestacklayer")
        writeContents(["info": info], to: directory)
        writeImageSet(at: directory.appendingPathComponent("Content.imageset"), size: size, scales: scales, opaque: layer.opaque, draw: layer.draw)
    }
    writeContents(["info": info, "layers": layers.map { ["filename": "\($0.name).imagestacklayer"] }], to: stack)
}

writeContents(["info": info], to: catalog)
let brand = catalog.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
writeImageStack(named: "App Icon", in: brand, size: Canvas.homeIcon, scales: [1, 2])
writeImageStack(named: "App Icon - App Store", in: brand, size: Canvas.appStoreIcon, scales: [1])
writeImageSet(at: brand.appendingPathComponent("Top Shelf Image.imageset"), size: Canvas.topShelf, scales: [1, 2], opaque: true, draw: topShelf)
writeImageSet(at: brand.appendingPathComponent("Top Shelf Image Wide.imageset"), size: Canvas.topShelfWide, scales: [1, 2], opaque: true, draw: topShelf)
writeContents([
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
    "info": info,
], to: brand)

// iPhone and iPad: one 1024 pt image; Xcode derives the other sizes.
let appIcon = catalog.appendingPathComponent("AppIcon.appiconset")
try! fileManager.createDirectory(at: appIcon, withIntermediateDirectories: true)
try! render(Canvas.touchIcon, scale: 1, opaque: true, touchIcon).write(to: appIcon.appendingPathComponent("icon-1024.png"))
writeContents([
    "images": [["filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]],
    "info": info,
], to: appIcon)
print("Wrote brand assets to \(catalog.path)")
