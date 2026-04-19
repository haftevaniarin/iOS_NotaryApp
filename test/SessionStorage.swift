import Foundation

enum SessionStorage {
    private static let tokenKey = "authToken"

    static func saveToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    static func getToken() -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    static func clearToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
}
