//
//  File.swift
//
//
//  Created by Nemo on 2021/7/28.
//

import Foundation
import ImageIO

public extension ImageCompress {
    enum ColorConfig: CaseIterable {
        case alpha8
        case rgb565
        case argb8888
        case rgbaF16
    }
}

public extension ImageCompress {
    /// 改变图片到指定的色彩配置
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - config: 色彩配置
    /// - Throws: ImageCompress.Error
    /// - Returns: 处理后数据
    static func changeColor(of rawData: Data, config: ColorConfig) throws -> Data {
        guard let imageForamt = rawData.imageFormat, isSupportColorConfig(of: imageForamt) else {
            throw Error.unsupportedFormat
        }
        
        let imageConfig = config.imageConfig

        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let writeData = CFDataCreateMutable(nil, 0),
              let imageType = CGImageSourceGetType(imageSource)
        else {
            throw Error.imageIOError(.sourceMissing)
        }

        guard let imageDestination = CGImageDestinationCreateWithData(writeData, imageType, 1, nil) else {
            throw Error.imageIOError(.destinationMissing(type: imageType as String))
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
            throw Error.imageIOError(.cgImageMissing(index: 0))
        }

        CGImageDestinationAddImage(imageDestination, imageFrame, nil)

        guard CGImageDestinationFinalize(imageDestination) else {
            throw Error.imageIOError(.destinationFinalizeFail)
        }
        return writeData as Data
    }

    /// 获取图片的色彩配置
    ///
    /// - Parameter rawData: 原始图片数据
    /// - Returns: 色彩配置
    static func colorConfig(of rawData: Data) -> ColorConfig? {
        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let imageFrame = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return nil
        }

        return imageFrame.colorConfig
    }
}

extension ImageCompress {
    static func isSupportColorConfig(of format: ImageFormat) -> Bool {
        let supportedFormats: Set<ImageFormat> = [.jpeg, .heic, .png]
        return supportedFormats.contains(format)
    }
}

private extension ImageCompress.ColorConfig {
    struct CGImageConfig {
        let bitsPerComponent: Int
        let bitsPerPixel: Int
        let bitmapInfo: CGBitmapInfo
    }

    var imageConfig: CGImageConfig {
        switch self {
        case .alpha8:
            return CGImageConfig(bitsPerComponent: 8, bitsPerPixel: 8, bitmapInfo: CGBitmapInfo(.alphaOnly))
        case .rgb565:
            return CGImageConfig(bitsPerComponent: 5, bitsPerPixel: 16, bitmapInfo: CGBitmapInfo(.noneSkipFirst))
        case .argb8888:
            return CGImageConfig(bitsPerComponent: 8, bitsPerPixel: 32, bitmapInfo: CGBitmapInfo(.premultipliedFirst))
        case .rgbaF16:
            return CGImageConfig(bitsPerComponent: 16, bitsPerPixel: 64, bitmapInfo: CGBitmapInfo(.premultipliedLast, true))
        }
    }
}

private extension CGImage {
    var colorConfig: ImageCompress.ColorConfig? {
        return ImageCompress.ColorConfig.allCases.first(where: { isColorConfig($0) })
    }

    func isColorConfig(_ colorConfig: ImageCompress.ColorConfig) -> Bool {
        let imageConfig = colorConfig.imageConfig
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

private extension CGBitmapInfo {
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
