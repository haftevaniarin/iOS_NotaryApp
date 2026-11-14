import AppKit
import ImageIO

// Render the web app's public/notary-ledger-icon.svg without changing the seal.
// Run from the repository root: swift scripts/generate-app-icon.swift
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("scripts/assets/notary-ledger-icon.svg")
let output = root.appendingPathComponent("notaryledger-ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let size = 1024

guard let artwork = NSImage(contentsOf: source), artwork.isValid,
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: size * 4, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Could not load the web logo or create the app icon canvas.")
}

// Fill the SVG's transparent corners with its parchment background. App Store
// icons must be opaque; iOS supplies the rounded app icon mask.
let bounds = CGRect(x: 0, y: 0, width: size, height: size)
context.setFillColor(CGColor(srgbRed: 250.0 / 255, green: 246.0 / 255, blue: 236.0 / 255, alpha: 1))
context.fill(bounds)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
artwork.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("Could not create the app icon PNG.")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write the app icon PNG.") }
print("Generated opaque \(size)×\(size) app icon: \(output.path)")
