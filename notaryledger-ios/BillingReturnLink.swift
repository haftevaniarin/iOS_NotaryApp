import Foundation

nonisolated struct BillingReturnLink: Equatable {
    enum Outcome { case checkoutSuccess, checkoutCancelled, portal }
    let outcome: Outcome
    let sessionID: String?

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.port == nil else { return nil }
        if parts.scheme == "notaryledger" {
            guard parts.host == "billing", parts.path == "/return" else { return nil }
        } else {
            guard parts.scheme == "https", ["notaryledger.org", "www.notaryledger.org"].contains(parts.host ?? ""),
                  parts.path == "/mobile-billing-return.html" else { return nil }
        }
        let items = parts.queryItems ?? []
        func value(_ name: String) -> String? {
            let matches = items.filter { $0.name == name }
            return matches.count == 1 ? matches[0].value : nil
        }
        switch (value("flow"), value("checkout")) {
        case ("checkout", "success"): outcome = .checkoutSuccess
        case ("checkout", "canceled"): outcome = .checkoutCancelled
        case ("portal", nil): outcome = .portal
        default: return nil
        }
        if let value = value("session_id"), value.range(of: #"^cs_[A-Za-z0-9_]{1,200}$"#, options: .regularExpression) != nil {
            sessionID = value
        } else { sessionID = nil }
    }
}
