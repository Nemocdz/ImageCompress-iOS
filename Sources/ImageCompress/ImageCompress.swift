//
//  ImageCompress.swift
//  ImageCompress
//
//  Created by Nemo on 2019/1/15.
//  Copyright © 2019 nemocdz. All rights reserved.
//

import Foundation
import ImageIO

public enum ImageCompress {
}

public extension ImageCompress {
    enum ColorConfig: CaseIterable {
        case alpha8
        case rgb565
        case argb8888
        case rgbaF16
        case unknown // 其余色彩配置
    }
}

public extension ImageCompress {
    enum CompressError: Error {
        case imageIOError(ImageIOError)
        case illegalFormat
        case illegalColorConfig
        case illegalLimitLongWidth(width: CGFloat)
    }
}

public extension ImageCompress.CompressError {
    enum ImageIOError {
        case cgImageCreateFail
        case thumbnailCreateFail(index: Int)
        case sourceCreateFail
        case destinationCreateFail
        case destinationFinishFail
    }
}

public extension ImageCompress {
    /// 改变图片到指定的色彩配置
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - config: 色彩配置
    /// - Returns: 处理后数据
    static func changeColor(of rawData: Data, config: ColorConfig) throws -> Data {
        guard rawData.imageFormat != .unknown else {
            throw CompressError.illegalFormat
        }
        
        guard let imageConfig = config.imageConfig else {
            throw CompressError.illegalFormat
        }
    
        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let writeData = CFDataCreateMutable(nil, 0),
              let imageType = CGImageSourceGetType(imageSource) else {
            throw CompressError.imageIOError(.sourceCreateFail)
        }
        
        guard let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, 1, nil) else {
            throw CompressError.imageIOError(.destinationCreateFail)
        }
        
        guard let rawDataProvider = CGDataProvider(data: rawData as CFData),
              let imageFrame = CGImage(width: Int(rawData.imageSize.width),
                                       height: Int(rawData.imageSize.height),
                                       bitsPerComponent: imageConfig.bitsPerComponent,
                                       bitsPerPixel: imageConfig.bitsPerPixel,
                                       bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: imageConfig.bitmapInfo,
                                       provider: rawDataProvider,
                                       decode: nil,
                                       shouldInterpolate: true,
                                       intent: .defaultIntent)
        else {
            throw CompressError.imageIOError(.cgImageCreateFail)
        }
        
        CGImageDestinationAddImage(imageDestination, imageFrame, nil)
        
        guard CGImageDestinationFinalize(imageDestination) else {
            throw CompressError.imageIOError(.destinationFinishFail)
        }
        return writeData as Data
    }

    /// 获取图片的色彩配置
    ///
    /// - Parameter rawData: 原始图片数据
    /// - Returns: 色彩配置
    static func colorConfig(of rawData: Data) -> ColorConfig {
        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let imageFrame = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return .unknown
        }
        
        return imageFrame.colorConfig
    }

    /// 同步压缩图片数据长边到指定数值
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - limitLongWidth: 长边限制
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData: Data, limitLongWidth: CGFloat) throws -> Data {
        guard rawData.imageFormat != .unknown else {
            throw CompressError.illegalFormat
        }

        guard limitLongWidth > 0 else {
            throw CompressError.illegalLimitLongWidth(width: limitLongWidth)
        }
        
        guard max(rawData.imageSize.height, rawData.imageSize.width) > limitLongWidth else {
            return rawData
        }

        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let writeData = CFDataCreateMutable(nil, 0),
              let imageType = CGImageSourceGetType(imageSource) else {
            throw CompressError.imageIOError(.sourceCreateFail)
        }

        let frameCount = CGImageSourceGetCount(imageSource)

        guard let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, frameCount, nil) else {
            throw CompressError.imageIOError(.destinationCreateFail)
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
                throw CompressError.imageIOError(.thumbnailCreateFail(index: 0))
            }
            
            CGImageDestinationAddImage(imageDestination, resizedImageFrame, nil)
        }

        guard CGImageDestinationFinalize(imageDestination) else {
            throw CompressError.imageIOError(.destinationFinishFail)
        }

        return writeData as Data
    }

    /// 同步压缩图片到指定文件大小
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - limitDataSize: 限制文件大小，单位字节
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData: Data, limitDataSize: Int) throws -> Data {
        guard rawData.imageFormat != .unknown else {
            throw CompressError.illegalFormat
        }
        
        guard rawData.count > limitDataSize else {
            return rawData
        }

        var resultData = rawData

        // 若是 JPG，先用压缩系数压缩 6 次，二分法
        if resultData.imageFormat == .jpg {
            var compression: Double = 1
            var maxCompression: Double = 1
            var minCompression: Double = 0
            for _ in 0 ..< 6 {
                compression = (maxCompression + minCompression) / 2
                resultData = try compressImageData(resultData, compression: compression)
                if resultData.count < Int(CGFloat(limitDataSize) * 0.9) {
                    minCompression = compression
                } else if resultData.count > limitDataSize {
                    maxCompression = compression
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
            let sampleCount = resultData.fitSampleCount
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
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData: Data, sampleCount: Int) throws -> Data {
        guard rawData.imageFormat == .gif else {
            throw CompressError.illegalFormat
        }
        
        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let writeData = CFDataCreateMutable(nil, 0),
              let imageType = CGImageSourceGetType(imageSource) else {
            throw CompressError.imageIOError(.sourceCreateFail)
        }

        // 计算帧的间隔
        let frameDurations = imageSource.frameDurations

        // 合并帧的时间,最长不可高于 200ms
        let mergeFrameDurations = (0 ..< frameDurations.count).filter { $0 % sampleCount == 0 }.map { min(frameDurations[$0 ..< min($0 + sampleCount, frameDurations.count)].reduce(0.0) { $0 + $1 }, 0.2) }

        // 抽取帧 每 n 帧使用 1 帧
        let sampleImageFrames = (0 ..< frameDurations.count).filter { $0 % sampleCount == 0 }.compactMap { CGImageSourceCreateImageAtIndex(imageSource, $0, nil) }

        guard let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, sampleImageFrames.count, nil) else {
            throw CompressError.imageIOError(.destinationCreateFail)
        }

        // 每一帧图片都进行重新编码
        zip(sampleImageFrames, mergeFrameDurations).forEach {
            // 设置帧间隔
            let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: $1, kCGImagePropertyGIFUnclampedDelayTime: $1]]
            CGImageDestinationAddImage(imageDestination, $0, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(imageDestination) else {
            throw CompressError.imageIOError(.destinationFinishFail)
        }

        return writeData as Data
    }

    /// 同步压缩图片到指定压缩系数，仅支持 JPG
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - compression: 压缩系数
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData: Data, compression: Double) throws -> Data {
        guard rawData.imageFormat == .jpg else {
            return rawData
        }
        
        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let writeData = CFDataCreateMutable(nil, 0),
              let imageType = CGImageSourceGetType(imageSource) else {
            throw CompressError.imageIOError(.sourceCreateFail)
        }
        
        guard let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, 1, nil) else {
            throw CompressError.imageIOError(.destinationCreateFail)
        }

        let frameProperties = [kCGImageDestinationLossyCompressionQuality: compression] as CFDictionary
        CGImageDestinationAddImageFromSource(imageDestination, imageSource, 0, frameProperties)
        
        guard CGImageDestinationFinalize(imageDestination) else {
            throw CompressError.imageIOError(.destinationFinishFail)
        }
        
        return writeData as Data
    }
}


extension ImageCompress {
    enum ImageFormat {
        case jpg
        case png
        case gif
        case unknown
    }
}

extension Data {
    var frameCount: Int {
        guard let imageSource = CGImageSourceCreateWithData(self as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return 1
        }

        return CGImageSourceGetCount(imageSource)
    }
    
    var fitSampleCount: Int {
        var sampleCount = 1
        switch frameCount {
        case 2 ..< 8:
            sampleCount = 2
        case 8 ..< 20:
            sampleCount = 3
        case 20 ..< 30:
            sampleCount = 4
        case 30 ..< 40:
            sampleCount = 5
        case 40 ..< Int.max:
            sampleCount = 6
        default: break
        }

        return sampleCount
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

    var imageFormat: ImageCompress.ImageFormat {
        var headerData = [UInt8](repeating: 0, count: 3)
        copyBytes(to: &headerData, from: 0 ..< 3)
        let hexString = headerData.reduce("") { $0 + String($1 & 0xFF, radix: 16) }.uppercased()
        var imageFormat = ImageCompress.ImageFormat.unknown
        switch hexString {
        case "FFD8FF":
            imageFormat = .jpg
        case "89504E":
            imageFormat = .png
        case "474946":
            imageFormat = .gif
        default: break
        }
        return imageFormat
    }
}

extension CGImageSource {
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

extension ImageCompress.ColorConfig {
    struct CGImageConfig {
        let bitsPerComponent: Int
        let bitsPerPixel: Int
        let bitmapInfo: CGBitmapInfo
    }

    var imageConfig: CGImageConfig? {
        switch self {
        case .alpha8:
            return CGImageConfig(bitsPerComponent: 8, bitsPerPixel: 8, bitmapInfo: CGBitmapInfo(.alphaOnly))
        case .rgb565:
            return CGImageConfig(bitsPerComponent: 5, bitsPerPixel: 16, bitmapInfo: CGBitmapInfo(.noneSkipFirst))
        case .argb8888:
            return CGImageConfig(bitsPerComponent: 8, bitsPerPixel: 32, bitmapInfo: CGBitmapInfo(.premultipliedFirst))
        case .rgbaF16:
            return CGImageConfig(bitsPerComponent: 16, bitsPerPixel: 64, bitmapInfo: CGBitmapInfo(.premultipliedLast, true))
        case .unknown:
            return nil
        }
    }
}

extension CGBitmapInfo {
    init(_ alphaInfo: CGImageAlphaInfo, _ isFloatComponents: Bool = false) {
        var array = [
            CGBitmapInfo(rawValue: alphaInfo.rawValue),
            CGBitmapInfo(rawValue: CGImageByteOrderInfo.orderDefault.rawValue),
        ]

        if isFloatComponents {
            array.append(.floatComponents)
        }

        self.init(array)
    }
}

extension CGImage {
    var colorConfig: ImageCompress.ColorConfig {
        return ImageCompress.ColorConfig.allCases.first(where: { isColorConfig($0) }) ?? .unknown
    }

    func isColorConfig(_ colorConfig: ImageCompress.ColorConfig) -> Bool {
        guard let imageConfig = colorConfig.imageConfig else {
            return false
        }

        if bitsPerComponent == imageConfig.bitsPerComponent,
           bitsPerPixel == imageConfig.bitsPerPixel,
           imageConfig.bitmapInfo.contains(CGBitmapInfo(alphaInfo)),
           imageConfig.bitmapInfo.contains(.floatComponents)
        {
            return true
        } else {
            return false
        }
    }
}
