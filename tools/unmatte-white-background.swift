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
// F = (C - (1-a)*B) / a. B is sampled from a corner the fill actually seeded
// from, rather than assumed to be pure white: exported art often sits on an
// off-white such as (254,254,254), and assuming 255 leaves the corners a hair
// short of transparent. Background pixels become fully transparent; the soft
// edge keeps its exact coverage, so compositing the result back over B
// reproduces the input.
//
// The flood spreads only through pixels at or above --threshold. The
// threshold has to clear every background pixel while staying above the
// brightest artwork pixel the fill can reach along the edge, so the fill runs
// out of background instead of leaking inside. Sweeping it should show a wide
// plateau where the filled count barely moves; pick from the middle of that
// plateau. A leak is obvious in the reported percentage: it jumps to most of
// the image.
//
// Scope: flat-backdrop artwork with at least one background corner. The tool
// refuses to run when no corner qualifies rather than writing a file that is
// merely opaque-with-an-alpha-channel. Two known limits: the fill is
// hard-thresholded, so the boundary carries a real alpha discontinuity (fine
// where boundary pixels are already dark and saturated, visible as a seam on
// art with a very gentle edge), and the output is written as 8-bit sRGB at
// the default resolution, so dpi and any wide-gamut profile are not carried
// through.
//
// Usage:
//   tools/unmatte-white-background.swift <input.png> <output.png> [--threshold N]
//   tools/unmatte-white-background.swift --verify <input.png> <output.png> [--threshold N]
//
// --verify re-checks a generated file against its source. It re-runs the same
// flood fill on the source and asserts that every pixel the fill reaches is
// non-opaque in the output, that every pixel it does not reach kept the
// source's alpha, that the four corners are fully transparent, and that
// compositing the output back over the sampled backdrop reproduces the
// source. Run it after regenerating to confirm the asset is still correct.

import AppKit

let defaultThreshold = 45
// Round-trip slack: loadBitmap un-premultiplies with integer division, which
// costs up to a count or two on partial-alpha pixels once alpha is reapplied.
let compositeTolerance = 2

struct Bitmap {
    var pixels: [UInt8]  // RGBA, straight (non-premultiplied) alpha
    let width: Int
    let height: Int

    func index(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    func minChannel(_ x: Int, _ y: Int) -> Int {
        let i = index(x, y)
        return min(Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }

    func color(_ x: Int, _ y: Int) -> [Double] {
        let i = index(x, y)
        return (0..<3).map { Double(pixels[i + $0]) }
    }

    /// The four corners, named for diagnostics.
    var corners: [(name: String, x: Int, y: Int)] {
        [("top-left", 0, 0), ("top-right", width - 1, 0),
         ("bottom-left", 0, height - 1), ("bottom-right", width - 1, height - 1)]
    }
}

/// The background region, and the backdrop colour it was measured from.
struct Surround {
    let mask: [Bool]
    let background: [Double]
    let seededAt: String
    let filled: Int
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
/// Returns nil when no corner is background, which means the threshold or the
/// artwork does not match this tool's assumptions.
func findSurround(_ bitmap: Bitmap, threshold: Int) -> Surround? {
    let seeds = bitmap.corners.filter { bitmap.minChannel($0.x, $0.y) >= threshold }
    guard let first = seeds.first else { return nil }

    var mask = [Bool](repeating: false, count: bitmap.width * bitmap.height)
    var stack: [(Int, Int)] = []
    for seed in seeds {
        let cell = seed.y * bitmap.width + seed.x
        if !mask[cell] {
            mask[cell] = true
            stack.append((seed.x, seed.y))
        }
    }
    var filled = stack.count
    while let (x, y) = stack.popLast() {
        for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
            guard nx >= 0, nx < bitmap.width, ny >= 0, ny < bitmap.height else { continue }
            let cell = ny * bitmap.width + nx
            guard !mask[cell], bitmap.minChannel(nx, ny) >= threshold else { continue }
            mask[cell] = true
            filled += 1
            stack.append((nx, ny))
        }
    }
    return Surround(
        mask: mask,
        background: bitmap.color(first.x, first.y),
        seededAt: first.name,
        filled: filled
    )
}

func requireSurround(_ bitmap: Bitmap, threshold: Int, path: String) -> Surround {
    guard let surround = findSurround(bitmap, threshold: threshold) else {
        let seen = bitmap.corners
            .map { "\($0.name)=\(bitmap.minChannel($0.x, $0.y))" }
            .joined(separator: " ")
        fail("no corner of \(path) reaches the --threshold of \(threshold), so there is no "
            + "background to remove (corner min-channel values: \(seen)). This tool expects "
            + "artwork on a flat light backdrop; lower the threshold if the backdrop is darker.")
    }
    return surround
}

/// Replaces the background surround with straight-alpha coverage.
func unmatte(_ bitmap: Bitmap, surround: Surround) -> Bitmap {
    var result = bitmap
    let background = surround.background
    for cell in 0..<surround.mask.count where surround.mask[cell] {
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

func describe(_ background: [Double]) -> String {
    "rgb(" + background.map { String(Int($0)) }.joined(separator: ",") + ")"
}

func generate(input: String, output: String, threshold: Int) {
    let source = loadBitmap(input)
    let surround = requireSurround(source, threshold: threshold, path: input)
    writePNG(unmatte(source, surround: surround), to: output)
    let percent = Double(surround.filled) / Double(source.width * source.height) * 100
    print("wrote \(output) — \(source.width)x\(source.height), backdrop "
        + "\(describe(surround.background)) seeded at \(surround.seededAt), "
        + String(format: "surround %d px (%.1f%% of image)", surround.filled, percent))
}

func verify(input: String, output: String, threshold: Int) {
    let source = loadBitmap(input)
    let result = loadBitmap(output)
    guard source.width == result.width, source.height == result.height else {
        fail("size mismatch: source \(source.width)x\(source.height), "
            + "output \(result.width)x\(result.height)")
    }
    let surround = requireSurround(source, threshold: threshold, path: input)
    var failures: [String] = []

    func note(_ line: String) {
        FileHandle.standardError.write("  \(line)\n".data(using: .utf8)!)
    }
    note("backdrop \(describe(surround.background)) seeded at \(surround.seededAt)")
    note("surround \(surround.filled) px of \(source.width * source.height)")

    for corner in result.corners {
        let alpha = result.pixels[result.index(corner.x, corner.y) + 3]
        note("corner \(corner.name) (\(corner.x),\(corner.y)) alpha=\(alpha)")
        if alpha != 0 {
            failures.append("corner \(corner.name) is not transparent (alpha=\(alpha))")
        }
    }

    // The real assertion: the whole background region must have been cleared,
    // and nothing outside it may have moved.
    var surroundStillOpaque = 0
    var artworkAlphaChanged = 0
    var worst = 0
    var worstAt = (0, 0)
    for y in 0..<result.height {
        for x in 0..<result.width {
            let i = result.index(x, y)
            let alpha = Int(result.pixels[i + 3])
            if surround.mask[y * result.width + x] {
                if alpha == 255 { surroundStillOpaque += 1 }
            } else if alpha != Int(source.pixels[i + 3]) {
                artworkAlphaChanged += 1
            }
            let a = Double(alpha) / 255
            var pixelWorst = 0
            for c in 0..<3 {
                let over = Double(result.pixels[i + c]) * a + surround.background[c] * (1 - a)
                pixelWorst = max(pixelWorst, abs(Int(over.rounded()) - Int(source.pixels[i + c])))
            }
            if pixelWorst > worst {
                worst = pixelWorst
                worstAt = (x, y)
            }
        }
    }
    note("background pixels left opaque: \(surroundStillOpaque)")
    note("artwork pixels whose alpha changed: \(artworkAlphaChanged)")
    note("worst channel difference over the source backdrop: \(worst) at \(worstAt.0),\(worstAt.1)")

    if surroundStillOpaque != 0 {
        failures.append("\(surroundStillOpaque) background pixels are still opaque; "
            + "the surround was not removed")
    }
    if artworkAlphaChanged != 0 {
        failures.append("\(artworkAlphaChanged) pixels outside the background changed alpha; "
            + "the artwork was altered")
    }
    if worst > compositeTolerance {
        failures.append("compositing over the source backdrop does not reproduce the source "
            + "(off by \(worst), tolerance \(compositeTolerance))")
    }

    guard failures.isEmpty else {
        for failure in failures {
            FileHandle.standardError.write("FAIL: \(failure)\n".data(using: .utf8)!)
        }
        exit(1)
    }
    print("OK: \(output) is transparent across the background and unchanged over the backdrop")
}

let usage = """
usage: unmatte-white-background.swift <input.png> <output.png> [--threshold N]
       unmatte-white-background.swift --verify <input.png> <output.png> [--threshold N]
"""

/// Splits a trailing `--threshold N` off the argument list.
func takeThreshold(_ args: [String]) -> ([String], Int) {
    guard args.count >= 2, args[args.count - 2] == "--threshold" else {
        return (args, defaultThreshold)
    }
    guard let value = Int(args[args.count - 1]), (0...255).contains(value) else {
        fail("--threshold takes a number from 0 to 255\n\(usage)")
    }
    return (Array(args.dropLast(2)), value)
}

let (positional, threshold) = takeThreshold(Array(CommandLine.arguments.dropFirst()))
let verifying = positional.first == "--verify"
let paths = verifying ? Array(positional.dropFirst()) : positional

guard paths.count == 2, !paths.contains(where: { $0.hasPrefix("--") }) else {
    fail(usage)
}
if verifying {
    verify(input: paths[0], output: paths[1], threshold: threshold)
} else {
    generate(input: paths[0], output: paths[1], threshold: threshold)
}
