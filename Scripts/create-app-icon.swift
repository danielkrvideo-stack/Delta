import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: create-app-icon.swift output.png\n", stderr)
    exit(EXIT_FAILURE)
}

let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not allocate the app icon image.\n", stderr)
    exit(EXIT_FAILURE)
}

NSGraphicsContext.saveGraphicsState()
guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create an app icon graphics context.\n", stderr)
    exit(EXIT_FAILURE)
}
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 20, dy: 20), xRadius: 230, yRadius: 230)
background.addClip()

NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.22, blue: 0.48, alpha: 1),
    NSColor(calibratedRed: 0.27, green: 0.30, blue: 0.62, alpha: 1),
    NSColor(calibratedRed: 0.48, green: 0.28, blue: 0.58, alpha: 1)
])?.draw(in: bounds, angle: -35)

NSColor.white.withAlphaComponent(0.08).setFill()
NSBezierPath(ovalIn: NSRect(x: 610, y: 545, width: 590, height: 590)).fill()

let rim = NSBezierPath(ovalIn: NSRect(x: 174, y: 174, width: 676, height: 676))
NSColor.white.withAlphaComponent(0.22).setStroke()
rim.lineWidth = 12
rim.stroke()

let delta = NSBezierPath()
delta.move(to: NSPoint(x: 512, y: 764))
delta.line(to: NSPoint(x: 760, y: 300))
delta.line(to: NSPoint(x: 264, y: 300))
delta.close()
NSColor.white.setFill()
delta.fill()

let counter = NSBezierPath()
counter.move(to: NSPoint(x: 512, y: 624))
counter.line(to: NSPoint(x: 661, y: 352))
counter.line(to: NSPoint(x: 363, y: 352))
counter.close()
NSColor(calibratedRed: 0.30, green: 0.30, blue: 0.61, alpha: 1).setFill()
counter.fill()

NSColor.white.withAlphaComponent(0.96).setFill()
NSBezierPath(ovalIn: NSRect(x: 489, y: 466, width: 46, height: 46)).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the app icon PNG.\n", stderr)
    exit(EXIT_FAILURE)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
do {
    try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: output, options: .atomic)
} catch {
    fputs("Could not write app icon: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
