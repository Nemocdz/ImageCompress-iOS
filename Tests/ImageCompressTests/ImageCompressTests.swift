import XCTest
@testable import ImageCompress

final class ImageCompressTests: XCTestCase {
    func imageData(of format: ImageCompress.ImageFormat) -> Data {
        let url = Bundle.module.url(forResource: "test", withExtension: format.fileExtension)!
        return try! Data(contentsOf: url)
    }
    
    func assertError(_ error: Error) {
        XCTAssert(false, "\(error)")
    }
    
    func _testWidth(of raw: Data) {
        do {
            let result = try ImageCompress.compressImageData(raw, limitLongWidth: raw.testLongWidth)
            XCTAssert(result.imageSize.small(than: raw.testLongWidth))
        } catch {
            assertError(error)
        }
    }
    
    func _testSize(of raw: Data) {
        do {
            let result = try ImageCompress.compressImageData(raw, limitDataSize: raw.testDataCount)
            XCTAssert(result.count < raw.testDataCount)
        } catch {
            assertError(error)
        }
    }
    
    func _testQuality(of raw: Data) {
        do {
            let result = try ImageCompress.compressImageData(raw, quality: 0)
            XCTAssert(result.count <= raw.count)
        } catch {
            assertError(error)
        }
    }
        
    func testPNG() {
        let raw = imageData(of: .png)
        _testSize(of: raw)
        _testWidth(of: raw)
    }
    
    func testJPEG() {
        let raw = imageData(of: .jpeg)
        _testQuality(of: raw)
        _testWidth(of: raw)
        _testSize(of: raw)
    }
    
    func testGIF() {
        let raw = imageData(of: .gif)
        
        func testGIFSampleCount() {
            do {
                let result = try ImageCompress.compressImageData(raw, sampleCount: 2)
                XCTAssert(result.frameCount < raw.frameCount)
            } catch {
                assertError(error)
            }
        }
        
        _testWidth(of: raw)
        _testSize(of: raw)
        testGIFSampleCount()
    }
    
    func testHEIC() {
        let raw = imageData(of: .heic)
        _testQuality(of: raw)
        _testWidth(of: raw)
        _testSize(of: raw)
    }

    static var allTests = [
        ("testGIF", testGIF),
        ("testJPEG", testJPEG),
        ("testPNG", testPNG),
        ("testHEIC", testHEIC),
    ]
}

fileprivate extension ImageCompress.ImageFormat {
    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .gif: return "gif"
        case .heic: return "heic"
        default: return ""
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
