//
//  SelfieCaptureViewController.swift
//  BillEasy
//

import AVFoundation
import UIKit

final class SelfieCaptureViewController: UIViewController {

    // MARK: - Layout

    private enum Layout {
        static let captureButtonSize: CGFloat = 72
        static let bottomInset: CGFloat = 34
        static let horizontalMargin: CGFloat = 24
    }

    // MARK: - Dependencies

    private let verificacaoID: String
    private let session: AuthSession
    private let service: VerificacoesService

    // MARK: - Capture

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "br.com.billeasy.selfie.capture.session")
    private var isSessionConfigured = false
    private var capturedImage: UIImage?

    // MARK: - UI

    private let previewView = CameraPreviewView()
    private let capturedImageView = UIImageView()
    private let guideView = SelfieOvalGuideView()
    private let closeButton = UIButton(type: .system)
    private let instructionLabel = UILabel()
    private let captureButton = UIButton(type: .custom)
    private let retakeButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)
    private let uploadOverlay = UIView()
    private let uploadIndicator = UIActivityIndicatorView(style: .large)
    private let uploadLabel = UILabel()

    // MARK: - Callbacks

    var onConcluido: (() -> Void)?
    var onCancelar: (() -> Void)?

    // MARK: - Init

    init(
        verificacaoID: String,
        session: AuthSession,
        service: VerificacoesService = VerificacoesService()
    ) {
        self.verificacaoID = verificacaoID
        self.session = session
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        requestCameraAccessIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewView.previewLayer.frame = previewView.bounds
        captureButton.layer.cornerRadius = captureButton.bounds.width / 2
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSessionIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    // MARK: - Setup

    private func setupView() {
        view.backgroundColor = UIColor(hex: "#050B12")

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.previewLayer.videoGravity = .resizeAspectFill
        view.addSubview(previewView)

        capturedImageView.translatesAutoresizingMaskIntoConstraints = false
        capturedImageView.contentMode = .scaleAspectFill
        capturedImageView.clipsToBounds = true
        capturedImageView.isHidden = true
        view.addSubview(capturedImageView)

        guideView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(guideView)

        setupChrome()
        setupUploadOverlay()

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            capturedImageView.topAnchor.constraint(equalTo: view.topAnchor),
            capturedImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            capturedImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            capturedImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            guideView.topAnchor.constraint(equalTo: view.topAnchor),
            guideView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            guideView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            guideView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupChrome() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor(hex: "#FFFFFF")
        closeButton.backgroundColor = UIColor(hex: "#07101A", alpha: 0.62)
        closeButton.layer.cornerRadius = 18
        closeButton.layer.cornerCurve = .continuous
        closeButton.accessibilityLabel = "Cancelar captura"
        closeButton.addTarget(self, action: #selector(cancelarTapped), for: .touchUpInside)

        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.text = "Posicione seu rosto dentro da marcação"
        instructionLabel.textColor = UIColor(hex: "#FFFFFF")
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionLabel.applyScaledFont(size: 15, weight: .semibold, textStyle: .body)

        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = UIColor(hex: "#FFFFFF", alpha: 0.18)
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor(hex: "#FFFFFF").cgColor
        captureButton.accessibilityLabel = "Capturar selfie"
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)

        let innerCircle = UIView()
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        innerCircle.isUserInteractionEnabled = false
        innerCircle.backgroundColor = UIColor(hex: "#FFFFFF")
        innerCircle.layer.cornerRadius = 24
        captureButton.addSubview(innerCircle)

        retakeButton.translatesAutoresizingMaskIntoConstraints = false
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)

        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)

        configureReviewButtons()

        let reviewStack = UIStackView(arrangedSubviews: [retakeButton, confirmButton])
        reviewStack.translatesAutoresizingMaskIntoConstraints = false
        reviewStack.axis = .horizontal
        reviewStack.spacing = 12
        reviewStack.distribution = .fillEqually
        reviewStack.isHidden = true
        reviewStack.accessibilityIdentifier = "selfie.review.actions"

        view.addSubview(closeButton)
        view.addSubview(instructionLabel)
        view.addSubview(captureButton)
        view.addSubview(reviewStack)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalMargin),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalMargin),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalMargin),
            instructionLabel.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -22),

            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Layout.bottomInset),
            captureButton.widthAnchor.constraint(equalToConstant: Layout.captureButtonSize),
            captureButton.heightAnchor.constraint(equalToConstant: Layout.captureButtonSize),

            innerCircle.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: 48),
            innerCircle.heightAnchor.constraint(equalToConstant: 48),

            reviewStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalMargin),
            reviewStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalMargin),
            reviewStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Layout.bottomInset),
            reviewStack.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func configureReviewButtons() {
        var retakeConfiguration = UIButton.Configuration.tinted()
        retakeConfiguration.cornerStyle = .capsule
        retakeConfiguration.baseBackgroundColor = UIColor(hex: "#FFFFFF", alpha: 0.16)
        retakeConfiguration.baseForegroundColor = UIColor(hex: "#FFFFFF")
        retakeConfiguration.title = "Refazer"
        retakeConfiguration.image = UIImage(systemName: "arrow.counterclockwise")
        retakeConfiguration.imagePadding = 8
        retakeButton.configuration = retakeConfiguration
        retakeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)

        var confirmConfiguration = UIButton.Configuration.filled()
        confirmConfiguration.cornerStyle = .capsule
        confirmConfiguration.baseBackgroundColor = UIColor(hex: "#2E87C8")
        confirmConfiguration.baseForegroundColor = UIColor(hex: "#FFFFFF")
        confirmConfiguration.title = "Confirmar"
        confirmConfiguration.image = UIImage(systemName: "checkmark.circle.fill")
        confirmConfiguration.imagePadding = 8
        confirmButton.configuration = confirmConfiguration
        confirmButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
    }

    private func setupUploadOverlay() {
        uploadOverlay.translatesAutoresizingMaskIntoConstraints = false
        uploadOverlay.backgroundColor = UIColor(hex: "#050B12", alpha: 0.78)
        uploadOverlay.isHidden = true

        uploadIndicator.translatesAutoresizingMaskIntoConstraints = false
        uploadIndicator.color = UIColor(hex: "#FFFFFF")

        uploadLabel.translatesAutoresizingMaskIntoConstraints = false
        uploadLabel.text = "Enviando selfie…"
        uploadLabel.textColor = UIColor(hex: "#FFFFFF")
        uploadLabel.textAlignment = .center
        uploadLabel.applyScaledFont(size: 16, weight: .semibold, textStyle: .body)

        uploadOverlay.addSubview(uploadIndicator)
        uploadOverlay.addSubview(uploadLabel)
        view.addSubview(uploadOverlay)

        NSLayoutConstraint.activate([
            uploadOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            uploadOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            uploadOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            uploadOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            uploadIndicator.centerXAnchor.constraint(equalTo: uploadOverlay.centerXAnchor),
            uploadIndicator.centerYAnchor.constraint(equalTo: uploadOverlay.centerYAnchor, constant: -18),

            uploadLabel.topAnchor.constraint(equalTo: uploadIndicator.bottomAnchor, constant: 14),
            uploadLabel.leadingAnchor.constraint(equalTo: uploadOverlay.leadingAnchor, constant: Layout.horizontalMargin),
            uploadLabel.trailingAnchor.constraint(equalTo: uploadOverlay.trailingAnchor, constant: -Layout.horizontalMargin)
        ])
    }

    // MARK: - Camera

    private func requestCameraAccessIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    granted ? self.configureSession() : self.showCameraDeniedAlert()
                }
            }
        case .denied, .restricted:
            showCameraDeniedAlert()
        @unknown default:
            showCameraDeniedAlert()
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isSessionConfigured else { return }

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .photo

            do {
                guard
                    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                else {
                    DispatchQueue.main.async { self.showSimpleToast("Câmera frontal indisponível.", style: .error) }
                    self.captureSession.commitConfiguration()
                    return
                }

                let input = try AVCaptureDeviceInput(device: device)
                guard self.captureSession.canAddInput(input) else {
                    DispatchQueue.main.async { self.showSimpleToast("Não foi possível acessar a câmera.", style: .error) }
                    self.captureSession.commitConfiguration()
                    return
                }
                self.captureSession.addInput(input)

                guard self.captureSession.canAddOutput(self.photoOutput) else {
                    DispatchQueue.main.async { self.showSimpleToast("Não foi possível configurar a captura.", style: .error) }
                    self.captureSession.commitConfiguration()
                    return
                }
                self.captureSession.addOutput(self.photoOutput)

                self.captureSession.commitConfiguration()
                self.isSessionConfigured = true

                DispatchQueue.main.async {
                    self.previewView.previewLayer.session = self.captureSession
                    if let connection = self.previewView.previewLayer.connection, connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = true
                    }
                    self.startSessionIfNeeded()
                }
            } catch {
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    private func startSessionIfNeeded() {
        guard isSessionConfigured, capturedImage == nil else { return }
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning == false else { return }
            self.captureSession.startRunning()
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    private func showCameraDeniedAlert() {
        let alert = UIAlertController(
            title: "Câmera bloqueada",
            message: "Autorize o acesso à câmera nos Ajustes para capturar a selfie de verificação.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            self?.onCancelar?()
            self?.dismiss(animated: true)
        })
        alert.addAction(UIAlertAction(title: "Abrir Ajustes", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    // MARK: - Actions

    @objc private func cancelarTapped() {
        onCancelar?()
    }

    @objc private func captureTapped() {
        guard isSessionConfigured else {
            showSimpleToast("A câmera ainda está carregando.", style: .info)
            return
        }
        captureButton.isEnabled = false

        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        if let connection = photoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = true
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func retakeTapped() {
        capturedImage = nil
        capturedImageView.image = nil
        capturedImageView.isHidden = true
        guideView.isHidden = false
        captureButton.isHidden = false
        instructionLabel.text = "Posicione seu rosto dentro da marcação"
        setReviewButtonsHidden(true)
        startSessionIfNeeded()
    }

    @objc private func confirmTapped() {
        guard let capturedImage else { return }
        guard let imageData = capturedImage.jpegDataUnderLimit(maxBytes: 500 * 1024) else {
            showSimpleToast("Não foi possível preparar a selfie.", style: .error)
            return
        }

        setUploading(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.enviarSelfie(id: self.verificacaoID, imageData: imageData)
                await MainActor.run {
                    self.setUploading(false)
                    self.showSimpleToast("Selfie enviada com sucesso.", style: .success)
                    self.onConcluido?()
                }
            } catch {
                await MainActor.run {
                    self.setUploading(false)
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    // MARK: - State

    private func displayCapturedImage(_ image: UIImage) {
        capturedImage = image.normalizedForJPEG()
        capturedImageView.image = capturedImage
        capturedImageView.isHidden = false
        guideView.isHidden = true
        captureButton.isHidden = true
        instructionLabel.text = "Revise a selfie antes de enviar"
        setReviewButtonsHidden(false)
        stopSession()
    }

    private func setReviewButtonsHidden(_ hidden: Bool) {
        view.subviews
            .compactMap { $0 as? UIStackView }
            .first { $0.accessibilityIdentifier == "selfie.review.actions" }?
            .isHidden = hidden
    }

    private func setUploading(_ uploading: Bool) {
        uploadOverlay.isHidden = !uploading
        uploading ? uploadIndicator.startAnimating() : uploadIndicator.stopAnimating()
        confirmButton.isEnabled = !uploading
        retakeButton.isEnabled = !uploading
        closeButton.isEnabled = !uploading
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension SelfieCaptureViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.captureButton.isEnabled = true

            if let error {
                self.showSimpleToast(error.localizedDescription, style: .error)
                return
            }

            guard
                let data = photo.fileDataRepresentation(),
                let image = UIImage(data: data)
            else {
                self.showSimpleToast("Não foi possível capturar a selfie.", style: .error)
                return
            }

            self.displayCapturedImage(image)
        }
    }
}

// MARK: - Preview and overlay views

private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

private final class SelfieOvalGuideView: UIView {
    private let dimLayer = CAShapeLayer()
    private let strokeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(dimLayer)
        layer.addSublayer(strokeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let guideWidth = min(bounds.width * 0.74, 300)
        let guideHeight = guideWidth * 1.28
        let guideRect = CGRect(
            x: (bounds.width - guideWidth) / 2,
            y: (bounds.height - guideHeight) / 2 - 18,
            width: guideWidth,
            height: guideHeight
        )

        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(ovalIn: guideRect))
        path.usesEvenOddFillRule = true

        dimLayer.frame = bounds
        dimLayer.path = path.cgPath
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = UIColor(hex: "#000000", alpha: 0.42).cgColor

        strokeLayer.frame = bounds
        strokeLayer.path = UIBezierPath(ovalIn: guideRect).cgPath
        strokeLayer.fillColor = UIColor.clear.cgColor
        strokeLayer.strokeColor = UIColor(hex: "#FFFFFF", alpha: 0.92).cgColor
        strokeLayer.lineWidth = 3
        strokeLayer.lineDashPattern = [10, 8]
    }
}

// MARK: - JPEG preparation

private extension UIImage {
    func normalizedForJPEG() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func jpegDataUnderLimit(maxBytes: Int) -> Data? {
        var image = normalizedForJPEG()
        var quality: CGFloat = 0.9

        while quality >= 0.35 {
            if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.08
        }

        var maxDimension = max(image.size.width, image.size.height)
        while maxDimension > 320 {
            let scale = max((maxDimension - 240) / maxDimension, 0.35)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image = image.resized(to: newSize)
            maxDimension = max(image.size.width, image.size.height)

            if let data = image.jpegData(compressionQuality: 0.72), data.count <= maxBytes {
                return data
            }
            if let data = image.jpegData(compressionQuality: 0.55), data.count <= maxBytes {
                return data
            }
        }

        guard let finalData = image.jpegData(compressionQuality: 0.42), finalData.count <= maxBytes else {
            return nil
        }
        return finalData
    }

    private func resized(to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
