import XCTest
@testable import TailInput

final class LoggerTests: XCTestCase {

    func testLoggerCreation() {
        let logger = TILogger(category: "TestModule")
        XCTAssertTrue(logger.isEnabled)
        XCTAssertEqual(logger.category, "TestModule")
    }

    func testLoggerDisabled() {
        let logger = TILogger(category: "TestModule", enabled: false)
        XCTAssertFalse(logger.isEnabled)
        // should not crash, messages silently dropped
        logger.debug("should not appear")
        logger.info("should not appear")
        logger.warn("should not appear")
        logger.error("should not appear")
    }

    func testLoggerEnabled() {
        let logger = TILogger(category: "TestModule", enabled: true)
        // should not crash
        logger.debug("debug message")
        logger.info("info message")
        logger.warn("warn message")
        logger.error("error message")
    }

    func testLogLevelEmoji() {
        XCTAssertEqual(LogLevel.debug.emoji, "\u{1F50D}")
        XCTAssertEqual(LogLevel.info.emoji, "\u{2139}\u{FE0F}")
        XCTAssertEqual(LogLevel.warn.emoji, "\u{26A0}\u{FE0F}")
        XCTAssertEqual(LogLevel.error.emoji, "\u{274C}")
    }

    func testLogLevelRawValues() {
        XCTAssertEqual(LogLevel.debug.rawValue, 0)
        XCTAssertEqual(LogLevel.info.rawValue, 1)
        XCTAssertEqual(LogLevel.warn.rawValue, 2)
        XCTAssertEqual(LogLevel.error.rawValue, 3)
    }

    func testToggleDisabled() {
        let logger = TILogger(category: "Test", enabled: false)
        logger.isEnabled = true
        logger.debug("now visible")
        // should not crash when re-enabled
        logger.isEnabled = false
        logger.debug("now hidden")
        // should not crash when disabled again
    }
}
