import SwiftUI
import UIKit

/// Camera-first capture screen used by the AI scanning flow.
struct LabelCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = LabelCameraController()
    let onCapture: (UIImage) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }

    @ViewBuilder private var content: some View {
        if let image = controller.capturedImage {
            captured(image)
        } else if controller.authorizationDenied {
            unavailable("Camera access is off. Enable camera access for LabStock in Settings.", symbol: "camera.fill")
        } else if let message = controller.errorMessage {
            unavailable(message, symbol: "exclamationmark.triangle")
        } else {
            LabelCameraPreview(session: controller.session) { controller.focus(at: $0) }
                .ignoresSafeArea()
                .overlay { frameGuide }
                .overlay(alignment: .top) { topBar }
                .overlay(alignment: .bottom) { shutterBar }
        }
    }

    private var frameGuide: some View {
        VStack(spacing: 16) {
            Text("Fill the frame with the label")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.45), in: Capsule())
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
                CornerMarks()
                    .stroke(LabTheme.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            .frame(width: 280, height: 380)
        }
        .allowsHitTesting(false)
    }

    /// Subtle framing corners instead of a full box.
    private struct CornerMarks: Shape {
        func path(in rect: CGRect) -> Path {
            let length: CGFloat = 34
            let radius: CGFloat = 22
            var path = Path()
            // top-left
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius + length))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + radius + length, y: rect.minY))
            // top-right
            path.move(to: CGPoint(x: rect.maxX - radius - length, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius + length))
            // bottom-right
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - radius - length))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - radius - length, y: rect.maxY))
            // bottom-left
            path.move(to: CGPoint(x: rect.minX + radius + length, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius - length))
            return path
        }
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white)
            Spacer()
            Button {
                controller.toggleTorch()
            } label: {
                Image(systemName: controller.torchOn ? "bolt.fill" : "bolt.slash.fill")
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .accessibilityLabel(controller.torchOn ? "Turn off light" : "Turn on light")
        }
        .padding()
    }

    private var shutterBar: some View {
        VStack(spacing: 10) {
            Button {
                controller.capture()
            } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 4).padding(-6))
            }
            .accessibilityLabel("Capture label")
            Text("Tap the label to focus")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .padding(.bottom, 24)
    }

    private func captured(_ image: UIImage) -> some View {
        VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: .infinity)
            HStack(spacing: 16) {
                Button {
                    controller.retake()
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    dismiss()
                    onCapture(image)
                } label: {
                    Label("Use Photo", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private func unavailable(_ message: String, symbol: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 48)).foregroundStyle(.white)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 28)
            Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }
}
