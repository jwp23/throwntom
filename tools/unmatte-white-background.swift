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
// plateau. A leak shows up as the share of the image the fill claims, which
// jumps to about half or more, and --max-surround makes that a hard limit
// rather than a number someone has to notice. That limit is the only thing
// that can catch a leak: re-running the fill checks a mask against itself, and
// a leaked mask is still perfectly self-consistent.
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
//   tools/unmatte-white-background.swift <in.png> <out.png> [--threshold N] [--max-surround PERCENT]
//   tools/unmatte-white-background.swift --verify <in.png> <out.png> [--threshold N] [--max-surround PERCENT]
//
// --verify re-checks a generated file against its source. It re-runs the same
// flood fill on the source and asserts that every pixel the fill reaches is
// non-opaque in the output, that every pixel it does not reach is byte-identical
// to the source, that the four corners are fully transparent, and that
// compositing the output back over the sampled backdrop reproduces the source.
// Artwork is held to exact equality; the composite tolerance covers only the
// partial-alpha edge. Verify with the same --threshold used to generate, since
// a different one recomputes a different region. Run it after regenerating to
// confirm the asset is still correct.

import AppKit

let defaultThreshold = 45
// The share of the image the background may claim before the fill is treated
// as having leaked. Flat-backdrop art surrounds a subject; a fill that has
// burst into the interior takes about half the image or more, so the gap
// between a sane fill and a leaked one is wide enough to sit a limit in.
let defaultMaxSurround = 0.25
// Round-trip slack: loadBitmap un-premultiplies with integer division, which
// costs up to a count or two on partial-alpha pixels once alpha is reapplied.
// It applies to partial-alpha pixels only; artwork is checked for exact equality.
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

func requireSurround(_ bitmap: Bitmap, threshold: Int, maxFraction: Double, path: String) -> Surround {
    guard let surround = findSurround(bitmap, threshold: threshold) else {
        let seen = bitmap.corners
            .map { "\($0.name)=\(bitmap.minChannel($0.x, $0.y))" }
            .joined(separator: " ")
        fail("no corner of \(path) reaches the --threshold of \(threshold), so there is no "
            + "background to remove (corner min-channel values: \(seen)). This tool expects "
            + "artwork on a flat light backdrop; lower the threshold if the backdrop is darker.")
    }
    // A fill that escaped through the edge of the art swallows the interior and
    // is still perfectly self-consistent, so its own mask cannot catch it. Only
    // the share of the image it claims gives it away.
    let fraction = Double(surround.filled) / Double(bitmap.width * bitmap.height)
    if fraction > maxFraction {
        fail(String(
            format: "the fill claimed %.1f%% of %@, over the --max-surround limit of %.1f%%. "
                + "A --threshold of %d has almost certainly leaked through the artwork's edge "
                + "into its interior. Sweep the threshold and pick from the plateau where the "
                + "claimed share barely moves, or raise --max-surround if this art really is "
                + "mostly background.",
            fraction * 100, path, maxFraction * 100, threshold
        ))
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

func generate(input: String, output: String, settings: Options) {
    let source = loadBitmap(input)
    let surround = requireSurround(
        source, threshold: settings.threshold, maxFraction: settings.maxSurround, path: input
    )
    writePNG(unmatte(source, surround: surround), to: output)
    let percent = Double(surround.filled) / Double(source.width * source.height) * 100
    print("wrote \(output) — \(source.width)x\(source.height), backdrop "
        + "\(describe(surround.background)) seeded at \(surround.seededAt), "
        + String(format: "surround %d px (%.1f%% of image)", surround.filled, percent))
}

func verify(input: String, output: String, settings: Options) {
    let source = loadBitmap(input)
    let result = loadBitmap(output)
    guard source.width == result.width, source.height == result.height else {
        fail("size mismatch: source \(source.width)x\(source.height), "
            + "output \(result.width)x\(result.height)")
    }
    let surround = requireSurround(
        source, threshold: settings.threshold, maxFraction: settings.maxSurround, path: input
    )
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
    // and nothing outside it may have moved. Artwork is held to exact equality,
    // not the composite tolerance — the tolerance exists only to absorb the
    // un-premultiply round-trip on partial-alpha pixels, which artwork pixels
    // left untouched do not have.
    //
    // A surround pixel is checked against its expected alpha, not just against
    // 255: a pixel left a hair below fully opaque (alpha 254, source RGB
    // unchanged) would pass a bare alpha != 255 check while still rendering as
    // near-opaque background, and would separately pass the composite check
    // below too, since a near-white pixel composited at alpha ~1 over a white
    // backdrop reproduces the source almost exactly either way.
    let expected = unmatte(source, surround: surround)
    var surroundAlphaMismatch = 0
    var artworkChanged = 0
    var worst = 0
    var worstAt = (0, 0)
    for y in 0..<result.height {
        for x in 0..<result.width {
            let i = result.index(x, y)
            let alpha = Int(result.pixels[i + 3])
            if surround.mask[y * result.width + x] {
                let expectedAlpha = Int(expected.pixels[i + 3])
                if abs(alpha - expectedAlpha) > compositeTolerance { surroundAlphaMismatch += 1 }
            } else if (0..<4).contains(where: { result.pixels[i + $0] != source.pixels[i + $0] }) {
                artworkChanged += 1
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
    note("background pixels not at expected alpha: \(surroundAlphaMismatch)")
    note("artwork pixels changed: \(artworkChanged)")
    note("worst channel difference over the source backdrop: \(worst) at \(worstAt.0),\(worstAt.1)")

    if surroundAlphaMismatch != 0 {
        failures.append("\(surroundAlphaMismatch) background pixels are not at the expected alpha; "
            + "the surround was not removed")
    }
    if artworkChanged != 0 {
        failures.append("\(artworkChanged) pixels outside the background differ from the source; "
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

let options = "[--threshold N] [--max-surround PERCENT]"
let usage = """
usage: unmatte-white-background.swift <input.png> <output.png> \(options)
       unmatte-white-background.swift --verify <input.png> <output.png> \(options)

Verify with the same --threshold the file was generated with; a different one
recomputes a different background region and reports a spurious mismatch.
"""

struct Options {
    var threshold = defaultThreshold
    var maxSurround = defaultMaxSurround
}

/// Splits trailing `--key value` options off the argument list.
func takeOptions(_ args: [String]) -> ([String], Options) {
    var rest = args
    var options = Options()
    while rest.count >= 2 {
        let key = rest[rest.count - 2]
        let raw = rest[rest.count - 1]
        switch key {
        case "--threshold":
            guard let value = Int(raw), (0...255).contains(value) else {
                fail("--threshold takes a number from 0 to 255\n\(usage)")
            }
            options.threshold = value
        case "--max-surround":
            guard let value = Double(raw), value > 0, value <= 100 else {
                fail("--max-surround takes a percentage above 0 and up to 100\n\(usage)")
            }
            options.maxSurround = value / 100
        default:
            return (rest, options)
        }
        rest = Array(rest.dropLast(2))
    }
    return (rest, options)
}

let (positional, settings) = takeOptions(Array(CommandLine.arguments.dropFirst()))
let verifying = positional.first == "--verify"
let paths = verifying ? Array(positional.dropFirst()) : positional

guard paths.count == 2, !paths.contains(where: { $0.hasPrefix("--") }) else {
    fail(usage)
}
if verifying {
    verify(input: paths[0], output: paths[1], settings: settings)
} else {
    generate(input: paths[0], output: paths[1], settings: settings)
}
