import Foundation
import XCTest
@testable import Coufunch

final class CoufunchBackupV2Tests: XCTestCase {
    private func archiveData(version: Int, preferences: [String: String]?) throws -> Data {
        var payload: [String: Any] = [
            "version": version,
            "createdAt": "2026-10-28T00:00:00Z",
            "workplaces": [], "paySettings": [], "sessions": [], "breaks": [],
            "rules": [], "incentives": [], "receipts": []
        ]
        if let preferences { payload["monthlyPreferences"] = preferences }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    func testLegacyV1ArchiveCanStillBeRead() throws {
        let archive = try CoufunchBackupStore.decode(archiveData(version: 1, preferences: nil))
        XCTAssertEqual(archive.version, 1)
        XCTAssertNil(archive.monthlyPreferences)
    }

    func testV2ArchiveIncludesMonthlyPreferences() throws {
        let id = UUID().uuidString
        let key = "insurance.employment.\(id).2026-10.previousMonth"
        let archive = try CoufunchBackupStore.decode(
            archiveData(version: 2, preferences: [key: "yes"])
        )
        XCTAssertEqual(archive.monthlyPreferences?[key], "yes")
    }

    func testV2RejectsUnsupportedPreferenceKeysAndInvalidValues() throws {
        XCTAssertThrowsError(try CoufunchBackupStore.decode(
            archiveData(version: 2, preferences: ["paydayRemindersEnabled": "true"])
        ))
        let key = "payroll.validation.\(UUID().uuidString).2026-10.fullMonthConfirmed"
        XCTAssertThrowsError(try CoufunchBackupStore.decode(
            archiveData(version: 2, preferences: [key: "not-a-boolean"])
        ))
    }

    func testV2RequiresPreferenceCollection() throws {
        XCTAssertThrowsError(try CoufunchBackupStore.decode(
            archiveData(version: 2, preferences: nil)
        ))
    }
}
