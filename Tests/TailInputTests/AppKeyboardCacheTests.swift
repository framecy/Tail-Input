import XCTest
@testable import TailInput

@MainActor
final class AppKeyboardCacheTests: XCTestCase {

    var cache: AppKeyboardCache!

    override func setUp() {
        super.setUp()
        cache = AppKeyboardCache()
    }

    override func tearDown() {
        cache.removeAll()
        super.tearDown()
    }

    func testSaveAndRetrieve() {
        cache.save(bundleID: "com.apple.Safari", sourceID: "com.apple.keylayout.ABC")
        XCTAssertEqual(cache.retrieve(bundleID: "com.apple.Safari"), "com.apple.keylayout.ABC")
    }

    func testRetrieveMissingReturnsNil() {
        XCTAssertNil(cache.retrieve(bundleID: "com.nonexistent.app"))
    }

    func testRemove() {
        cache.save(bundleID: "com.apple.Safari", sourceID: "com.apple.keylayout.ABC")
        cache.remove(bundleID: "com.apple.Safari")
        XCTAssertNil(cache.retrieve(bundleID: "com.apple.Safari"))
    }

    func testOverwriteExisting() {
        cache.save(bundleID: "com.apple.Safari", sourceID: "com.apple.keylayout.ABC")
        cache.save(bundleID: "com.apple.Safari", sourceID: "com.apple.inputmethod.scim.itabc")
        XCTAssertEqual(cache.retrieve(bundleID: "com.apple.Safari"), "com.apple.inputmethod.scim.itabc")
    }

    func testRemoveAll() {
        cache.save(bundleID: "app1", sourceID: "source1")
        cache.save(bundleID: "app2", sourceID: "source2")
        cache.removeAll()
        XCTAssertNil(cache.retrieve(bundleID: "app1"))
        XCTAssertNil(cache.retrieve(bundleID: "app2"))
    }

    func testCount() {
        XCTAssertEqual(cache.count, 0)
        cache.save(bundleID: "app1", sourceID: "source1")
        XCTAssertEqual(cache.count, 1)
        cache.save(bundleID: "app2", sourceID: "source2")
        XCTAssertEqual(cache.count, 2)
        cache.remove(bundleID: "app1")
        XCTAssertEqual(cache.count, 1)
    }

    func testMultipleAppsIndependent() {
        cache.save(bundleID: "com.apple.Safari", sourceID: "source.safari")
        cache.save(bundleID: "com.google.Chrome", sourceID: "source.chrome")
        XCTAssertEqual(cache.retrieve(bundleID: "com.apple.Safari"), "source.safari")
        XCTAssertEqual(cache.retrieve(bundleID: "com.google.Chrome"), "source.chrome")
    }
}
