import UIKit

// Port of App.jsx's handleGenerateTaxPdf template. Report values remain the
// backend's figures; this renderer lays them out rather than calculating tax.
enum TaxPDFGenerator {
    static func filename(user: AuthUser?, report: TaxPDFReport) -> String {
        "tax-summary-\(InvoiceDocument.filenamePart(displayName(user, fallback: "")))-\(report.summary.taxYear).pdf"
    }
    static func document(user: AuthUser?, report: TaxPDFReport, generatedAt: Date = Date(), timeZone: TimeZone = .current) -> Data {
        let template = Template()
        template.render(user: user, report: report, generatedAt: generatedAt, timeZone: timeZone)
        return BrandedPDF.document(template.layout.pages, includeDomain: false)
    }
    private static func displayName(_ user: AuthUser?, fallback: String) -> String {
        let name = [InvoiceDocument.trim(user?.firstName), InvoiceDocument.trim(user?.lastName)].filter { !$0.isEmpty }.joined(separator: " ")
        return name.nilIfEmpty ?? InvoiceDocument.trim(user?.fullName).nilIfEmpty ?? InvoiceDocument.trim(user?.email).nilIfEmpty ?? fallback
    }
    private struct Cell {
        var text: String
        var bold = false
        var muted = false
        var chip = false
    }
    private struct Column {
        let title: String
        let width: CGFloat
        var align: NSTextAlignment = .left
    }
    private final class Template {
        let layout = BrandedPDF.Layout()
        private let ink = BrandedPDF.ink
        private let slate = BrandedPDF.slate
        private let parchment = BrandedPDF.parchment
        private let brass = BrandedPDF.brass
        private let border = BrandedPDF.border
        nonisolated deinit {}

        func render(user: AuthUser?, report r: TaxPDFReport, generatedAt: Date, timeZone: TimeZone) {
            let s = r.summary
            header(user: user, year: s.taxYear, generatedAt: generatedAt, timeZone: timeZone)
            info("Taxpayer Information", ["Name: \(displayName(user, fallback: "N/A"))", "Email: \(user?.email.nilIfEmpty ?? "N/A")"], height: 66)
            section("A", "Income Summary")
            if r.hasIncomeDetails {
                metrics([("Total income received", money(s.incomeReceived)), ("Paid signing count", String(r.paidCount)),
                         ("Not yet received", money(s.unpaidIncome)), ("1099 review threshold", "$600+")])
            } else {
                metrics([("Signing fee income", money(s.incomeReceived)), ("1099 review threshold", "$600+")])
            }
            if r.missingPaidDateCount > 0 {
                info("Paid date warning", ["\(r.missingPaidDateCount) paid signing(s) used signing date because paid date is missing."], height: 54, alert: true)
            }
            if !r.clients.isEmpty {
                table([Column(title: "CLIENT", width: 170), Column(title: "PAYER", width: 132), Column(title: "SIGNINGS", width: 68),
                       Column(title: "TOTAL PAID", width: 104, align: .right), Column(title: "1099", width: 50, align: .center)],
                      rows: r.clients.map { client in
                    let payer = client.payer.trimmingCharacters(in: .whitespacesAndNewlines)
                    let meaningful = payer.count > 1 && payer.lowercased() != client.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return [Cell(text: client.name, bold: true), Cell(text: meaningful ? payer : "N/A", muted: !meaningful),
                            Cell(text: String(client.count), muted: true), Cell(text: money(client.paid), bold: true), Cell(text: "", chip: client.paid >= 600)]
                })
                layout.y += 20
            } else if s.incomeReceived > 0 {
                summaryTable("INCOME TYPE", [("Signing fee income", s.incomeReceived)])
                layout.y += 20
            } else { empty("No received income for this tax year.") }

            section("B", "Expense Summary")
            metrics([("Raw expense total", money(r.rawExpenses)), ("Deductible expenses", money(r.deductibleExpenses))])
            if !r.categories.isEmpty {
                table([Column(title: "CATEGORY", width: 220), Column(title: "ITEMS", width: 80), Column(title: "RAW TOTAL", width: 112, align: .right),
                       Column(title: "DEDUCTIBLE", width: 112, align: .right)], rows: r.categories.map {
                    [Cell(text: $0.name, bold: true), Cell(text: String($0.count), muted: true), Cell(text: money($0.raw), muted: true), Cell(text: money($0.deductible), bold: true)]
                })
                layout.y += 18
            } else if s.businessExpenses > 0 || r.orderExpenses > 0 {
                summaryTable("EXPENSE TYPE", [("Business expenses", s.businessExpenses), ("Order-specific expenses", r.orderExpenses)])
                layout.y += 18
            } else { empty("No expenses recorded for this tax year.") }
            let mileage = NumberFormatter()
            mileage.locale = Locale(identifier: "en_US"); mileage.numberStyle = .decimal; mileage.maximumFractionDigits = 2
            info("Mileage", ["Business miles: \(mileage.string(from: NSNumber(value: s.totalBusinessMiles)) ?? "0") mi",
                             "Parking: \(money(r.parking))", "Total travel expenses: \(money(s.travelExpenses))",
                             "Mileage and expense totals are provided for recordkeeping and tax preparation. Consult a qualified tax professional regarding deductibility."], height: 116)

            section("C", "Net Summary")
            metrics([("Total income received", money(s.incomeReceived)), ("Total deductible expenses", money(r.totalDeductibleExpenses)),
                     ("Notarial act fees exempt from SE tax", "-" + money(s.notarialActFeeExemptPortion)), ("Self-employment taxable income", money(s.selfEmploymentTaxableIncome))])
            layout.ensure(102)
            layout.box(44, layout.y, 524, 88, radius: 8, fill: ink)
            layout.text("Net self-employment income", 62, layout.y + 25, bold: true, color: parchment, width: 210)
            layout.text(money(s.netSelfEmploymentIncome), 62, layout.y + 55, size: 22, bold: true, serif: true, color: parchment, width: 210)
            let label = r.taxRate > 0 ? "Estimated self-employment tax at \(r.taxRate.formatted(.number.locale(Locale(identifier: "en_US"))))%" : "Estimated tax payments"
            layout.text(label, 548, layout.y + 25, bold: true, color: parchment, width: 230, align: .right)
            layout.text(money(r.taxRate > 0 ? s.estimatedSelfEmploymentTax : s.estimatedTaxPayments), 548, layout.y + 55, size: 22, bold: true, serif: true, color: parchment, width: 230, align: .right)
            layout.y += 104
            info("Estimate notice", ["This is an estimate only, not a filing figure.",
                                     "Notarial act fee amounts are self-reported per signing. Consult your tax preparer before filing."], height: 68)

            section("D", "Estimated Tax Payments")
            if !r.payments.isEmpty {
                table([Column(title: "DATE", width: 155), Column(title: "QUARTER", width: 150), Column(title: "AMOUNT", width: 109, align: .right),
                       Column(title: "RUNNING TOTAL", width: 110, align: .right)], rows: r.payments.map {
                    [Cell(text: InvoiceDocument.displayDate($0.date), muted: true), Cell(text: $0.quarter, bold: true),
                     Cell(text: money($0.amount), bold: true), Cell(text: money($0.runningTotal), muted: true)]
                })
                layout.y += 16
            } else if s.estimatedTaxPayments > 0 {
                summaryTable("PAYMENT TYPE", [("Estimated tax payments", s.estimatedTaxPayments)])
                layout.y += 16
            } else { empty("No estimated tax payments recorded.") }
            metrics([("Estimated payments total", money(s.estimatedTaxPayments))])
            info("CPA Note", ["This report summarizes records in Notary Ledger for bookkeeping support. Review with your accountant or tax preparer before filing."], height: 58)
        }
        private func money(_ value: Double) -> String { InvoiceDocument.currency(value) }
        private func header(user: AuthUser?, year: Int, generatedAt: Date, timeZone: TimeZone) {
            layout.add(.stamp)
            layout.text("Notary Ledger", 86, 58, size: 13, bold: true, serif: true, width: 160)
            layout.text("Signing Agent Desk", 86, 72, size: 7.5, bold: true, color: slate, width: 160)
            layout.box(378, 46, 190, 58, radius: 8, stroke: border)
            layout.text("TAX YEAR", 392, 68, size: 7.5, bold: true, color: slate, width: 70)
            layout.text(String(year), 554, 68, bold: true, width: 90, align: .right)
            layout.text("GENERATED", 392, 89, size: 7.5, bold: true, color: slate, width: 70)
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.locale = Locale(identifier: "en_US"); formatter.dateFormat = "M/d/yyyy, h:mm:ss a"
            layout.text(formatter.string(from: generatedAt), 554, 89, size: 8.5, bold: true, width: 110, align: .right)
            let title = displayName(user, fallback: "Notary Ledger") + " Tax Summary"
            let lines = BrandedPDF.Layout.wrapped(title, width: 360, font: BrandedPDF.font(24, bold: true, serif: true)).count
            let extra = CGFloat(max(0, lines - 1)) * 27.6
            layout.text(title, 44, 124, size: 24, bold: true, serif: true, width: 360)
            layout.line(44, 142 + extra, 568, 142 + extra, color: brass, width: 2)
            layout.y = 168 + extra
        }
        private func section(_ letter: String, _ title: String) {
            layout.ensure(34)
            layout.add(.circle(CGRect(x: 44, y: layout.y - 9, width: 18, height: 18), ink))
            layout.text(letter, 53, layout.y + 3, size: 8, bold: true, color: parchment, width: 12, align: .center)
            layout.text(title, 70, layout.y + 6, size: 15, bold: true, serif: true, width: 498)
            layout.y += 28
        }
        private func info(_ title: String, _ rows: [String], height: CGFloat, alert: Bool = false) {
            let foreground = alert ? UIColor(red: 150/255, green: 50/255, blue: 42/255, alpha: 1) : ink
            let fill = alert ? UIColor(red: 245/255, green: 228/255, blue: 225/255, alpha: 1) : parchment
            let lineCounts = rows.map { BrandedPDF.Layout.wrapped($0, width: 492, font: BrandedPDF.font(9)).count }
            let actualHeight = max(height, 39 + CGFloat(lineCounts.reduce(0, +) - 1) * 10.35 + CGFloat(max(0, rows.count - 1)) * 3.65 + 8)
            layout.ensure(actualHeight + 14)
            layout.box(44, layout.y, 524, actualHeight, radius: 7, fill: fill, stroke: alert ? foreground : border, strokeWidth: 0.8)
            layout.box(44, layout.y, 3, actualHeight, fill: alert ? foreground : brass)
            layout.text(title, 60, layout.y + 20, size: 10.5, bold: true, color: foreground, width: 492)
            var baseline = layout.y + 39
            for (index, row) in rows.enumerated() {
                layout.text(row, 60, baseline, size: 9, color: alert ? foreground : slate, width: 492)
                baseline += CGFloat(lineCounts[index]) * 10.35 + 3.65
            }
            layout.y += actualHeight + 14
        }
        private func empty(_ message: String) { info("No records", [message], height: 54) }
        private func metrics(_ metrics: [(String, String)]) {
            for (index, metric) in metrics.enumerated() {
                if index % 2 == 0 { layout.ensure(68) }
                let x: CGFloat = index % 2 == 0 ? 44 : 312
                layout.box(x, layout.y, 256, 56, radius: 7, stroke: border, strokeWidth: 0.8)
                layout.text(metric.0, x + 12, layout.y + 18, size: 8, bold: true, color: slate, width: 232)
                layout.text(metric.1, x + 12, layout.y + 41, size: 13, bold: true, width: 232)
                if index % 2 == 1 || index == metrics.count - 1 { layout.y += 68 }
            }
        }
        private func summaryTable(_ title: String, _ values: [(String, Double)]) {
            table([Column(title: title, width: 370), Column(title: "TOTAL", width: 154, align: .right)],
                  rows: values.map { [Cell(text: $0.0, bold: true), Cell(text: money($0.1), bold: true)] })
        }
        private func table(_ columns: [Column], rows: [[Cell]]) {
            func position(_ column: Column, x: CGFloat) -> CGFloat {
                column.align == .right ? x + column.width - 8 : column.align == .center ? x + column.width / 2 : x + 8
            }
            func tableHeader() {
                layout.ensure(24)
                layout.box(44, layout.y, 524, 24, radius: 5, fill: ink)
                var x: CGFloat = 44
                for column in columns {
                    layout.text(column.title, position(column, x: x), layout.y + 16, size: 8, bold: true, color: parchment, width: column.width - 16, align: column.align)
                    x += column.width
                }
                layout.y += 30
            }
            tableHeader()
            for (index, row) in rows.enumerated() {
                let lines = row.enumerated().map {
                    BrandedPDF.Layout.wrapped($0.element.text, width: max(16, columns[$0.offset].width - 16), font: BrandedPDF.font(8.7, bold: $0.element.bold))
                }
                let count = lines.map(\.count).max() ?? 1
                let height = max(26, CGFloat(count) * 12.7 + 12)
                if height <= 654, layout.ensure(height) { tableHeader() }
                var offset = 0
                while offset < count {
                    if layout.y + 26 > 736 { layout.nextPage(); tableHeader() }
                    let partCount = min(count - offset, max(1, Int((736 - layout.y - 12) / 12.7)))
                    let partHeight = max(26, CGFloat(partCount) * 12.7 + 12)
                    if index % 2 == 1 { layout.box(44, layout.y - 4, 524, partHeight) }
                    layout.line(44, layout.y + partHeight - 5, 568, layout.y + partHeight - 5, width: 0.7)
                    var x: CGFloat = 44
                    for (columnIndex, cell) in row.enumerated() {
                        let column = columns[columnIndex]
                        if cell.chip && offset == 0 {
                            let chipX = x + (column.width - 38) / 2
                            layout.box(chipX, layout.y + 3, 38, 14, radius: 7, stroke: border, strokeWidth: 0.7)
                            layout.text("1099", chipX + 19, layout.y + 13, size: 7, bold: true,
                                        color: UIColor(red: 150/255, green: 112/255, blue: 63/255, alpha: 1), width: 30, align: .center)
                        }
                        layout.drawLines(Array(lines[columnIndex].dropFirst(offset).prefix(partCount)), position(column, x: x), layout.y + 13,
                                         font: BrandedPDF.font(8.7, bold: cell.bold), color: cell.muted ? slate : ink, align: column.align)
                        x += column.width
                    }
                    layout.y += partHeight
                    offset += partCount
                    if offset < count { layout.nextPage(); tableHeader() }
                }
            }
        }
    }
}
