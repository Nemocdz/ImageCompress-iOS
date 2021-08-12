//
//  File.swift
//  
//
//  Created by Nemo on 2021/8/5.
//

import Foundation
import ImageIO

public extension ImageCompress {
    static func orientation(of data: Data) -> CGImagePropertyOrientation? {
        return data.imageOrientation
    }
    
    static func size(of data: Data) -> CGSize {
        return data.imageSize
    }
    
    static func frameCount(of data: Data) -> Int {
        return data.imageFrameCount
    }
    
    static func frameDurations(of data: Data) -> [Double] {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return []
        }
        return imageSource.frameDurations
    }
}


extension Data {
    var imageOrientation: CGImagePropertyOrientation? {
        guard let imageSource = CGImageSourceCreateWithData(self as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [AnyHashable: Any],
              let orientation = (properties[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init)
        else {
            return nil
        }
        return orientation
    }
    
    var imageSize: CGSize {
        guard let imageSource = CGImageSourceCreateWithData(self as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [AnyHashable: Any],
              let imageHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              let imageWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat
        else {
            return .zero
        }
        return CGSize(width: imageWidth, height: imageHeight)
    }
    
    var imageFrameCount: Int {
        guard let imageSource = CGImageSourceCreateWithData(self as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return 0
        }
        return CGImageSourceGetCount(imageSource)
    }
    
    var hasAlpha: Bool {
        guard let imageSource = CGImageSourceCreateWithData(self as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [AnyHashable: Any],
              let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool
        else {
            return false
        }
        return hasAlpha
    }
}

extension CGImageSource {
    func frameDuration(at index: Int) -> Double? {
        var frameDuration: Double = 0.1
        guard let frameProperties = CGImageSourceCopyPropertiesAtIndex(self, index, nil) as? [AnyHashable: Any],
              let gifProperties = frameProperties[kCGImagePropertyGIFDictionary] as? [AnyHashable: Any] else {
            return nil
        }

        if let unclampedDuration = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double {
            frameDuration = unclampedDuration
        } else {
            if let clampedDuration = gifProperties[kCGImagePropertyGIFDelayTime] as? Double {
                frameDuration = clampedDuration
            }
        }

        if frameDuration < 0.011 {
            frameDuration = 0.1
        }

        return frameDuration
    }

    var frameDurations: [Double] {
        let frameCount = CGImageSourceGetCount(self)
        return (0 ..< frameCount).compactMap { frameDuration(at: $0) }
    }
}

