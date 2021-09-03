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
        case illegalLongWidth(width: CGFloat)
        case illegalQuality(quality: CGFloat)
        case illegalSampleCount(count: Int)
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
        try build(of: rawData)
            .set(limitLongWidth: limitLongWidth)
            .finalize()
    }

    /// 同步压缩图片到指定文件大小
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - limitDataSize: 限制文件大小，单位字节
    /// - Throws: ImageCompress.Error
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData: Data, limitDataSize: Int) throws -> Data {
        try build(of: rawData)
            .set(limitSize: limitDataSize)
            .finalize()
    }

    /// 同步压缩图片抽取帧数，仅支持 GIF
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - sampleCount: 采样频率，比如 3 则每三张用第一张，然后延长时间
    /// - Throws: ImageCompress.Error
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData: Data, sampleCount: Int) throws -> Data {
        try build(of: rawData)
            .set(sampleCount: sampleCount)
            .finalize()
    }

    /// 同步压缩图片到指定压缩系数，仅支持 JPEG/HEIC
    ///
    /// - Parameters:
    ///   - rawData: 原始图片数据
    ///   - quality: 压缩系数
    /// - Throws: ImageCompress.Error
    /// - Returns: 处理后数据
    static func compressImageData(_ rawData: Data, quality: CGFloat) throws -> Data {
        try build(of: rawData)
            .set(quality: quality)
            .finalize()
    }
}
