import UIKit
import CoreText

// Shared drawing primitives for the web-aligned invoice and tax templates.
enum BrandedPDF {
    static let ink = color(27, 42, 74)
    static let parchment = color(250, 246, 236)
    static let brass = color(184, 137, 91)
    static let slate = color(91, 100, 114)
    static let border = color(228, 221, 203)
    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }
    static func font(_ size: CGFloat, bold: Bool = false, serif: Bool = false) -> UIFont {
        UIFont(name: serif ? (bold ? "TimesNewRomanPS-BoldMT" : "TimesNewRomanPSMT") : (bold ? "Helvetica-Bold" : "Helvetica"), size: size) ?? UIFont.systemFont(ofSize: size)
    }
    enum Mark {
        case text(String, CGPoint, UIFont, UIColor)
        case box(CGRect, CGFloat, UIColor, UIColor?, CGFloat)
        case circle(CGRect, UIColor)
        case line(CGPoint, CGPoint, UIColor, CGFloat)
        case stamp

        func draw(in context: CGContext) {
            context.saveGState()
            defer { context.restoreGState() }
            switch self {
            case let .text(text, origin, font, color):
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
                context.translateBy(x: origin.x, y: origin.y)
                context.scaleBy(x: 1, y: -1)
                context.textMatrix = .identity
                context.textPosition = .zero
                CTLineDraw(line, context)
            case let .box(rect, radius, fill, stroke, strokeWidth):
                let path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
                context.addPath(path)
                context.setFillColor(fill.cgColor)
                if let stroke {
                    context.setStrokeColor(stroke.cgColor)
                    context.setLineWidth(strokeWidth)
                    context.drawPath(using: .fillStroke)
                } else { context.fillPath() }
            case let .circle(rect, fill):
                context.setFillColor(fill.cgColor)
                context.fillEllipse(in: rect)
            case let .line(start, end, color, width):
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(width)
                context.move(to: start); context.addLine(to: end); context.strokePath()
            case .stamp:
                context.setStrokeColor(brass.cgColor)
                context.setLineWidth(1.2)
                context.setLineDash(phase: 0, lengths: [2.2, 2.2])
                context.strokeEllipse(in: CGRect(x: 44, y: 46, width: 32, height: 32))
                context.setLineDash(phase: 0, lengths: [])
                context.setFillColor(ink.cgColor)
                context.fillEllipse(in: CGRect(x: 48, y: 50, width: 24, height: 24))
                let face = BrandedPDF.font(11, bold: true, serif: true)
                let width = ("NL" as NSString).size(withAttributes: [.font: face]).width
                Mark.text("NL", CGPoint(x: 60 - width / 2, y: 66), face, parchment).draw(in: context)
            }
        }
    }

    final class Layout {
        var pages: [[Mark]] = [[]]
        var y: CGFloat = 52
        // This drawing plan needs no actor-bound cleanup. Match the other model
        // lifetime workaround for iOS 26.1 (swiftlang/swift#88036).
        nonisolated deinit {}
        func add(_ mark: Mark) { pages[pages.count - 1].append(mark) }
        func nextPage() { pages.append([]); y = 52 }
        @discardableResult func ensure(_ height: CGFloat) -> Bool {
            guard y + height > 736 else { return false }
            nextPage(); return true
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat = 0, fill: UIColor = parchment, stroke: UIColor? = nil, strokeWidth: CGFloat = 1) {
            add(.box(CGRect(x: x, y: y, width: width, height: height), radius, fill, stroke, strokeWidth))
        }
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, color: UIColor = border, width: CGFloat = 1) {
            add(.line(CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2), color, width))
        }
        static func wrapped(_ text: String, width: CGFloat, font: UIFont) -> [String] {
            text.components(separatedBy: "\n").flatMap { paragraph -> [String] in
                guard !paragraph.isEmpty else { return [""] }
                let string = paragraph as NSString
                let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: paragraph, attributes: [.font: font]))
                var result: [String] = []
                var offset = 0
                while offset < string.length {
                    let count = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, Double(width)))
                    result.append(string.substring(with: NSRange(location: offset, length: count)).trimmingCharacters(in: .whitespaces))
                    offset += count
                }
                return result
            }
        }
        @discardableResult func text(_ value: String, _ x: CGFloat, _ baseline: CGFloat, size: CGFloat = 10, bold: Bool = false,
                                     serif: Bool = false, color: UIColor = ink, width: CGFloat = 524, align: NSTextAlignment = .left) -> CGFloat {
            let face = BrandedPDF.font(size, bold: bold, serif: serif)
            let lines = Self.wrapped(value, width: width, font: face)
            drawLines(lines, x, baseline, font: face, color: color, align: align)
            return CGFloat(lines.count) * (size * 1.15 + 3)
        }
        func drawLines(_ lines: [String], _ x: CGFloat, _ baseline: CGFloat, font: UIFont, color: UIColor, align: NSTextAlignment = .left) {
            for (index, text) in lines.enumerated() {
                let width = (text as NSString).size(withAttributes: [.font: font]).width
                let offset: CGFloat = align == .right ? width : align == .center ? width / 2 : 0
                add(.text(text, CGPoint(x: x - offset, y: baseline + CGFloat(index) * font.pointSize * 1.15), font, color))
            }
        }
        func invoiceTableHeader() {
            ensure(32)
            box(44, y, 524, 24, radius: 5, fill: ink)
            for (title, x, width) in [("DATE", 52.0, 70.0), ("SERVICE", 132, 230), ("REF", 374, 80), ("STATUS", 458, 62)] {
                text(title, x, y + 16, size: 8.5, bold: true, color: parchment, width: width)
            }
            text("AMOUNT", 560, y + 16, size: 8.5, bold: true, color: parchment, width: 70, align: .right)
            y += 30
        }
    }

    static func document(_ pages: [[Mark]], includeDomain: Bool) -> Data {
        return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for (index, page) in pages.enumerated() {
                context.beginPage()
                page.forEach { $0.draw(in: context.cgContext) }
                Mark.line(CGPoint(x: 44, y: 758), CGPoint(x: 568, y: 758), border, 0.7).draw(in: context.cgContext)
                let footer = "Page \(index + 1) of \(pages.count) · Generated via Notary Ledger" + (includeDomain ? " · notaryledger.org" : "")
                let face = font(8)
                let width = (footer as NSString).size(withAttributes: [.font: face]).width
                Mark.text(footer, CGPoint(x: 306 - width / 2, y: 774), face, slate).draw(in: context.cgContext)
            }
        }
    }
}
