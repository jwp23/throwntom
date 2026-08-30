#!/usr/bin/env swift
//
// unmatte-white-background.swift — turn the white surround of flat artwork
// into real transparency, so the image sits on any page background.
//
// Artwork exported as opaque RGB carries its white backdrop with it, and that
// backdrop shows as white blocks in a dark-themed reader. This recovers the
// alpha channel the export threw away.
//
// The surround is found by a flood fill seeded at the four corners, so only
// background connected to the outside is touched — white *inside* the art (a
// ring, a wordmark, a highlight) is enclosed by opaque pixels and is never
// reached. Each surround pixel is then un-composited from the background: a
// pixel with value C over background B is read as C = a*F + (1-a)*B, and
// taking the foreground's darkest channel as 0 gives a = 1 - min(C/B) and
// F = (C - (1-a)*B) / a. B is sampled from the image's own corner rather than
// assumed to be pure white: exported art often sits on an off-white such as
// (254,254,254), and assuming 255 leaves the corners a hair short of
// transparent. Background pixels become fully transparent; the soft edge keeps
// its exact coverage, so compositing the result back over B reproduces the
// input.
//
// The flood spreads only through pixels at or above --threshold, which must
// sit above the artwork's own darkest channel so the fill cannot leak inside.
// The reported filled-pixel count makes a leak obvious: it jumps to most of
// the image.
//
// Usage:
//   tools/unmatte-white-background.swift <input.png> <output.png> [--threshold N]
//   tools/unmatte-white-background.swift --verify <input.png> <output.png>
//
// --verify re-checks a generated file against its source: the output must
// carry an alpha channel, its four corners must be fully transparent, and
// compositing it back over the source's background must reproduce the source,
// leaving every fully opaque pixel untouched. Run it after
// regenerating to confirm the asset is still correct.

import AppKit

let defaultThreshold = 45
let compositeTolerance = 2

struct Bitmap {
    var pixels: [UInt8]  // RGBA, straight (non-premultiplied) alpha
    let width: Int
    let height: Int

    init(pixels: [UInt8], width: Int, height: Int) {
        self.pixels = pixels
        self.width = width
        self.height = height
    }

    func index(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    func minChannel(_ x: Int, _ y: Int) -> Int {
        let i = index(x, y)
        return min(Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }

    /// The flat backdrop the art was exported over, read from the top-left corner.
    var backgroundColor: [Double] {
        let i = index(0, 0)
        return (0..<3).map { Double(pixels[i + $0]) }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("unmatte-white-background: \(message)\n".data(using: .utf8)!)
    exit(1)
}

func loadBitmap(_ path: String) -> Bitmap {
    guard let image = NSImage(contentsOfFile: path),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("could not load \(path)")
    }
    let width = cgImage.width
    let height = cgImage.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("could not create a drawing context for \(path)")
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Undo premultiplication so the buffer always holds straight alpha.
    for p in stride(from: 0, to: pixels.count, by: 4) {
        let a = Int(pixels[p + 3])
        guard a > 0, a < 255 else { continue }
        for c in 0..<3 {
            pixels[p + c] = UInt8(min(255, Int(pixels[p + c]) * 255 / a))
        }
    }
    return Bitmap(pixels: pixels, width: width, height: height)
}

func writePNG(_ bitmap: Bitmap, to path: String) {
    let pixels = bitmap.pixels
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: bitmap.width,
        pixelsHigh: bitmap.height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: .alphaNonpremultiplied,
        bytesPerRow: bitmap.width * 4,
        bitsPerPixel: 32
    ), let destination = rep.bitmapData else {
        fail("could not create an output bitmap")
    }
    pixels.withUnsafeBufferPointer { source in
        destination.update(from: source.baseAddress!, count: pixels.count)
    }
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fail("could not encode PNG")
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        fail("could not write \(path): \(error)")
    }
}

/// Marks every pixel reachable from a corner through background-bright pixels.
func floodFillSurround(_ bitmap: Bitmap, threshold: Int) -> [Bool] {
    var surround = [Bool](repeating: false, count: bitmap.width * bitmap.height)
    let corners = [
        (0, 0), (bitmap.width - 1, 0),
        (0, bitmap.height - 1), (bitmap.width - 1, bitmap.height - 1),
    ]
    var stack: [(Int, Int)] = []
    for (x, y) in corners where bitmap.minChannel(x, y) >= threshold {
        let cell = y * bitmap.width + x
        if !surround[cell] {
            surround[cell] = true
            stack.append((x, y))
        }
    }
    while let (x, y) = stack.popLast() {
        for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
            guard nx >= 0, nx < bitmap.width, ny >= 0, ny < bitmap.height else { continue }
            let cell = ny * bitmap.width + nx
            guard !surround[cell], bitmap.minChannel(nx, ny) >= threshold else { continue }
            surround[cell] = true
            stack.append((nx, ny))
        }
    }
    return surround
}

/// Replaces the background surround with straight-alpha coverage.
func unmatte(_ bitmap: Bitmap, surround: [Bool]) -> Bitmap {
    var result = bitmap
    let background = bitmap.backgroundColor
    for cell in 0..<surround.count where surround[cell] {
        let i = cell * 4
        // Coverage assumes the foreground's darkest channel is 0, so the
        // channel furthest below the backdrop sets how much art is present.
        var coverage = 0.0
        for c in 0..<3 where background[c] > 0 {
            coverage = max(coverage, 1 - Double(result.pixels[i + c]) / background[c])
        }
        let alpha = Int((min(max(coverage, 0), 1) * 255).rounded())
        guard alpha > 0 else {
            for c in 0..<4 { result.pixels[i + c] = 0 }
            continue
        }
        let a = Double(alpha) / 255
        for c in 0..<3 {
            let value = (Double(result.pixels[i + c]) - (1 - a) * background[c]) / a
            result.pixels[i + c] = UInt8(max(0, min(255, value.rounded())))
        }
        result.pixels[i + 3] = UInt8(alpha)
    }
    return result
}

func generate(input: String, output: String, threshold: Int) {
    let source = loadBitmap(input)
    let surround = floodFillSurround(source, threshold: threshold)
    let filled = surround.lazy.filter { $0 }.count
    let total = source.width * source.height
    writePNG(unmatte(source, surround: surround), to: output)
    let percent = Double(filled) / Double(total) * 100
    print("wrote \(output) — \(source.width)x\(source.height), "
        + String(format: "surround %d px (%.1f%% of image)", filled, percent))
}

func verify(input: String, output: String) {
    let source = loadBitmap(input)
    let result = loadBitmap(output)
    var failures: [String] = []

    guard source.width == result.width, source.height == result.height else {
        fail("size mismatch: source \(source.width)x\(source.height), output \(result.width)x\(result.height)")
    }

    if !result.pixels.contains(where: { $0 != 255 }) {
        failures.append("output has no alpha variation at all")
    }

    let corners = [
        ("top-left", 0, 0), ("top-right", result.width - 1, 0),
        ("bottom-left", 0, result.height - 1), ("bottom-right", result.width - 1, result.height - 1),
    ]
    for (name, x, y) in corners {
        let alpha = result.pixels[result.index(x, y) + 3]
        print("  corner \(name) (\(x),\(y)) alpha=\(alpha)")
        if alpha != 0 {
            failures.append("corner \(name) is not transparent (alpha=\(alpha))")
        }
    }

    let background = source.backgroundColor
    print("  source background: rgb(\(background.map { Int($0) }.map(String.init).joined(separator: ",")))")
    var worst = 0
    var worstAt = (0, 0)
    var opaqueChanged = 0
    for y in 0..<result.height {
        for x in 0..<result.width {
            let i = result.index(x, y)
            let alpha = Int(result.pixels[i + 3])
            let a = Double(alpha) / 255
            var pixelWorst = 0
            for c in 0..<3 {
                let over = Double(result.pixels[i + c]) * a + background[c] * (1 - a)
                pixelWorst = max(pixelWorst, abs(Int(over.rounded()) - Int(source.pixels[i + c])))
            }
            if alpha == 255, pixelWorst != 0 { opaqueChanged += 1 }
            if pixelWorst > worst {
                worst = pixelWorst
                worstAt = (x, y)
            }
        }
    }
    print("  worst channel difference over white: \(worst) at \(worstAt.0),\(worstAt.1)")
    print("  fully opaque pixels that changed: \(opaqueChanged)")
    if worst > compositeTolerance {
        failures.append("compositing over white does not reproduce the source (off by \(worst))")
    }
    if opaqueChanged != 0 {
        failures.append("\(opaqueChanged) opaque pixels changed; the artwork was altered")
    }

    guard failures.isEmpty else {
        for failure in failures {
            FileHandle.standardError.write("FAIL: \(failure)\n".data(using: .utf8)!)
        }
        exit(1)
    }
    print("OK: \(output) is transparent outside the artwork and unchanged over white")
}

let args = Array(CommandLine.arguments.dropFirst())
if args.count == 3, args[0] == "--verify" {
    verify(input: args[1], output: args[2])
} else if args.count == 2, !args[0].hasPrefix("--") {
    generate(input: args[0], output: args[1], threshold: defaultThreshold)
} else if args.count == 4, args[2] == "--threshold", let threshold = Int(args[3]) {
    generate(input: args[0], output: args[1], threshold: threshold)
} else {
    fail("usage: unmatte-white-background.swift <input.png> <output.png> [--threshold N]\n"
        + "       unmatte-white-background.swift --verify <input.png> <output.png>")
}
