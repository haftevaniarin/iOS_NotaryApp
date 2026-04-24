import XCTest
@testable import test

final class OrderParsingTests: XCTestCase {
    func testParsingOrdersJSON() throws {
        let json = """
        [
          {
            "id": "1",
            "customerName": "Alice",
            "signerName": "Bob",
            "date": "2026-04-01",
            "fee": 150.0,
            "paid": true,
            "invoiceNumber": "INV-100"
          },
          {
            "id": "2",
            "customerName": "Charlie",
            "signerName": "Dana",
            "date": "2026-03-15",
            "fee": 200.5,
            "paid": false,
            "invoiceNumber": "INV-101"
          }
        ]
        """.data(using: .utf8)!

        let orders = try JSONDecoder().decode([SigningOrder].self, from: json)
        XCTAssertEqual(orders.count, 2)
        XCTAssertEqual(orders[0].id, "1")
        XCTAssertEqual(orders[0].customerName, "Alice")
        XCTAssertEqual(orders[0].fee, 150.0)
        XCTAssertEqual(orders[1].paid, false)
    }
}
