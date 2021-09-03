import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import ImageCompress

final class ImageCompressTests: XCTestCase {
    func imageData(name: String = "test", format: ImageCompress.ImageFormat) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: format.fileExtension)!
        return try! Data(contentsOf: url)
    }
    
    func assertError(_ error: Error) {
        XCTAssert(false, "\(error)")
    }
    
    func _testWidth(of raw: Data) {
        do {
            let result = try ImageCompress.compressImageData(raw, limitLongWidth: raw.testLongWidth)
            XCTAssert(result.imageSize.small(than: raw.testLongWidth))
            let result1 = try ImageCompress
                .build(of: raw)
                .set(limitLongWidth: raw.testLongWidth)
                .finalize()
            XCTAssert(result1.imageSize.small(than: raw.testLongWidth))
        } catch {
            assertError(error)
        }
    }
    
    func _testSize(of raw: Data) {
        do {
            let result = try ImageCompress.compressImageData(raw, limitDataSize: raw.testDataCount)
            XCTAssert(result.count < raw.testDataCount)
            let result1 = try ImageCompress
                .build(of: raw)
                .set(limitSize: raw.testDataCount)
                .finalize()
            XCTAssert(result1.count < raw.testDataCount)
        } catch {
            assertError(error)
        }
    }
    
    func _testQuality(of raw: Data) {
        do {
            let result = try ImageCompress.compressImageData(raw, quality: 0)
            XCTAssert(result.count <= raw.count)
            let result1 = try ImageCompress
                .build(of: raw)
                .set(quality: 0)
                .finalize()
            XCTAssert(result1.count <= raw.count)
        } catch {
            assertError(error)
        }
    }
    
    func _testDPI(of raw: Data) {
        do {
            let dpi = ImageCompress.defaultDPI
            let result = try ImageCompress.changeDPI(of: raw, dpi: dpi)
            XCTAssertEqual(result.imageDPI, dpi)
            let result1 = try ImageCompress
                .build(of: raw)
                .set(dpi: dpi)
                .finalize()
            XCTAssertEqual(result1.imageDPI, dpi)
        } catch {
            assertError(error)
        }
    }
        
    func testPNG() {
        let raw = imageData(format: .png)
        _testSize(of: raw)
        _testWidth(of: raw)
    }
    
    func testJPEG() {
        let raw = imageData(format: .jpeg)
        _testQuality(of: raw)
        _testWidth(of: raw)
        _testSize(of: raw)
    }
    
    func testGIF() {
        let raw = imageData(format: .gif)
        
        func testGIFSampleCount() {
            do {
                let result = try ImageCompress.compressImageData(raw, sampleCount: 2)
                XCTAssert(result.imageFrameCount < raw.imageFrameCount)
                let result1 = try ImageCompress
                    .build(of: raw)
                    .set(sampleCount: 2)
                    .finalize()
                XCTAssert(result1.imageFrameCount < raw.imageFrameCount)
            } catch {
                assertError(error)
            }
        }
        
        _testWidth(of: raw)
        _testSize(of: raw)
        testGIFSampleCount()
    }
    
    func testHEIC() {
        let raw = imageData(format: .heic)
        _testQuality(of: raw)
        _testWidth(of: raw)
        _testSize(of: raw)
    }
    
    func testDPI() {
        let raw = imageData(name: "testDPI", format: .png)
        _testDPI(of: raw)
        _testSize(of: raw)
    }
    
    func testChangeFormat() {
        func changeFormat(from: ImageCompress.ImageFormat, to: ImageCompress.ImageFormat) {
            let raw = imageData(format: from)
            do {
                let result = try ImageCompress.changeImageFormat(of: raw, format: to)
                XCTAssertEqual(result.imageFormat, to)
                let result1 = try ImageCompress
                    .build(of: raw)
                    .set(format: to)
                    .finalize()
                XCTAssertEqual(result1.imageFormat, to)
            } catch {
                assertError(error)
            }
        }
        
        changeFormat(from: .png, to: .jpeg)
        changeFormat(from: .png, to: .heic)
        
        changeFormat(from: .heic, to: .png)
        changeFormat(from: .heic, to: .jpeg)
        
        changeFormat(from: .jpeg, to: .heic)
        changeFormat(from: .jpeg, to: .png)

        changeFormat(from: .dng, to: .jpeg)
        changeFormat(from: .dng, to: .png)
        changeFormat(from: .dng, to: .heic)
    }

    static var allTests = [
        ("testGIF", testGIF),
        ("testJPEG", testJPEG),
        ("testPNG", testPNG),
        ("testHEIC", testHEIC),
        ("testDPI", testDPI),
        ("testChangeFormat", testChangeFormat),
    ]
}

fileprivate extension ImageCompress.ImageFormat {
    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .gif: return "gif"
        case .heic: return "heic"
        case .dng: return "dng"
        }
    }
}

fileprivate extension CGSize {
    var longWidth: CGFloat {
        return max(height, width)
    }
    
    func small(than longWidth: CGFloat) -> Bool {
        return self.longWidth <= longWidth
    }
}

fileprivate extension Data {
    var testDataCount: Int {
        return Int(CGFloat(count) * 0.7)
    }
    
    var testLongWidth: CGFloat {
        assert(imageSize != .zero)
        return imageSize.longWidth * 0.7
    }
}
