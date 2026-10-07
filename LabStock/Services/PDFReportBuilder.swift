import UIKit

/// Native CoreGraphics/PDFKit-free PDF generation for the inventory report.
enum PDFReportBuilder {
    private static let pageSize = CGSize(width: 595, height: 842) // A4
    private static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 22
    private static let brand = UIColor(red: 0.05, green: 0.25, blue: 0.48, alpha: 1)
    private static let accent = UIColor(red: 0.09, green: 0.62, blue: 0.78, alpha: 1)

    static func inventoryReport(
        rows: [InventoryExportRow],
        summary: InventoryExportSummary,
        generatedAt: Date = .now
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            context.beginPage()
            var y = margin

            func newPageIfNeeded(_ needed: CGFloat) {
                if y + needed > pageSize.height - margin {
                    context.beginPage()
                    y = margin
                }
            }

            // Header
            draw("LabStock", at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 24, weight: .bold), color: brand)
            y += 30
            draw("Inventory Report", at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 15, weight: .semibold), color: .darkGray)
            y += 20
            draw("Generated: \(InventoryExport.stampField.string(from: generatedAt))",
                 at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 10), color: .gray)
            y += 18
            context.cgContext.setStrokeColor(accent.cgColor)
            context.cgContext.setLineWidth(2)
            context.cgContext.move(to: CGPoint(x: margin, y: y))
            context.cgContext.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
            context.cgContext.strokePath()
            y += 18

            let columns: [(String, CGFloat)] = [
                ("Item", margin),
                ("REF", 300),
                ("LOT", 360),
                ("Expiry", 430),
                ("Qty", 495),
                ("Status", 535)
            ]

            var currentGroup: String?
            for row in rows {
                if row.group != currentGroup {
                    newPageIfNeeded(rowHeight * 3)
                    currentGroup = row.group
                    y += 8
                    draw(row.group, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 12, weight: .semibold), color: brand)
                    y += 16
                    for (title, x) in columns {
                        draw(title, at: CGPoint(x: x, y: y), font: .systemFont(ofSize: 9, weight: .semibold), color: .gray)
                    }
                    y += 12
                }
                newPageIfNeeded(rowHeight)
                let values = [
                    String(row.itemName.prefix(34)),
                    row.reference,
                    String(row.lot.prefix(12)),
                    row.expiry.map { InventoryExport.dateField.string(from: $0) } ?? "-",
                    "\(row.quantity)",
                    row.status.rawValue
                ]
                for (index, entry) in columns.enumerated() {
                    let color = values[index] == ExportStatus.expired.rawValue ? UIColor.systemRed
                        : (values[index] == ExportStatus.expiring.rawValue ? UIColor.systemOrange : UIColor.black)
                    draw(values[index], at: CGPoint(x: entry.1, y: y), font: .systemFont(ofSize: 10), color: color)
                }
                y += rowHeight - 6
                context.cgContext.setStrokeColor(UIColor(white: 0.9, alpha: 1).cgColor)
                context.cgContext.setLineWidth(0.5)
                context.cgContext.move(to: CGPoint(x: margin, y: y))
                context.cgContext.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
                context.cgContext.strokePath()
                y += 6
            }

            // Summary
            newPageIfNeeded(150)
            y += 14
            draw("Summary", at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 13, weight: .bold), color: brand)
            y += 20
            let summaryLines = [
                "Total Items: \(summary.totalItems)",
                "Total Batches: \(summary.totalBatches)",
                "Total Quantity: \(summary.totalQuantity)",
                "Low Stock: \(summary.lowStock)",
                "Expiring Soon: \(summary.expiringSoon)",
                "Expired: \(summary.expired)"
            ]
            for line in summaryLines {
                draw(line, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 11), color: .black)
                y += 16
            }
        }
    }

    private static func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attributes)
    }
}
