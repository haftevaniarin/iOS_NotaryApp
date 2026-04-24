import Foundation

enum SessionStorage {
    private static let tokenKey = "notary_token_v1"
    private static let currentUserKey = "notary_current_user_v1"

    static func saveToken(_ token: String) {
        KeychainHelper.standard.save(token, for: tokenKey)
    }

    static func getToken() -> String? {
        KeychainHelper.standard.read(for: tokenKey)
    }

    static func clearToken() {
        KeychainHelper.standard.delete(tokenKey)
    }

    static func saveCurrentUser(_ user: AuthUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: currentUserKey)
        }
    }

    static func getCurrentUser() -> AuthUser? {
        guard let data = UserDefaults.standard.data(forKey: currentUserKey) else { return nil }
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    static func clearCurrentUser() {
        UserDefaults.standard.removeObject(forKey: currentUserKey)
    }
}
