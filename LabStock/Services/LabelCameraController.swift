import AVFoundation
import Combine
import SwiftUI
import UIKit

/// Minimal AVFoundation camera: autofocus, tap to focus, torch, single high quality capture.
final class LabelCameraController: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var torchOn = false
    @Published private(set) var authorizationDenied = false
    @Published var capturedImage: UIImage?
    @Published var errorMessage: String?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.labstock.camera")
    private var photoDevice: AVCaptureDevice?
    private var isConfigured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureAndRun()
                } else {
                    DispatchQueue.main.async { self.authorizationDenied = true }
                }
            }
        default:
            authorizationDenied = true
        }
    }

    func stop() {
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
        DispatchQueue.main.async { self.isRunning = false }
    }

    func capture() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func retake() { capturedImage = nil }

    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.photoDevice, device.hasTorch else { return }
            let target: AVCaptureDevice.TorchMode = device.torchMode == .on ? .off : .on
            guard device.isTorchModeSupported(target) else { return }
            try? device.lockForConfiguration()
            device.torchMode = target
            try? device.unlockForConfiguration()
            let isOn = target == .on
            DispatchQueue.main.async { self.torchOn = isOn }
        }
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.photoDevice else { return }
            guard device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) else { return }
            try? device.lockForConfiguration()
            device.focusPointOfInterest = devicePoint
            device.focusMode = .autoFocus
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            try? device.unlockForConfiguration()
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured { self.configure() }
            guard self.isConfigured else { return }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput) else {
            DispatchQueue.main.async { self.errorMessage = "The camera is unavailable on this device." }
            return
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        photoDevice = device

        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()

        isConfigured = true
    }
}

extension LabelCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.errorMessage = "The photo could not be processed. Try again." }
            return
        }
        DispatchQueue.main.async { self.capturedImage = image }
    }
}

struct LabelCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        uiView.onTap = onTap
    }

    final class PreviewView: UIView {
        var onTap: ((CGPoint) -> Void)?
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self))
            onTap?(point)
        }
    }
}
