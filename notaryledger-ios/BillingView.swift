import SwiftUI

struct BillingView: View {
    @EnvironmentObject private var appState: AppState
    var body: some View {
        BillingOverviewView(store: appState.subscriptions)
            .onChange(of: appState.subscriptions.billingStatus) { _, status in
                if let status, let owner = appState.currentUser?.id, owner == appState.subscriptions.accountID {
                    appState.updateBillingStatus(status, for: owner)
                }
            }
    }
}
