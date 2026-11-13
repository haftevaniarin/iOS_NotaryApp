import Foundation

@MainActor protocol DashboardRepository {
    func load() async throws -> DashboardSnapshot
}

@MainActor struct InMemoryDashboardRepository: DashboardRepository {
    private let source: () throws -> DashboardSnapshot
    init(snapshot: DashboardSnapshot) { source = { snapshot } }
    init(source: @escaping () throws -> DashboardSnapshot) { self.source = source }
    func load() async throws -> DashboardSnapshot { try source() }
}

@MainActor struct MockDashboardRepository: DashboardRepository {
    let result: Result<DashboardSnapshot, Error>
    func load() async throws -> DashboardSnapshot { try result.get() }
}
