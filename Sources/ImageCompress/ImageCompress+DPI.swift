//
//  File.swift
//
//
//  Created by Nemo on 2021/7/28.
//

import Foundation
import ImageIO

public extension ImageCompress {
    static var defaultDPI: CGSize {
        Builder.defaultDPI
    }

    /// 设置图片的 DPI
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - dpi: 目标 DPI
    /// - Throws: ImageCompress.Error
    /// - Returns: 处理后数据
    static func changeDPI(of rawData: Data, dpi: CGSize = defaultDPI) throws -> Data {
        try build(of: rawData)
            .set(dpi: dpi)
            .finalize()
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
