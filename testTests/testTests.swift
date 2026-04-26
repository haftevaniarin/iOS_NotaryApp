//
//  testTests.swift
//  testTests
//
//  Created by Arin on 3/17/26.
//

// Support both the custom `Testing` harness and XCTest. Use whichever is available.
#if canImport(Testing)
import Testing
@testable import test

struct testTests {
    @Test func example() async throws {
        // Use the Testing harness when available.
    }
}
// XCTest path disabled in this environment to avoid missing module errors.
#else
// No test framework available in this environment. Tests will be skipped.
#endif
