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
        VStack(spacing: 14) {
            Text("Fill the frame with the label")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.45), in: Capsule())
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.85), lineWidth: 3)
                .frame(width: 280, height: 380)
        }
        .allowsHitTesting(false)
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
