#!/usr/bin/env swift
//
// mask-icon.swift — apply Apple's continuous-corner squircle to app icon art.
//
// Takes a 1024x1024 source PNG with no pre-applied mask and produces a
// 1024x1024 PNG master: the source scaled/cropped to 824x824, clipped with
// SwiftUI's RoundedRectangle(cornerRadius: 185.4, style: .continuous) (the
// real macOS icon corner, not a circular-arc rounded rect), and centered on a
// transparent 1024x1024 canvas — the standard macOS icon inset.
//
// Usage:
//   swift macos/mask-icon.swift <input-1024.png> <output-1024-masked.png>
//
// Invoked by macos/generate-icon.sh; not meant to be run standalone except
// for debugging.

import AppKit
import SwiftUI

let canvas: CGFloat = 1024
let artSize: CGFloat = 824
let iconCornerRadius: CGFloat = 185.4

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("usage: mask-icon.swift <input.png> <output.png>\n".data(using: .utf8)!)
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard let sourceImage = NSImage(contentsOfFile: inputPath) else {
    FileHandle.standardError.write("could not load \(inputPath)\n".data(using: .utf8)!)
    exit(1)
}

struct MaskedIcon: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: artSize, height: artSize)
            .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
            .frame(width: canvas, height: canvas)
    }
}

@MainActor
func renderMaskedIcon() -> CGImage? {
    let renderer = ImageRenderer(content: MaskedIcon(image: sourceImage))
    renderer.scale = 1.0
    return renderer.cgImage
}

guard let cgImage = MainActor.assumeIsolated({ renderMaskedIcon() }) else {
    FileHandle.standardError.write("failed to render masked icon\n".data(using: .utf8)!)
    exit(1)
}

let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    FileHandle.standardError.write("failed to write \(outputPath): \(error)\n".data(using: .utf8)!)
    exit(1)
}
