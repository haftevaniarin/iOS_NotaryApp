import Foundation

enum SessionStorage {
    private static let accessTokenKey = "notary_access_token_v1"
    private static let refreshTokenKey = "notary_refresh_token_v1"
    private static let currentUserKey = "notary_current_user_v1"

    static func saveToken(_ token: String) {
        saveAccessToken(token)
    }

    static func getToken() -> String? {
        getAccessToken()
    }

    static func clearToken() {
        clearTokens()
    }

    static func saveAccessToken(_ token: String) {
        KeychainHelper.standard.save(token, for: accessTokenKey)
    }

    static func getAccessToken() -> String? {
        KeychainHelper.standard.read(for: accessTokenKey)
    }

    static func saveRefreshToken(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        KeychainHelper.standard.save(token, for: refreshTokenKey)
    }

    static func getRefreshToken() -> String? {
        KeychainHelper.standard.read(for: refreshTokenKey)
    }

    static func clearTokens() {
        KeychainHelper.standard.delete(accessTokenKey)
        KeychainHelper.standard.delete(refreshTokenKey)
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

    static func saveSession(_ response: AuthResponse) {
        saveAccessToken(response.token)
        saveRefreshToken(response.refreshToken)
        saveCurrentUser(response.user)
    }

    static func clearSession() {
        clearTokens()
        clearCurrentUser()
    }
}
