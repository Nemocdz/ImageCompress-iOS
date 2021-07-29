//
//  File.swift
//
//
//  Created by Nemo on 2021/7/28.
//

import Foundation
import ImageIO
import CoreServices.LaunchServices.UTCoreTypes
import struct AVFoundation.AVFileType

public extension ImageCompress {
    enum ImageFormat: CaseIterable {
        case jpeg
        case png
        case gif
        case heic
        case dng
    }
}

public extension ImageCompress {
    /// 更改图片格式
    /// - Parameters:
    ///   - rawData: 原始数据
    ///   - format: 目标图片格式
    /// - Throws: ImageCompress.Error
    /// - Returns: 处理后数据
    static func changeImageFormat(of rawData: Data, format: ImageFormat) throws -> Data {
        guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let writeData = CFDataCreateMutable(nil, 0),
              let imageType = CGImageSourceGetType(imageSource)
        else {
            throw Error.imageIOError(.sourceMissing)
        }

        guard let imageDestination = CGImageDestinationCreateWithData(writeData, format.uniformTypeIdentifer as CFString, 1, nil) else {
            throw Error.imageIOError(.destinationMissing(type: imageType as String))
        }

        CGImageDestinationAddImageFromSource(imageDestination, imageSource, 0, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw Error.imageIOError(.destinationFinalizeFail)
        }
        return writeData as Data
    }

    /// 获取图片格式
    /// - Parameter rawData: 原始图片数据
    /// - Returns: 图片格式
    static func imageFormat(of rawData: Data) -> ImageFormat? {
        return rawData.imageFormat
    }
}

extension Data {
    var imageFormat: ImageCompress.ImageFormat? {
        guard count >= 8 else {
            return nil
        }

        var headerData = [UInt8](repeating: 0, count: 8)
        copyBytes(to: &headerData, from: 0 ..< 8)

        if headerData.hasPrefix([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return .png
        } else if headerData.hasPrefix([0xFF, 0xD8, 0xFF]) {
            return .jpeg
        } else if headerData.hasPrefix([0x47, 0x49, 0x46]) {
            return .gif
        } else if isHeicFormat {
            return .heic
        } else if headerData.hasPrefix([0x4D, 0x4D, 0x00, 0x2A]) || headerData.hasPrefix([0x49, 0x49, 0x00, 0x2A]) {
            return .dng
        }
        return nil
    }

    var isHeicFormat: Bool {
        guard count >= 12 else {
            return false
        }

        guard let testString = String(data: subdata(in: 4 ..< 12), encoding: .ascii) else {
            return false
        }
        guard Set(["ftypheic", "ftypheix", "ftyphevc", "ftyphevx"]).contains(testString.lowercased()) else {
            return false
        }
        return true
    }
}

extension ImageCompress.ImageFormat {
    var uniformTypeIdentifer: String {
        switch self {
        case .heic:
            return AVFileType.heic.rawValue
        case .gif:
            return kUTTypeGIF as String
        case .png:
            return kUTTypePNG as String
        case .jpeg:
            return kUTTypeJPEG as String
        case .dng:
            return AVFileType.dng.rawValue
        }
    }
}

private extension Array where Element == UInt8 {
    func hasPrefix(_ prefix: [UInt8]) -> Bool {
        guard prefix.count <= count else { return false }
        return prefix.enumerated().allSatisfy { self[$0.offset] == $0.element }
    }
}
