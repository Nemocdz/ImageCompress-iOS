//
//  File.swift
//
//
//  Created by Nemo on 2021/9/3.
//

import Foundation
import ImageIO

public extension ImageCompress {
    static func build(of data: Data) throws -> Builder {
        try Builder(data: data)
    }
}

public extension ImageCompress {
    final class Builder {
        let data: Data
        let inputFormat: ImageFormat
        var outputFormat: ImageFormat
        var frameProperties = [CFString: Any]()
        var compressType = CompressType.none
        var sampleCount: Int?
        
        init(data: Data) throws {
            guard let format = data.imageFormat else {
                throw Error.unsupportedFormat
            }
            self.inputFormat = format
            self.outputFormat = format
            self.data = data
        }
    }
}

extension ImageCompress.Builder {
    enum CompressType {
        case size(Int)
        case width(CGFloat)
        case none
    }
}

extension ImageCompress.Builder {
    var quality: CGFloat? {
        frameProperties[kCGImageDestinationLossyCompressionQuality] as? CGFloat
    }
    
    var dpi: CGSize? {
        guard let width = frameProperties[kCGImagePropertyDPIWidth] as? CGFloat,
              let height = frameProperties[kCGImagePropertyDPIHeight] as? CGFloat
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}

public extension ImageCompress.Builder {
    typealias Error = ImageCompress.Error
    typealias Builder = ImageCompress.Builder
    typealias ImageFormat = ImageCompress.ImageFormat
    
    func set(limitLongWidth: CGFloat) throws -> Builder {
        guard limitLongWidth > 0 else {
            throw Error.illegalLongWidth(width: limitLongWidth)
        }
        if max(data.imageSize.height, data.imageSize.width) > limitLongWidth, case .none = compressType {
            compressType = .width(limitLongWidth)
        }
        return self
    }
    
    func set(quality: CGFloat) throws -> Builder {
        guard Self.isSupportQualityCompression(of: inputFormat) else {
            throw Error.unsupportedFormat
        }
        guard quality >= 0, quality <= 1.0 else {
            throw Error.illegalQuality(quality: quality)
        }
        frameProperties[kCGImageDestinationLossyCompressionQuality] = quality
        return self
    }
    
    func set(sampleCount: Int) throws -> Builder {
        guard Self.isSupportSampleCount(of: inputFormat) else {
            throw Error.unsupportedFormat
        }
        guard sampleCount > 0 else {
            throw Error.illegalSampleCount(count: sampleCount)
        }
        self.sampleCount = sampleCount
        return self
    }
    
    func set(format: ImageFormat) throws -> Builder {
        guard Self.isSupportWrite(of: format) else {
            throw Error.unsupportedFormat
        }
        outputFormat = format
        return self
    }
    
    func set(dpi: CGSize) throws -> Builder {
        guard Self.isSupportDPI(of: inputFormat) else {
            throw Error.unsupportedFormat
        }
        guard let originDPI = data.imageDPI, originDPI != dpi else {
            return self
        }
        frameProperties[kCGImagePropertyDPIWidth] = dpi.width
        frameProperties[kCGImagePropertyDPIHeight] = dpi.height
        return self
    }
    
    func set(limitSize: Int) -> Builder {
        if data.count > limitSize, case .none = compressType {
            compressType = .size(limitSize)
        }
        return self
    }
    
    func finalize() throws -> Data {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let writeData = CFDataCreateMutable(nil, 0)
        else {
            throw Error.imageIOError(.sourceMissing)
        }
        
        let frameCount = CGImageSourceGetCount(imageSource)

        guard let imageDestination = CGImageDestinationCreateWithData(writeData, outputFormat.uniformTypeIdentifer as CFString, frameCount, nil) else {
            throw Error.imageIOError(.destinationMissing(type: outputFormat.uniformTypeIdentifer))
        }
        
        func addImage(thumbnailOptions: CFDictionary? = nil) throws {
            let sampleCount = sampleCount ?? 1
            
            if frameCount > 1 {
                // 计算帧的间隔
                let originFrameDurations = imageSource.frameDurations

                // 合并帧的时间,最长不可高于 200ms
                let targetFrameDurations: [Double]
                if sampleCount > 1 {
                    targetFrameDurations = (0 ..< frameCount)
                        .filter { $0 % sampleCount == 0 }
                        .map { min(originFrameDurations[$0 ..< min($0 + sampleCount, frameCount)]
                                .reduce(0.0) { $0 + $1 }, 0.2) }
                } else {
                    targetFrameDurations = originFrameDurations
                }

                // 抽取帧，每 n 帧使用 1 帧
                let targetIndexs = (0 ..< frameCount).filter { $0 % sampleCount == 0 }
                
                try targetIndexs.enumerated().forEach {
                    // 计算帧的间隔和缩放
                    let duration = targetFrameDurations[$0.offset]
                    let index = $0.element
                    
                    func imageFrame() throws -> CGImage {
                        if let options = thumbnailOptions,
                           let image = CGImageSourceCreateThumbnailAtIndex(imageSource, index, options)
                        {
                            return image
                        } else if let image = CGImageSourceCreateImageAtIndex(imageSource, index, nil) {
                            return image
                        }
                        throw Error.imageIOError(.cgImageMissing(index: index))
                    }

                    let imageFrame = try imageFrame()
                    
                    // 设置帧间隔
                    let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: duration, kCGImagePropertyGIFUnclampedDelayTime: duration]]
                    // 每一帧都进行重新编码
                    CGImageDestinationAddImage(imageDestination, imageFrame, frameProperties as CFDictionary)
                }
            } else {
                if let options = thumbnailOptions {
                    guard let resizedImageFrame = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
                        throw Error.imageIOError(.thumbnailMissing(index: 0))
                    }
                    CGImageDestinationAddImage(imageDestination, resizedImageFrame, nil)
                } else {
                    CGImageDestinationAddImageFromSource(imageDestination, imageSource, 0, frameProperties as CFDictionary)
                }
            }
        }
        
        switch compressType {
        case .size(let size):
            var resultData = data
            
            // 若支持 DPI，先设置 DPI 为默认值
            if Self.isSupportDPI(of: inputFormat) {
                resultData = try Builder(data: data)
                    .set(dpi: dpi ?? Self.defaultDPI)
                    .finalize()
            }
            
            // 若支持压缩系数，先用压缩系数压缩 6 次，二分法
            if Self.isSupportQualityCompression(of: inputFormat) {
                if let quality = quality {
                    resultData = try Builder(data: data)
                        .set(quality: quality)
                        .finalize()
                } else {
                    var quality: CGFloat = 1
                    var maxQuality: CGFloat = 1
                    var minQuality: CGFloat = 0
                    for _ in 0 ..< 6 {
                        quality = (maxQuality + minQuality) / 2
                        resultData = try Builder(data: data)
                            .set(quality: quality)
                            .finalize()
                        if resultData.count < Int(CGFloat(size) * 0.9) {
                            minQuality = quality
                        } else if resultData.count > size {
                            maxQuality = quality
                        } else {
                            break
                        }
                    }
                    if resultData.count <= size {
                        return resultData
                    }
                }
            }

            // 若支持抽帧，先用抽帧减少大小
            if Self.isSupportSampleCount(of: inputFormat) {
                let sampleCount = sampleCount ?? Self.fitSampleCount(of: resultData.imageFrameCount)
                resultData = try Builder(data: data)
                    .set(sampleCount: sampleCount)
                    .finalize()
                if resultData.count <= size {
                    return resultData
                }
            }

            var longWidth = max(resultData.imageSize.height, resultData.imageSize.width)
            // 图片尺寸按比率缩小，比率按字节比例逼近
            while resultData.count > size {
                let ratio = sqrt(CGFloat(size) / CGFloat(resultData.count))
                longWidth *= ratio
                resultData = try Builder(data: data)
                    .set(limitLongWidth: longWidth)
                    .finalize()
            }
            return resultData
        case .width(let width):
            // 设置缩略图参数，kCGImageSourceThumbnailMaxPixelSize 为生成缩略图的大小。当设置为 800，如果图片本身大于 800*600，则生成后图片大小为 800*600，如果源图片为 700*500，则生成图片为 800*500
            let options = [kCGImageSourceThumbnailMaxPixelSize: width,
                           kCGImageSourceCreateThumbnailWithTransform: true,
                           kCGImageSourceCreateThumbnailFromImageAlways: true] as CFDictionary
            try addImage(thumbnailOptions: options)
        case .none:
            try addImage()
        }
        
        guard CGImageDestinationFinalize(imageDestination) else {
            throw Error.imageIOError(.destinationFinalizeFail)
        }

        return writeData as Data
    }
}

extension ImageCompress.Builder {
    static let defaultDPI = CGSize(width: 72, height: 72)
    
    static func isSupportQualityCompression(of format: ImageFormat) -> Bool {
        var supportedFormats: Set<ImageFormat> = [.jpeg]
        if isHeicSupported {
            supportedFormats.insert(.heic)
        }
        return supportedFormats.contains(format)
    }
    
    static func isSupportSampleCount(of format: ImageFormat) -> Bool {
        let supporFormats: Set<ImageFormat> = [.gif]
        return supporFormats.contains(format)
    }

    static var isHeicSupported: Bool {
        guard let uniformTypeIdentifers = CGImageDestinationCopyTypeIdentifiers() as? [String] else {
            return false
        }
        return Set(uniformTypeIdentifers).contains(ImageFormat.heic.uniformTypeIdentifer)
    }
    
    static func isSupportDPI(of format: ImageFormat) -> Bool {
        let supportFormats: Set<ImageFormat> = [.jpeg, .png]
        return supportFormats.contains(format)
    }
    
    static func isSupportWrite(of format: ImageFormat) -> Bool {
        let supportFormats: Set<ImageFormat> = [.jpeg, .png, .gif, .heic]
        return supportFormats.contains(format)
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
