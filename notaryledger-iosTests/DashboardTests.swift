import Foundation
import Testing
@testable import notaryledger_ios

@MainActor private final class DashboardRepositoryProbe: DashboardRepository {
    nonisolated deinit {}
    var result: Result<DashboardSnapshot, Error>
    init(_ result: Result<DashboardSnapshot, Error>) { self.result = result }
    func load() async throws -> DashboardSnapshot { try result.get() }
}

@MainActor struct DashboardTests {
    @Test func selectsNextTodayAndAtMostThreeUpcomingWithoutDuplicatingHero() async {
        let model = DashboardViewModel(repository: InMemoryDashboardRepository(snapshot: PreviewData.loaded), now: { PreviewData.date })
        await model.load()
        #expect(model.state == .loaded && model.nextSigning?.id == "preview-next")
        #expect(model.upcoming.count == 3 && !model.upcoming.contains { $0.id == model.nextSigning?.id })
        #expect(model.upcoming.map(\.startsAt) == model.upcoming.map(\.startsAt).sorted())
        #expect(model.monthStats.netIncome == 4280 && model.attentionItems.count == 2)
    }
    @Test func tomorrowIsUpcomingAndNeverPretendsToBeTodaysSigning() async {
        let future = DashboardSnapshot(signings: Array(PreviewData.loaded.signings.dropFirst()), monthStats: .zero, attentionItems: [])
        let model = DashboardViewModel(repository: InMemoryDashboardRepository(snapshot: future), now: { PreviewData.date })
        await model.load()
        #expect(model.nextSigning == nil && model.upcoming.count == 3 && model.attentionItems.isEmpty)
    }
    @Test func ordinaryErrorsSurfaceAndRetryCanLoadWithoutFabricatingData() async {
        let probe = DashboardRepositoryProbe(.failure(APIError.serverError("Could not load dashboard")))
        let model = DashboardViewModel(repository: probe, now: { PreviewData.date })
        await model.load()
        #expect(model.state == .error("Could not load dashboard") && model.nextSigning == nil)
        probe.result = .success(.empty)
        await model.load()
        #expect(model.state == .loaded && model.monthStats == .zero && model.errorMessage == nil)
    }
    @Test func canceledRefreshKeepsPreviouslyLoadedValues() async {
        let probe = DashboardRepositoryProbe(.success(PreviewData.loaded))
        let model = DashboardViewModel(repository: probe, now: { PreviewData.date })
        await model.load()
        probe.result = .failure(URLError(.cancelled))
        await model.load()
        #expect(model.state == .loaded && model.monthStats.netIncome == 4280 && model.nextSigning != nil)
    }
    @Test func oldResponseCannotReplaceNewerRefresh() async {
        let start = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<DashboardSnapshot, Error>?
        var first = true
        let repository = DelayedDashboardRepository {
            if first {
                first = false
                return try await withCheckedThrowingContinuation { continuation in pending = continuation; start.continuation.yield(()) }
            }
            return .empty
        }
        let model = DashboardViewModel(repository: repository, now: { PreviewData.date })
        let old = Task { await model.load() }
        var iterator = start.stream.makeAsyncIterator(); await iterator.next()
        await model.load()
        pending?.resume(returning: PreviewData.loaded)
        await old.value
        #expect(model.state == .loaded && model.monthStats == .zero && model.nextSigning == nil)
    }
    @Test func ledgerAdapterUsesDecimalAndOmitsUnknownAddressesAndDistances() {
        let order = SigningOrder(id: "decimal", customerName: "Title", signerName: "Signer", date: "2026-11-12", time: "10:00", fee: 100.10, paid: true, mileage: 12.5)
        let expense = Expense(id: "expense", date: "2026-11-12", category: "Supplies", description: "Sample", amount: 0.20, businessUsePercent: 100)
        let data = LedgerDashboardSnapshot.make(orders: [order], expenses: [expense], now: PreviewData.date)
        #expect(data.monthStats.netIncome == Decimal(string: "99.90"))
        #expect(data.monthStats.expenses == Decimal(string: "0.20") && data.monthStats.mileage == Decimal(string: "12.5"))
        #expect(data.signings.first?.address == "" && data.signings.first?.distanceMiles == nil)
    }
    @Test func mapsUsesAnEncodedAddressAndMissingAddressesCannotNavigate() throws {
        #expect(DashboardMaps.url(address: "  ") == nil)
        let address = "123 Example Ave, Los Angeles, CA & Suite 2"
        let url = try #require(DashboardMaps.url(address: address))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "maps.apple.com" && components.scheme == "https")
        #expect(components.queryItems?.first(where: { $0.name == "daddr" })?.value == address)
    }
    @Test func legacyDestinationsHaveStableTabOwners() {
        #expect(LedgerTab(section: .dashboard) == .home)
        #expect(LedgerTab(section: .signings) == .signings)
        #expect(LedgerTab(section: .billing) == .more)
        #expect(LedgerTab(section: .expenses) == .money)
        #expect(LedgerTab(section: .terms) == .more)
    }
}

@MainActor private struct DelayedDashboardRepository: DashboardRepository {
    let source: () async throws -> DashboardSnapshot
    func load() async throws -> DashboardSnapshot { try await source() }
}
