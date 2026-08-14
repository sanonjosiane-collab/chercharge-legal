//
//  ImageDecodeCache.swift
//  Chercharge
//
//  Avoid decoding multi‑MB JPEG/PNG blobs on the main thread inside SwiftUI `body`.
//

import ImageIO
import SwiftUI
import UIKit

enum ImageDecodeCache {
    private static let cache = NSCache<NSString, UIImage>()
    private static let lock = NSLock()

    static func image(for data: Data?, maxPixelSide: CGFloat = 512) -> UIImage? {
        guard let data, !data.isEmpty else { return nil }
        let key = cacheKey(for: data, maxPixelSide: maxPixelSide)
        lock.lock()
        let hit = cache.object(forKey: key)
        lock.unlock()
        if let hit { return hit }

        guard let decoded = decodeDownsampled(data: data, maxPixelSide: maxPixelSide) else {
            return nil
        }
        lock.lock()
        cache.setObject(decoded, forKey: key, cost: data.count)
        lock.unlock()
        return decoded
    }

    /// Decode off the calling thread when you already have a background context.
    static func decodeDownsampled(data: Data, maxPixelSide: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return UIImage(data: data)
        }
        let downsample: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSide),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsample as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    private static func cacheKey(for data: Data, maxPixelSide: CGFloat) -> NSString {
        // Stable enough for session-length caching without hashing entire blobs.
        "\(data.count)-\(data.prefix(64).hashValue)-\(Int(maxPixelSide))" as NSString
    }
}

/// SwiftUI helper: shows a cached/downsampled image for binary photo data.
struct CachedDataImage: View {
    let data: Data?
    var maxPixelSide: CGFloat = 512
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let uiImage = ImageDecodeCache.image(for: data, maxPixelSide: maxPixelSide) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
    }
}
