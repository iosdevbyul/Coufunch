import Foundation
import XCTest
@testable import Coufunch

final class LocalizationRegressionTests: XCTestCase {
    private func catalog() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Localizable", withExtension: "xcstrings"))
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: Any])
    }

    func testCriticalPayrollAndGuidanceStringsHaveKoreanTranslations() throws {
        let keys = [
            "Estimated Gross Pay", "Estimated Take-Home Pay",
            "Estimated insurance deductions", "Payroll Audit",
            "Shift Pay Forecast", "Actual Payments", "Gross receipts",
            "Net receipts", "Gross difference (received − estimated)",
            "Weekly Bonus Period", "Incentive Rules", "Manual Incentives",
            "Pay Method", "The statutory minimum wage will be selected for the work date when the session is recorded.",
            "These defaults affect new records only. Existing pay snapshots are retained. Weekly overtime is not calculated.",
            "This also removes the session's break records.",
            "%d incomplete pay record(s) excluded.",
            "%d completed shift(s) could not be calculated.",
            "%d shift(s) without sufficient pay data."
        ]
        let strings = try catalog()
        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "Missing source key: \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            let korean = try XCTUnwrap(localizations["ko"] as? [String: Any], "Missing Korean: \(key)")
            let unit = try XCTUnwrap(korean["stringUnit"] as? [String: Any])
            XCTAssertEqual(unit["state"] as? String, "translated", key)
            let translated = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
        }
    }

    func testLocalizedFormatArgumentsArePreserved() throws {
        let expected: [String: String] = [
            "%d session(s)": "%d",
            "%d incomplete pay record(s) excluded.": "%d",
            "%d completed shift(s) could not be calculated.": "%d",
            "%d shift(s) without sufficient pay data.": "%d",
            "Scheduled end: %@": "%@",
            "Actual end: %@": "%@",
            "%@ days · %@ KRW": "%@%@"
        ]
        let strings = try catalog()
        for (key, placeholders) in expected {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let ko = try XCTUnwrap((entry["localizations"] as? [String: Any])?["ko"] as? [String: Any])
            let translated = try XCTUnwrap((ko["stringUnit"] as? [String: Any])?["value"] as? String)
            let sourceArgs = placeholders.components(separatedBy: "%").dropFirst().map { "%" + $0 }
            for arg in Set(sourceArgs) {
                XCTAssertEqual(translated.components(separatedBy: arg).count - 1,
                               key.components(separatedBy: arg).count - 1, key)
            }
        }
    }
}
