import XCTest
@testable import ImageCompress

final class ImageCompressTests: XCTestCase {
    func imageData(of format: Data.ImageFormat) -> Data {
        let url = Bundle.module.url(forResource: "test", withExtension: format.fileExtension)!
        return try! Data(contentsOf: url)
    }
    
    func _testWidth(of raw: Data) {
        guard let result = ImageCompress.compressImageData(raw, limitLongWidth: raw.testLongWidth) else {
            return XCTAssert(false)
        }
        XCTAssert(result.imageSize.small(than: raw.testLongWidth))
    }
    
    func _testSize(of raw: Data) {
        guard let result = ImageCompress.compressImageData(raw, limitDataSize: raw.testDataCount) else {
            return XCTAssert(false)
        }
        XCTAssert(result.count < raw.testDataCount)
    }
        
    func testPNG() {
        let raw = imageData(of: .png)
        _testSize(of: raw)
        _testWidth(of: raw)
    }
    
    func testJPG() {
        let raw = imageData(of: .jpg)

        func testJPGQuality() {
            guard let result = ImageCompress.compressImageData(raw, compression: 0.0) else {
                return XCTAssert(false)
            }
            XCTAssert(result.count <= raw.count)
        }
        
        _testWidth(of: raw)
        _testSize(of: raw)
        testJPGQuality()
    }
    
    func testGIF() {
        let raw = imageData(of: .gif)
        
        func testGIFSampleCount() {
            guard let result = ImageCompress.compressImageData(raw, sampleCount: 2) else {
                return XCTAssert(false)
            }
            XCTAssert(result.frameCount <= raw.frameCount)
        }
        
        _testWidth(of: raw)
        _testSize(of: raw)
        testGIFSampleCount()
    }

    static var allTests = [
        ("testGIF", testGIF),
        ("testJPG", testJPG),
        ("testPNG", testPNG),
    ]
}

fileprivate extension Data.ImageFormat {
    var fileExtension: String {
        switch self {
        case .jpg: return "jpg"
        case .png: return "png"
        case .gif: return "gif"
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
