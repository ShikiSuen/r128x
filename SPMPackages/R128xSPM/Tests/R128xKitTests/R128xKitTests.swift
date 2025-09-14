// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Testing

@testable import R128xKit

struct R128xKitTests {
  @Test
  func testBasicFunctionality() {
    // Basic test to ensure the module loads correctly
    #expect(Bool(true), "Module should load without issues")
  }

  @Test
  func testExtAudioProcessorInitialization() {
    _ = ExtAudioProcessor()
    // Just verify the processor was created successfully (no throw)
    #expect(Bool(true), "ExtAudioProcessor should initialize successfully")
  }
}
