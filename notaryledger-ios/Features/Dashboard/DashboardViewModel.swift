import Foundation
import Observation

@MainActor @Observable final class DashboardViewModel {
    nonisolated deinit {}
    enum State: Equatable { case loading, loaded, error(String) }
    private(set) var nextSigning: Signing?
    private(set) var monthStats = MonthStats.zero
    private(set) var attentionItems: [AttentionItem] = []
    private(set) var upcoming: [Signing] = []
    private(set) var state: State = .loading
    private(set) var referenceDate: Date
    var loadsOnAppear = true
    private let repository: any DashboardRepository
    private let now: () -> Date
    private let calendar: Calendar
    private var revision = UUID()

    init(repository: any DashboardRepository, now: @escaping () -> Date = Date.init, calendar: Calendar = .autoupdatingCurrent) {
        self.repository = repository; self.now = now; self.calendar = calendar; referenceDate = now()
    }
    var greeting: String {
        switch calendar.component(.hour, from: referenceDate) {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
    var dateLabel: String { referenceDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).localizedUppercase }
    var monthLabel: String { referenceDate.formatted(.dateTime.month(.wide)) }
    var previousMonthLabel: String {
        calendar.date(byAdding: .month, value: -1, to: referenceDate)?.formatted(.dateTime.month(.wide)) ?? "last month"
    }
    var errorMessage: String? { if case .error(let message) = state { message } else { nil } }
    var isLoading: Bool { state == .loading }
    func load() async {
        let request = UUID(); revision = request
        let previousState = state
        state = .loading
        do {
            let snapshot = try await repository.load()
            try Task.checkCancellation()
            guard revision == request else { return }
            referenceDate = now()
            apply(snapshot)
            state = .loaded
        } catch {
            guard revision == request else { return }
            if RequestCancellation.isCancellation(error) {
                state = previousState
            } else { state = .error(error.localizedDescription) }
        }
    }
    private func apply(_ snapshot: DashboardSnapshot) {
        let future = snapshot.signings.filter { $0.startsAt >= referenceDate }.sorted { $0.startsAt < $1.startsAt }
        nextSigning = future.first { calendar.isDate($0.startsAt, inSameDayAs: referenceDate) }
        upcoming = Array(future.filter { $0.id != nextSigning?.id }.prefix(3))
        monthStats = snapshot.monthStats; attentionItems = snapshot.attentionItems
    }
    static func preview(snapshot: DashboardSnapshot, date: Date, state: State = .loaded) -> DashboardViewModel {
        let model = DashboardViewModel(repository: InMemoryDashboardRepository(snapshot: snapshot), now: { date })
        model.apply(snapshot); model.state = state; model.loadsOnAppear = false
        return model
    }
}
