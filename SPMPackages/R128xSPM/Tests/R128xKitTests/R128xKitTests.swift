// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import XCTest
@testable import R128xKit

final class R128xKitTests: XCTestCase {
    
    func testBasicFunctionality() {
        // Basic test to ensure the module loads correctly
        XCTAssertTrue(true, "Module should load without issues")
    }
    
    func testExtAudioProcessorInitialization() {
        let processor = ExtAudioProcessor()
        XCTAssertNotNil(processor, "ExtAudioProcessor should initialize successfully")
    }
}
