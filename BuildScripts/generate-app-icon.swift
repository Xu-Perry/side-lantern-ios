#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Redraw the SideLantern Windows tray mark as opaque, scalable iOS artwork.
let root = URL(fileURLWithPath:CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("Limelight/Images.xcassets/AppIcon.appiconset")
let contentsURL = catalog.appendingPathComponent("Contents.json")
var contents = try JSONSerialization.jsonObject(with:Data(contentsOf:contentsURL)) as! [String:Any]
var entries = contents["images"] as! [[String:String]]

func writeIcon(pixels:Int, filename:String) throws {
    let context = CGContext(data:nil, width:pixels, height:pixels, bitsPerComponent:8, bytesPerRow:pixels * 4,
        space:CGColorSpaceCreateDeviceRGB(), bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.scaleBy(x:CGFloat(pixels) / 32, y:CGFloat(pixels) / 32)
    context.setFillColor(CGColor(red:36 / 255, green:87 / 255, blue:66 / 255, alpha:1))
    context.fill(CGRect(x:0, y:0, width:32, height:32))
    context.setFillColor(CGColor(red:235 / 255, green:250 / 255, blue:233 / 255, alpha:1))
    // Core Graphics uses a bottom-left origin; these match the original 32 px mark.
    context.fill(CGRect(x:13, y:21, width:6, height:4))
    context.addRect(CGRect(x:10, y:11, width:12, height:10))
    context.addRect(CGRect(x:13, y:13, width:6, height:6))
    context.drawPath(using:.eoFill)
    context.fill(CGRect(x:9, y:7, width:14, height:3))
    let destination = CGImageDestinationCreateWithURL(catalog.appendingPathComponent(filename) as CFURL,
        UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain:"SideLanternIcon", code:1, userInfo:[NSLocalizedDescriptionKey:filename])
    }
}

for index in entries.indices {
    let entry = entries[index]
    let size = Double(entry["size"]!.split(separator:"x")[0])!
    let scale = Double(entry["scale"]!.dropLast())!
    let filename = entry["filename"] ?? "SideLantern-\(Int(size * scale)).png"
    entries[index]["filename"] = filename
    try writeIcon(pixels:Int(size * scale), filename:filename)
}
contents["images"] = entries
try JSONSerialization.data(withJSONObject:contents, options:[.prettyPrinted, .sortedKeys]).write(to:contentsURL)
print("Generated SideLantern app icons for all \(entries.count) catalog slots.")
