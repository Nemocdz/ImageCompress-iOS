//
//  ImageCompress.swift
//  ImageCompress
//
//  Created by Nemo on 2019/1/15.
//  Copyright © 2019 nemocdz. All rights reserved.
//

import Foundation
import ImageIO

public enum ImageCompress {}

public extension ImageCompress {
    enum Error: Swift.Error {
        case imageIOError(ImageIOError)
        case unsupportedFormat
        case unsupportedColorConfig
        case illegalLongWidth(width: CGFloat)
        case illegalQuality(quality: CGFloat)
    }
}

public extension ImageCompress.Error {
    enum ImageIOError {
        case cgImageMissing(index: Int)
        case thumbnailMissing(index: Int)
        case sourceMissing
        case destinationMissing(type: String)
        case destinationFinalizeFail
    }
}

public extension ImageCompress {
    /// 同步压缩图片数据长边到指定数值
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - limitLongWidth: 长边限制
    /// - Throws: ImageCompress.Error
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData: Data, limitLongWidth: CGFloat) throws -> Data {
        guard rawData.imageFormat != nil else {
            throw Error.unsupportedFormat
        }

        guard limitLongWidth > 0 else {
            throw Error.illegalLongWidth(width: limitLongWidth)
        }

        guard max(rawData.imageSize.height, rawData.imageSize.width) > limitLongWidth else {
            return rawData
        }

        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let writeData = CFDataCreateMutable(nil, 0),
              let imageType = CGImageSourceGetType(imageSource)
        else {
            throw Error.imageIOError(.sourceMissing)
        }

        let frameCount = CGImageSourceGetCount(imageSource)

        guard let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, frameCount, nil) else {
            throw Error.imageIOError(.destinationMissing(type: imageType as String))
        }

        // 设置缩略图参数，kCGImageSourceThumbnailMaxPixelSize 为生成缩略图的大小。当设置为 800，如果图片本身大于 800*600，则生成后图片大小为 800*600，如果源图片为 700*500，则生成图片为 800*500
        let options = [kCGImageSourceThumbnailMaxPixelSize: limitLongWidth, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true, kCGImageSourceCreateThumbnailFromImageAlways: true] as CFDictionary

        if frameCount > 1 {
            // 计算帧的间隔
            let frameDurations = imageSource.frameDurations

            // 每一帧都进行缩放
            let resizedImageFrames = (0 ..< frameCount).compactMap { CGImageSourceCreateThumbnailAtIndex(imageSource, $0, options) }

            // 每一帧都进行重新编码
            zip(resizedImageFrames, frameDurations).forEach {
                // 设置帧间隔
                let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: $1, kCGImagePropertyGIFUnclampedDelayTime: $1]]
                CGImageDestinationAddImage(imageDestination, $0, frameProperties as CFDictionary)
            }
        } else {
            guard let resizedImageFrame = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
                throw Error.imageIOError(.thumbnailMissing(index: 0))
            }

            CGImageDestinationAddImage(imageDestination, resizedImageFrame, nil)
        }

        guard CGImageDestinationFinalize(imageDestination) else {
            throw Error.imageIOError(.destinationFinalizeFail)
        }

        return writeData as Data
    }

    /// 同步压缩图片到指定文件大小
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - limitDataSize: 限制文件大小，单位字节
    /// - Throws: ImageCompress.Error
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData: Data, limitDataSize: Int) throws -> Data {
        guard rawData.imageFormat != nil else {
            throw Error.unsupportedFormat
        }

        guard rawData.count > limitDataSize else {
            return rawData
        }

        // 若有 DPI，先设置 DPI 为默认值
        var resultData = try changeDPI(of: rawData)

        // 若是 JPEG/HEIC，先用压缩系数压缩 6 次，二分法
        if isSupportQualityCompression(of: rawData) {
            var quality: CGFloat = 1
            var maxQuality: CGFloat = 1
            var minQuality: CGFloat = 0
            for _ in 0 ..< 6 {
                quality = (maxQuality + minQuality) / 2
                resultData = try compressImageData(resultData, quality: quality)
                if resultData.count < Int(CGFloat(limitDataSize) * 0.9) {
                    minQuality = quality
                } else if resultData.count > limitDataSize {
                    maxQuality = quality
                } else {
                    break
                }
            }
            if resultData.count <= limitDataSize {
                return resultData
            }
        }

        // 若是 GIF，先用抽帧减少大小
        if resultData.imageFormat == .gif {
            let sampleCount = fitSampleCount(of: resultData.imageFrameCount)
            resultData = try compressImageData(resultData, sampleCount: sampleCount)
            if resultData.count <= limitDataSize {
                return resultData
            }
        }

        var longWidth = max(resultData.imageSize.height, resultData.imageSize.width)
        // 图片尺寸按比率缩小，比率按字节比例逼近
        while resultData.count > limitDataSize {
            let ratio = sqrt(CGFloat(limitDataSize) / CGFloat(resultData.count))
            longWidth *= ratio
            resultData = try compressImageData(resultData, limitLongWidth: longWidth)
        }
        return resultData
    }

    /// 同步压缩图片抽取帧数，仅支持 GIF
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - sampleCount: 采样频率，比如 3 则每三张用第一张，然后延长时间
    /// - Throws: ImageCompress.Error
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData: Data, sampleCount: Int) throws -> Data {
        guard rawData.imageFormat == .gif else {
            throw Error.unsupportedFormat
        }

        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let writeData = CFDataCreateMutable(nil, 0),
              let imageType = CGImageSourceGetType(imageSource)
        else {
            throw Error.imageIOError(.sourceMissing)
        }

        // 计算帧的间隔
        let frameDurations = imageSource.frameDurations

        // 合并帧的时间,最长不可高于 200ms
        let mergeFrameDurations = (0 ..< frameDurations.count)
            .filter { $0 % sampleCount == 0 }
            .map { min(frameDurations[$0 ..< min($0 + sampleCount, frameDurations.count)]
                    .reduce(0.0) { $0 + $1 }, 0.2) }

        // 抽取帧，每 n 帧使用 1 帧
        let sampleImageFrames: [CGImage] = try (0 ..< frameDurations.count)
            .filter { $0 % sampleCount == 0 }
            .enumerated()
            .map {
                guard let imageFrame = CGImageSourceCreateImageAtIndex(imageSource, $0.element, nil) else {
                    throw Error.imageIOError(.cgImageMissing(index: $0.offset))
                }
                return imageFrame
            }

        guard let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, sampleImageFrames.count, nil) else {
            throw Error.imageIOError(.destinationFinalizeFail)
        }

        // 每一帧图片都进行重新编码
        zip(sampleImageFrames, mergeFrameDurations).forEach {
            // 设置帧间隔
            let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: $1, kCGImagePropertyGIFUnclampedDelayTime: $1]]
            CGImageDestinationAddImage(imageDestination, $0, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(imageDestination) else {
            throw Error.imageIOError(.destinationFinalizeFail)
        }

        return writeData as Data
    }

    /// 同步压缩图片到指定压缩系数，仅支持 JPEG/HEIC
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - quality: 压缩系数
    /// - Throws: ImageCompress.Error
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData: Data, quality: CGFloat) throws -> Data {
        guard isSupportQualityCompression(of: rawData) else {
            throw Error.unsupportedFormat
        }

        guard quality >= 0, quality <= 1.0 else {
            throw Error.illegalQuality(quality: quality)
        }

        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let writeData = CFDataCreateMutable(nil, 0),
              let imageType = CGImageSourceGetType(imageSource)
        else {
            throw Error.imageIOError(.sourceMissing)
        }

        guard let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, 1, nil) else {
            throw Error.imageIOError(.destinationMissing(type: imageType as String))
        }

        let frameProperties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImageFromSource(imageDestination, imageSource, 0, frameProperties)

        guard CGImageDestinationFinalize(imageDestination) else {
            throw Error.imageIOError(.destinationFinalizeFail)
        }

        return writeData as Data
    }
}

extension ImageCompress {
    static func isSupportQualityCompression(of data: Data) -> Bool {
        guard let imageFormat = data.imageFormat else { return false }
        var supportedFormats: Set<ImageFormat> = [.jpeg]
        if isHeicSupported {
            supportedFormats.insert(.heic)
        }
        return supportedFormats.contains(imageFormat)
    }

    static var isHeicSupported: Bool {
        guard let uniformTypeIdentifers = CGImageDestinationCopyTypeIdentifiers() as? [String] else {
            return false
        }
        return uniformTypeIdentifers.contains(ImageFormat.heic.uniformTypeIdentifer)
    }

    static func fitSampleCount(of frameCount: Int) -> Int {
        switch frameCount {
        case 2 ..< 8:
            return 2
        case 8 ..< 20:
            return 3
        case 20 ..< 30:
            return 4
        case 30 ..< 40:
            return 5
        case 40 ..< Int.max:
            return 6
        default:
            return 1
        }
    }
}

extension Data {
    var imageFrameCount: Int {
        guard let imageSource = CGImageSourceCreateWithData(self as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return 1
        }

        return CGImageSourceGetCount(imageSource)
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
}

fileprivate extension CGImageSource {
    func frameDuration(at index: Int) -> Double {
        var frameDuration = Double(0.1)
        guard let frameProperties = CGImageSourceCopyPropertiesAtIndex(self, index, nil) as? [AnyHashable: Any], let gifProperties = frameProperties[kCGImagePropertyGIFDictionary] as? [AnyHashable: Any] else {
            return frameDuration
        }

        if let unclampedDuration = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber {
            frameDuration = unclampedDuration.doubleValue
        } else {
            if let clampedDuration = gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber {
                frameDuration = clampedDuration.doubleValue
            }
        }

        if frameDuration < 0.011 {
            frameDuration = 0.1
        }

        return frameDuration
    }

    var frameDurations: [Double] {
        let frameCount = CGImageSourceGetCount(self)
        return (0 ..< frameCount).map { frameDuration(at: $0) }
    }
}
