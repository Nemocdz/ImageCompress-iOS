//
//  File.swift
//
//
//  Created by Nemo on 2021/7/28.
//

import Foundation
import ImageIO

public extension ImageCompress {
    static let defaultDPI = CGSize(width: 72, height: 72)

    /// 设置图片的 DPI
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - dpi: 目标 DPI
    /// - Throws: ImageCompress.Error
    /// - Returns: 处理后数据
    static func changeDPI(of rawData: Data, dpi: CGSize = defaultDPI) throws -> Data {
        guard rawData.imageDPI != nil else {
            return rawData
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

        let frameProperties = [kCGImagePropertyDPIWidth: dpi.width, kCGImagePropertyDPIHeight: dpi.height] as CFDictionary
        CGImageDestinationAddImageFromSource(imageDestination, imageSource, 0, frameProperties)

        guard CGImageDestinationFinalize(imageDestination) else {
            throw Error.imageIOError(.destinationFinalizeFail)
        }
        return writeData as Data
    }

    /// 获取图片的 DPI
    /// - Parameter rawData: 原始图片数据
    /// - Returns: DPI
    static func dpi(of rawData: Data) -> CGSize? {
        return rawData.imageDPI
    }
}

extension Data {
    var imageDPI: CGSize? {
        guard let imageSource = CGImageSourceCreateWithData(self as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [AnyHashable: Any],
              let dpiHeight = properties[kCGImagePropertyDPIHeight] as? CGFloat,
              let dpiWidth = properties[kCGImagePropertyDPIWidth] as? CGFloat
        else {
            return nil
        }

        return CGSize(width: dpiWidth, height: dpiHeight)
    }
}
