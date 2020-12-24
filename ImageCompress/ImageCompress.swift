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
    public enum ColorConfig{
        case alpha8
        case rgb565
        case argb8888
        case rgbaF16
        case unknown // 其余色彩配置
    }
    
    /// 改变图片到指定的色彩配置
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - config: 色彩配置
    /// - Returns: 处理后数据
    public static func changeColorWithImageData(_ rawData:Data, config:ColorConfig) -> Data?{
        guard let imageConfig = config.imageConfig else {
            return rawData
        }
    
        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let writeData = CFDataCreateMutable(nil, 0),
            let imageType = CGImageSourceGetType(imageSource),
            let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, 1, nil),
            let rawDataProvider = CGDataProvider(data: rawData as CFData),
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
                                     intent: .defaultIntent) else {
                                        return nil
        }
        CGImageDestinationAddImage(imageDestination, imageFrame, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            return nil
        }
        return writeData as Data
    }
    
    
    /// 获取图片的色彩配置
    ///
    /// - Parameter rawData: 原始图片数据
    /// - Returns: 色彩配置
    public static func getColorConfigWithImageData(_ rawData:Data) -> ColorConfig{
        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let imageFrame = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
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
    public static func compressImageData(_ rawData:Data, limitLongWidth:CGFloat) -> Data?{
        guard max(rawData.imageSize.height, rawData.imageSize.width) > limitLongWidth else {
            return rawData
        }
        
        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let writeData = CFDataCreateMutable(nil, 0),
            let imageType = CGImageSourceGetType(imageSource) else {
                return nil
        }
        
        let frameCount = CGImageSourceGetCount(imageSource)
        
        guard let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, frameCount, nil) else{
            return nil
        }
        
        // 设置缩略图参数，kCGImageSourceThumbnailMaxPixelSize 为生成缩略图的大小。当设置为 800，如果图片本身大于 800*600，则生成后图片大小为 800*600，如果源图片为 700*500，则生成图片为 800*500
        let options = [kCGImageSourceThumbnailMaxPixelSize: limitLongWidth, kCGImageSourceCreateThumbnailWithTransform:true, kCGImageSourceShouldCacheImmediately: true, kCGImageSourceCreateThumbnailFromImageAlways: true] as CFDictionary
        
        if frameCount > 1 {
            // 计算帧的间隔
            let frameDurations = imageSource.frameDurations
            
            // 每一帧都进行缩放
            let resizedImageFrames = (0..<frameCount).compactMap{ CGImageSourceCreateThumbnailAtIndex(imageSource, $0, options) }
            
            // 每一帧都进行重新编码
            zip(resizedImageFrames, frameDurations).forEach {
                // 设置帧间隔
                let frameProperties = [kCGImagePropertyGIFDictionary : [kCGImagePropertyGIFDelayTime: $1, kCGImagePropertyGIFUnclampedDelayTime: $1]]
                CGImageDestinationAddImage(imageDestination, $0, frameProperties as CFDictionary)
            }
        } else {
            guard let resizedImageFrame = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else {
                return nil
            }
            CGImageDestinationAddImage(imageDestination, resizedImageFrame, nil)
        }
        
        guard CGImageDestinationFinalize(imageDestination) else {
            return nil
        }
        
        return writeData as Data
    }
    
    /// 同步压缩图片到指定文件大小
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - limitDataSize: 限制文件大小，单位字节
    /// - Returns: 处理后数据
    public static func compressImageData(_ rawData:Data, limitDataSize:Int) -> Data?{
        guard rawData.count > limitDataSize else {
            return rawData
        }
        
        var resultData = rawData
        
        // 若是 JPG，先用压缩系数压缩 6 次，二分法
        if resultData.imageFormat == .jpg {
            var compression: Double = 1
            var maxCompression: Double = 1
            var minCompression: Double = 0
            for _ in 0..<6 {
                compression = (maxCompression + minCompression) / 2
                if let data = compressImageData(resultData, compression: compression){
                    resultData = data
                } else {
                    return nil
                }
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
            if let data = compressImageData(resultData, sampleCount: sampleCount){
                resultData = data
            } else {
                return nil
            }
            if resultData.count <= limitDataSize {
                return resultData
            }
        }
        
        var longSideWidth = max(resultData.imageSize.height, resultData.imageSize.width)
        // 图片尺寸按比率缩小，比率按字节比例逼近
        while resultData.count > limitDataSize{
            let ratio = sqrt(CGFloat(limitDataSize) / CGFloat(resultData.count))
            longSideWidth *= ratio
            if let data = compressImageData(resultData, limitLongWidth: longSideWidth) {
                resultData = data
            } else {
                return nil
            }
        }
        return resultData
    }
    
    /// 同步压缩图片抽取帧数，仅支持 GIF
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - sampleCount: 采样频率，比如 3 则每三张用第一张，然后延长时间
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData:Data, sampleCount:Int) -> Data?{
        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let writeData = CFDataCreateMutable(nil, 0),
            let imageType = CGImageSourceGetType(imageSource) else {
                return nil
        }
        
        // 计算帧的间隔
        let frameDurations = imageSource.frameDurations
        
        // 合并帧的时间,最长不可高于 200ms
        let mergeFrameDurations = (0..<frameDurations.count).filter{ $0 % sampleCount == 0 }.map{ min(frameDurations[$0..<min($0 + sampleCount, frameDurations.count)].reduce(0.0) { $0 + $1 }, 0.2) }
        
        // 抽取帧 每 n 帧使用 1 帧
        let sampleImageFrames = (0..<frameDurations.count).filter{ $0 % sampleCount == 0 }.compactMap{ CGImageSourceCreateImageAtIndex(imageSource, $0, nil) }
        
        guard let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, sampleImageFrames.count, nil) else{
            return nil
        }
        
        // 每一帧图片都进行重新编码
        zip(sampleImageFrames, mergeFrameDurations).forEach{
            // 设置帧间隔
            let frameProperties = [kCGImagePropertyGIFDictionary : [kCGImagePropertyGIFDelayTime: $1, kCGImagePropertyGIFUnclampedDelayTime: $1]]
            CGImageDestinationAddImage(imageDestination, $0, frameProperties as CFDictionary)
        }
        
        guard CGImageDestinationFinalize(imageDestination) else {
            return nil
        }
        
        return writeData as Data
    }
    
    
    /// 同步压缩图片到指定压缩系数，仅支持 JPG
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - compression: 压缩系数
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData:Data, compression:Double) -> Data?{
        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let writeData = CFDataCreateMutable(nil, 0),
            let imageType = CGImageSourceGetType(imageSource),
            let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, 1, nil) else {
                return nil
        }
        
        let frameProperties = [kCGImageDestinationLossyCompressionQuality: compression] as CFDictionary
        CGImageDestinationAddImageFromSource(imageDestination, imageSource, 0, frameProperties)
        guard CGImageDestinationFinalize(imageDestination) else {
            return nil
        }
        return writeData as Data
    }
}

extension Data{
    var fitSampleCount:Int{
        guard let imageSource = CGImageSourceCreateWithData(self as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return 1
        }
        
        let frameCount = CGImageSourceGetCount(imageSource)
        var sampleCount = 1
        switch frameCount {
        case 2..<8:
            sampleCount = 2
        case 8..<20:
            sampleCount = 3
        case 20..<30:
            sampleCount = 4
        case 30..<40:
            sampleCount = 5
        case 40..<Int.max:
            sampleCount = 6
        default:break
        }
        
        return sampleCount
    }
    
    var imageSize:CGSize{
        guard let imageSource = CGImageSourceCreateWithData(self as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [AnyHashable: Any],
            let imageHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
            let imageWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat else {
                return .zero
        }
        return CGSize(width: imageWidth, height: imageHeight)
    }
    
    var imageFormat:ImageFormat {
        var headerData = [UInt8](repeating: 0, count: 3)
        self.copyBytes(to: &headerData, from:(0..<3))
        let hexString = headerData.reduce("") { $0 + String(($1&0xFF), radix:16) }.uppercased()
        var imageFormat = ImageFormat.unknown
        switch hexString {
        case "FFD8FF":
            imageFormat = .jpg
        case "89504E":
            imageFormat = .png
        case "474946":
            imageFormat = .gif
        default:break
        }
        return imageFormat
    }
    
    enum ImageFormat {
        case jpg, png, gif, unknown
    }
}

extension CGImageSource {
    func frameDurationAtIndex(_ index: Int) -> Double{
        var frameDuration = Double(0.1)
        guard let frameProperties = CGImageSourceCopyPropertiesAtIndex(self, index, nil) as? [AnyHashable:Any], let gifProperties = frameProperties[kCGImagePropertyGIFDictionary] as? [AnyHashable:Any] else {
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
    
    var frameDurations:[Double]{
        let frameCount = CGImageSourceGetCount(self)
        return (0..<frameCount).map{ self.frameDurationAtIndex($0) }
    }
}

extension ImageCompress.ColorConfig{
    struct CGImageConfig{
        let bitsPerComponent:Int
        let bitsPerPixel:Int
        let bitmapInfo: CGBitmapInfo
    }
    
    var imageConfig:CGImageConfig?{
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
    init(_ alphaInfo:CGImageAlphaInfo, _ isFloatComponents:Bool = false) {
        var array = [
            CGBitmapInfo(rawValue: alphaInfo.rawValue),
            CGBitmapInfo(rawValue: CGImageByteOrderInfo.orderDefault.rawValue)
        ]
        
        if isFloatComponents {
            array.append(.floatComponents)
        }
        
        self.init(array)
    }
}

extension CGImage{
    var colorConfig:ImageCompress.ColorConfig{
        if isColorConfig(.alpha8) {
            return .alpha8
        } else if isColorConfig(.rgb565) {
            return .rgb565
        } else if isColorConfig(.argb8888) {
            return .argb8888
        } else if isColorConfig(.rgbaF16) {
            return .rgbaF16
        } else {
            return .unknown
        }
    }
    
    func isColorConfig(_ colorConfig:ImageCompress.ColorConfig) -> Bool{
        guard let imageConfig = colorConfig.imageConfig else {
            return false
        }
        
        if bitsPerComponent == imageConfig.bitsPerComponent &&
            bitsPerPixel == imageConfig.bitsPerPixel &&
            imageConfig.bitmapInfo.contains(CGBitmapInfo(alphaInfo)) &&
            imageConfig.bitmapInfo.contains(.floatComponents) {
            return true
        } else {
            return false
        }
    }
}


