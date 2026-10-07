import SwiftUI
import UIKit

/// Shared visual system: deep blue / cyan / teal medical-tech palette with light + dark support.
enum LabTheme {
    static let deepBlue = Color(red: 0.05, green: 0.22, blue: 0.45)
    static let cyan = Color(red: 0.09, green: 0.62, blue: 0.82)
    static let teal = Color(red: 0.06, green: 0.60, blue: 0.58)
    static let amber = Color(red: 0.95, green: 0.65, blue: 0.15)

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [deepBlue, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var heroGradient: LinearGradient {
        LinearGradient(colors: [deepBlue, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let cardCorner: CGFloat = 16
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct MetricCard: View {
    let value: String
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LabTheme.cardCorner, style: .continuous))
    }
}

struct HeroCard: View {
    let caption: String
    let value: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(value)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(title)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(LabTheme.heroGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? AnyShapeStyle(LabTheme.brandGradient) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)),
                            in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let icon: String
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(LabTheme.cyan)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let primaryTitle, let primaryAction {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// Native share sheet: Save to Files, AirDrop, WhatsApp, Email, …
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension ExportStatus {
    var color: Color {
        switch self {
        case .normal: LabTheme.teal
        case .lowStock: LabTheme.amber
        case .expiring: .orange
        case .expired: .red
        }
    }
}

extension MovementType {
    var color: Color {
        switch self {
        case .add: .green
        case .withdraw: .red
        case .adjustment: LabTheme.amber
        case .inventory: LabTheme.cyan
        }
    }
}
