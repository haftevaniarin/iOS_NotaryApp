import Foundation

nonisolated struct SubscriptionEligibility: Equatable {
    var countryCode: String?
    // Retained for legacy callers; the native subscription flow uses Stripe.
    var hasAppleSubscription = false
    var allowsStripeLinks: Bool { countryCode == "USA" }
    func allowsNewStripePurchase(hasStripeSubscription: Bool) -> Bool {
        allowsStripeLinks && !hasAppleSubscription && !hasStripeSubscription
    }
}
