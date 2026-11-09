import AppKit
import Foundation

/// TIFF verisini PNG'ye donusturur (B-8.3.9).
public enum ImageTranscoder {
    public static func tiffToPNG(_ tiffData: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: tiffData) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
