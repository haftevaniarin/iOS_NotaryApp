import SwiftUI
import Charts

struct ReportsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.nlViewportWidth) private var viewportWidth
    @State private var kind: LedgerReportKind = .overview
    @State private var filters = ReportFilters()
    @State private var model = ReportsViewModel()
    @State private var viewingOrder: SigningOrder?
    private var request: ReportRequest { ReportRequest(kind: kind, filters: filters, ownerID: appState.currentUser?.id) }
    private var clients: [ReportClientOption] { ReportClientOption.from(appState.orders) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NLSpacing.lg) {
                ScreenTitleBlock(title: "Reports", subtitle: "Understand your revenue, expenses, payments, mileage, and business performance.")
                filterCard
                if let range = filters.dateRange() {
                    Text("\(filters.period.title): \(range.start) – \(range.end)")
                        .font(NLTypography.caption).foregroundStyle(NLColor.muted)
                } else {
                    Label(ReportError.invalidDateRange.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(NLColor.danger).font(NLTypography.body)
                }
                if model.isLoading || model.currentRequest != request {
                    ProgressView("Loading \(kind.title.lowercased()) report…")
                        .frame(maxWidth: .infinity, minHeight: 100).accessibilityIdentifier("reports-loading")
                } else if let error = model.errorMessage {
                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.md) {
                            Label("Report unavailable", systemImage: "exclamationmark.triangle").font(NLTypography.bodyStrong)
                            Text(error).font(NLTypography.body).accessibilityIdentifier("reports-error")
                            Button("Try again") { Task { await model.load(request) } }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                } else if let report = model.report {
                    LazyVStack(alignment: .leading, spacing: NLSpacing.lg) {
                        reportContents(report)
                    }.id(model.reportRevision)
                }
            }.nlScreenPadding()
        }.background(ParchmentBackground())
            .task(id: request) { await model.load(request) }
            .refreshable { await model.load(request) }
            .onChange(of: clients.map(\.id)) { _, ids in
                if !filters.clientID.isEmpty && !ids.contains(filters.clientID) { filters.clientID = "" }
            }
            .sheet(item: $viewingOrder) { order in
                NavigationStack {
                    SigningOrderDetailView(order: order)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { viewingOrder = nil } } }
                }
            }
    }

    private var filterCard: some View {
        NLCard {
            VStack(alignment: .leading, spacing: NLSpacing.md) {
                NLSelectField(title: "Report", selection: $kind, value: kind.title) {
                    ForEach(LedgerReportKind.allCases) { Text($0.title).tag($0) }
                }
                NLSelectField(title: "Period", selection: $filters.period, value: filters.period.title) {
                    ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                }
                NLSelectField(title: "Client", selection: $filters.clientID, value: clients.first { $0.id == filters.clientID }?.name ?? "All clients") {
                    Text("All clients").tag("")
                    ForEach(clients) { Text($0.name).tag($0.id) }
                }.disabled(clients.isEmpty)
                if filters.period == .custom {
                    NLDateField(title: "Start Date", selection: $filters.startDate)
                    NLDateField(title: "End Date", selection: $filters.endDate)
                }
                if kind.showsPaymentStatus {
                    NLSelectField(title: "Payment Status", selection: $filters.paymentStatus, value: filters.paymentStatus) {
                        ForEach(["All", "Paid", "Pending", "Overdue"], id: \.self) { Text($0).tag($0) }
                    }
                }
                if kind.showsOrderStatus {
                    NLSelectField(title: "Order Status", selection: $filters.orderStatus, value: filters.orderStatus) {
                        ForEach(["All", "Scheduled", "Pending", "Overdue", "Paid", "Cancelled"], id: \.self) { Text($0).tag($0) }
                    }
                }
            }.tint(NLColor.navy)
        }
    }

    @ViewBuilder private func reportContents(_ report: LedgerReport) -> some View {
        let metrics = kind.metrics.filter { $0.formatted(in: report.totals) != nil }
        if !metrics.isEmpty {
            SectionHeader(title: kind.title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: dynamicTypeSize.isAccessibilitySize || viewportWidth < 360 ? 1 : 2), spacing: NLSpacing.md) {
                ForEach(metrics) { field in
                    NLCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(field.title).font(NLTypography.caption).foregroundStyle(NLColor.muted)
                            Text(field.formatted(in: report.totals) ?? "")
                                .font(NLTypography.cardTitle).foregroundStyle(NLColor.navy)
                                .fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("report-metric-\(field.key)")
                }
            }
        }
        let points = chartPoints(report)
        if !points.isEmpty {
            NLCard {
                VStack(alignment: .leading, spacing: NLSpacing.md) {
                    Text("\(kind.title) Trend").font(NLTypography.cardTitle)
                    Chart(points) { point in
                        BarMark(x: .value("Month", point.period), y: .value("Value", point.value))
                            .foregroundStyle(by: .value("Metric", point.series))
                            .position(by: .value("Metric", point.series))
                            .accessibilityLabel("\(point.period), \(point.series)")
                            .accessibilityValue(point.formatted)
                    }
                    .chartForegroundStyleScale(range: [NLColor.navy, Theme.brassDeep, Color.positive])
                    .chartScrollableAxes(.horizontal).chartXVisibleDomain(length: 6)
                    .frame(height: 220)
                }
            }
        }
        let sections = kind.sections.filter { !report.root[$0.path].rows.isEmpty }
        if kind != .outstanding && !metrics.isEmpty && metrics.allSatisfy({ report.totals[$0.key].decimal == 0 }) {
            EmptyStateView(title: "No activity", systemImage: "chart.bar.doc.horizontal", message: "No activity was recorded for this period and these filters.")
        }
        if metrics.isEmpty && sections.isEmpty {
            EmptyStateView(title: "No report data", systemImage: "chart.bar.doc.horizontal", message: "No records were returned for this period and these filters.")
        }
        ForEach(sections) { section in
            LazyVStack(alignment: .leading, spacing: NLSpacing.md) {
                SectionHeader(title: section.title)
                ForEach(Array(report.root[section.path].rows.enumerated()), id: \.offset) { index, row in
                    NLCard {
                        VStack(alignment: .leading, spacing: NLSpacing.sm) {
                            ForEach(section.fields) { field in
                                if let value = field.formatted(in: row) { DetailRow(label: field.title, value: value) }
                            }
                            if section.path == "items", let id = row["orderId"].text,
                               let order = appState.orders.first(where: { $0.id == id }) {
                                Button("View signing") { viewingOrder = order }.buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }.accessibilityElement(children: .contain)
                        .accessibilityIdentifier("report-row-\(section.path)-\(index)")
                }
            }
        }
        if kind == .outstanding && report.root["items"].rows.isEmpty {
            EmptyStateView(title: "No outstanding payments", systemImage: "checkmark.circle", message: "You're all caught up for this period and these filters.")
        }
    }

    private func chartPoints(_ report: LedgerReport) -> [ReportChartPoint] {
        report.root[kind.chartPath].rows.enumerated().flatMap { index, row in
            kind.chartFields.compactMap { field -> ReportChartPoint? in
                guard let period = row["period"].text, let value = row[field.key].decimal,
                      let formatted = field.formatted(in: row) else { return nil }
                return ReportChartPoint(id: "\(index)-\(field.id)", period: period, series: field.title,
                                        value: NSDecimalNumber(decimal: value).doubleValue, formatted: formatted)
            }
        }
    }
}

private struct ReportChartPoint: Identifiable {
    let id: String
    let period: String
    let series: String
    let value: Double
    let formatted: String
}

#Preview("Reports") {
    NavigationStack { ReportsView() }.environmentObject(AppState()).preferredColorScheme(.light)
}
