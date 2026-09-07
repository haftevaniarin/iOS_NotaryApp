import Foundation

enum APIConfig {
    enum Environment: String {
        case local
        case staging
        case production
    }

    static var environment: Environment {
        #if PRODUCTION
        return .production
        #elseif STAGING
        return .staging
        #else
        return .local
        #endif
    }

    static var baseURL: String {
        switch environment {
        case .local:
            return "http://127.0.0.1:4000"
        case .staging:
            return "https://staging.notaryledger.org"
        case .production:
            return "https://notaryledger.org"
        }
    }

    static let maintenancePath = "/api/config/maintenance"
}
