@testable import CodexTouchBarCore
import XCTest

final class ZCodeUsageTests: XCTestCase {
    func testZCodeStandaloneChecks() async throws {
        try await ZCodeStandaloneChecks.run()
    }
}
