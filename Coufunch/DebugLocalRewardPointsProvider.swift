#if DEBUG
import Foundation
import TrisAdKit

/// Simulator-only bridge to the local TrisAdKit ledger.
/// Do not use anonymous local session issuance for production rewards.
@MainActor
final class DebugLocalRewardPointsProvider: RewardPointsProviding {
    private let baseURL = URL(string: "http://127.0.0.1:8765")!
    private let session: URLSession
    private var token: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchConfirmedPoints() async throws -> RewardPointsSnapshot {
        let accessToken = try await sessionToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/rewards/points"))
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LocalRewardError.invalidResponse
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.balance >= 0, payload.entries.allSatisfy({ $0.points > 0 }) else {
            throw LocalRewardError.invalidResponse
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        let entries = try payload.entries.map { item -> RewardPointEntry in
            guard let date = fractional.date(from: item.awardedAt) ?? standard.date(from: item.awardedAt) else {
                throw LocalRewardError.invalidResponse
            }
            return RewardPointEntry(
                id: item.id, points: item.points,
                awardedAt: date, description: item.description
            )
        }
        return RewardPointsSnapshot(balance: payload.balance, entries: entries)
    }

    private func sessionToken() async throws -> String {
        if let token { return token }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/rewards/local-session"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw LocalRewardError.localSessionDisabled
        }
        let issued = try JSONDecoder().decode(LocalSession.self, from: data)
        guard !issued.accessToken.isEmpty else { throw LocalRewardError.invalidResponse }
        token = issued.accessToken
        return issued.accessToken
    }

    private struct LocalSession: Decodable {
        let accessToken: String
    }

    private struct Payload: Decodable {
        let balance: Int
        let entries: [Entry]
    }

    private struct Entry: Decodable {
        let id: String
        let points: Int
        let awardedAt: String
        let description: String
    }

    private enum LocalRewardError: Error {
        case invalidResponse
        case localSessionDisabled
    }
}
#endif
