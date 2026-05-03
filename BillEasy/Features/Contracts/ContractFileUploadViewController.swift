import UIKit
import UniformTypeIdentifiers

/// Aqui eu replico o modal de upload do fluxo Kotlin antes de enviar o arquivo para a IA.
final class ContractFileUploadViewController: UIViewController, UIDocumentPickerDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate, UIAdaptivePresentationControllerDelegate {
    var onDismissWithoutSelection: (() -> Void)?
    var onConfirmSelectedFile: ((URL) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let contentStack = UIStackView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let dropZoneButton = UIButton(type: .system)
    private let dropZoneBorderLayer = CAShapeLayer()
    private let filesOptionButton = UIButton(type: .system)
    private let cameraOptionButton = UIButton(type: .system)
    private let selectedFileCard = UIView()
    private let selectedFileIconContainer = UIView()
    private let selectedFileIconView = UIImageView()
    private let selectedFileNameLabel = UILabel()
    private let selectedFileSizeLabel = UILabel()
    private let removeFileButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)

    private var selectedFileURL: URL?
    private var didConfirmSelection = false

    override func viewDidLoad() {
        super.viewDidLoad()
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        presentationController?.delegate = self
        setupView()
        setupLayout()
        refreshSelectedFileState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateDropZoneBorder()
    }

    private func setupView() {
        view.backgroundColor = UIColor(hex: "#FFFFFF")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false

        contentView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Enviar Documento"
        titleLabel.textColor = UIColor(hex: "#283344")
        titleLabel.numberOfLines = 0
        titleLabel.applyScaledFont(size: 24, weight: .bold, textStyle: .title2)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Selecione um contrato ou documento para análise inteligente"
        subtitleLabel.textColor = UIColor(hex: "#6E7F95")
        subtitleLabel.numberOfLines = 0
        subtitleLabel.applyScaledFont(size: 15, weight: .medium, textStyle: .body)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.tintColor = UIColor(hex: "#6E7F95")
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        dropZoneButton.translatesAutoresizingMaskIntoConstraints = false
        dropZoneButton.backgroundColor = UIColor(hex: "#EAF4FB")
        dropZoneButton.layer.cornerRadius = 22
        dropZoneButton.layer.cornerCurve = .continuous
        dropZoneButton.layer.borderWidth = 0
        dropZoneButton.addTarget(self, action: #selector(filesTapped), for: .touchUpInside)

        let dropIconBackground = UIView()
        dropIconBackground.translatesAutoresizingMaskIntoConstraints = false
        dropIconBackground.backgroundColor = UIColor(hex: "#D8EDF8")
        dropIconBackground.layer.cornerRadius = 32
        dropIconBackground.layer.cornerCurve = .continuous

        let dropIcon = UIImageView(image: UIImage(systemName: "square.and.arrow.up"))
        dropIcon.translatesAutoresizingMaskIntoConstraints = false
        dropIcon.tintColor = UIColor(hex: "#1579A8")
        dropIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)

        let dropTitle = UILabel()
        dropTitle.translatesAutoresizingMaskIntoConstraints = false
        dropTitle.text = "Toque para selecionar um arquivo"
        dropTitle.textColor = UIColor(hex: "#1579A8")
        dropTitle.textAlignment = .center
        dropTitle.numberOfLines = 0
        dropTitle.applyScaledFont(size: 15, weight: .bold, textStyle: .headline)

        let dropFormats = UILabel()
        dropFormats.translatesAutoresizingMaskIntoConstraints = false
        dropFormats.text = "PDF, JPG, PNG, WEBP (máx. 10MB)"
        dropFormats.textColor = UIColor(hex: "#6E7F95")
        dropFormats.textAlignment = .center
        dropFormats.numberOfLines = 0
        dropFormats.applyScaledFont(size: 13, weight: .medium, textStyle: .footnote)

        dropZoneButton.addSubview(dropIconBackground)
        dropIconBackground.addSubview(dropIcon)
        dropZoneButton.addSubview(dropTitle)
        dropZoneButton.addSubview(dropFormats)

        NSLayoutConstraint.activate([
            dropIconBackground.centerXAnchor.constraint(equalTo: dropZoneButton.centerXAnchor),
            dropIconBackground.topAnchor.constraint(equalTo: dropZoneButton.topAnchor, constant: 30),
            dropIconBackground.widthAnchor.constraint(equalToConstant: 64),
            dropIconBackground.heightAnchor.constraint(equalToConstant: 64),

            dropIcon.centerXAnchor.constraint(equalTo: dropIconBackground.centerXAnchor),
            dropIcon.centerYAnchor.constraint(equalTo: dropIconBackground.centerYAnchor),

            dropTitle.topAnchor.constraint(equalTo: dropIconBackground.bottomAnchor, constant: 16),
            dropTitle.leadingAnchor.constraint(equalTo: dropZoneButton.leadingAnchor, constant: 24),
            dropTitle.trailingAnchor.constraint(equalTo: dropZoneButton.trailingAnchor, constant: -24),

            dropFormats.topAnchor.constraint(equalTo: dropTitle.bottomAnchor, constant: 6),
            dropFormats.leadingAnchor.constraint(equalTo: dropZoneButton.leadingAnchor, constant: 24),
            dropFormats.trailingAnchor.constraint(equalTo: dropZoneButton.trailingAnchor, constant: -24)
        ])

        configureQuickOption(filesOptionButton, icon: "doc", title: "Arquivos", action: #selector(filesTapped))
        configureQuickOption(cameraOptionButton, icon: "camera", title: "Câmera", action: #selector(cameraTapped))

        selectedFileCard.translatesAutoresizingMaskIntoConstraints = false
        selectedFileCard.backgroundColor = UIColor(hex: "#EAF4FB")
        selectedFileCard.layer.cornerRadius = 16
        selectedFileCard.layer.cornerCurve = .continuous
        selectedFileCard.layer.borderWidth = 0

        selectedFileIconContainer.translatesAutoresizingMaskIntoConstraints = false
        selectedFileIconContainer.backgroundColor = UIColor(hex: "#D8EDF8")
        selectedFileIconContainer.layer.cornerRadius = 12
        selectedFileIconContainer.layer.cornerCurve = .continuous

        selectedFileIconView.translatesAutoresizingMaskIntoConstraints = false
        selectedFileIconView.tintColor = UIColor(hex: "#1579A8")
        selectedFileIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)

        selectedFileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        selectedFileNameLabel.textColor = UIColor(hex: "#283344")
        selectedFileNameLabel.numberOfLines = 1
        selectedFileNameLabel.applyScaledFont(size: 15, weight: .bold, textStyle: .headline)

        selectedFileSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        selectedFileSizeLabel.textColor = UIColor(hex: "#6E7F95")
        selectedFileSizeLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .footnote)

        removeFileButton.translatesAutoresizingMaskIntoConstraints = false
        removeFileButton.tintColor = UIColor(hex: "#C94D5D")
        removeFileButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        removeFileButton.accessibilityLabel = "Remover arquivo"
        removeFileButton.addTarget(self, action: #selector(removeSelectedFile), for: .touchUpInside)

        selectedFileCard.addSubview(selectedFileIconContainer)
        selectedFileIconContainer.addSubview(selectedFileIconView)
        selectedFileCard.addSubview(selectedFileNameLabel)
        selectedFileCard.addSubview(selectedFileSizeLabel)
        selectedFileCard.addSubview(removeFileButton)

        NSLayoutConstraint.activate([
            selectedFileIconContainer.leadingAnchor.constraint(equalTo: selectedFileCard.leadingAnchor, constant: 16),
            selectedFileIconContainer.centerYAnchor.constraint(equalTo: selectedFileCard.centerYAnchor),
            selectedFileIconContainer.widthAnchor.constraint(equalToConstant: 48),
            selectedFileIconContainer.heightAnchor.constraint(equalToConstant: 48),

            selectedFileIconView.centerXAnchor.constraint(equalTo: selectedFileIconContainer.centerXAnchor),
            selectedFileIconView.centerYAnchor.constraint(equalTo: selectedFileIconContainer.centerYAnchor),

            selectedFileNameLabel.topAnchor.constraint(equalTo: selectedFileCard.topAnchor, constant: 16),
            selectedFileNameLabel.leadingAnchor.constraint(equalTo: selectedFileIconContainer.trailingAnchor, constant: 12),
            selectedFileNameLabel.trailingAnchor.constraint(equalTo: removeFileButton.leadingAnchor, constant: -12),

            selectedFileSizeLabel.topAnchor.constraint(equalTo: selectedFileNameLabel.bottomAnchor, constant: 2),
            selectedFileSizeLabel.leadingAnchor.constraint(equalTo: selectedFileNameLabel.leadingAnchor),
            selectedFileSizeLabel.trailingAnchor.constraint(equalTo: selectedFileNameLabel.trailingAnchor),
            selectedFileSizeLabel.bottomAnchor.constraint(equalTo: selectedFileCard.bottomAnchor, constant: -16),

            removeFileButton.trailingAnchor.constraint(equalTo: selectedFileCard.trailingAnchor, constant: -10),
            removeFileButton.centerYAnchor.constraint(equalTo: selectedFileCard.centerYAnchor),
            removeFileButton.widthAnchor.constraint(equalToConstant: 32),
            removeFileButton.heightAnchor.constraint(equalToConstant: 32)
        ])

        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.backgroundColor = UIColor(hex: "#1579A8")
        confirmButton.layer.cornerRadius = 20
        confirmButton.layer.cornerCurve = .continuous
        confirmButton.setTitle("Analisar Documento", for: .normal)
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.titleLabel?.applyScaledFont(size: 17, weight: .bold, textStyle: .headline)
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        confirmButton.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let headerRow = UIView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(titleLabel)
        headerRow.addSubview(subtitleLabel)
        headerRow.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: headerRow.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),

            closeButton.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        let quickOptionsRow = UIStackView(arrangedSubviews: [filesOptionButton, cameraOptionButton])
        quickOptionsRow.translatesAutoresizingMaskIntoConstraints = false
        quickOptionsRow.axis = .horizontal
        quickOptionsRow.spacing = 12
        quickOptionsRow.distribution = .fillEqually

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(contentStack)

        contentStack.addArrangedSubview(headerRow)
        contentStack.addArrangedSubview(dropZoneButton)
        contentStack.addArrangedSubview(quickOptionsRow)
        contentStack.addArrangedSubview(selectedFileCard)
        contentStack.addArrangedSubview(confirmButton)

        contentStack.setCustomSpacing(24, after: headerRow)
        contentStack.setCustomSpacing(16, after: dropZoneButton)
        contentStack.setCustomSpacing(24, after: quickOptionsRow)
        contentStack.setCustomSpacing(24, after: selectedFileCard)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),

            dropZoneButton.heightAnchor.constraint(equalToConstant: 200),
            filesOptionButton.heightAnchor.constraint(equalToConstant: 72),
            cameraOptionButton.heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    private func configureQuickOption(_ button: UIButton, icon: String, title: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor(hex: "#EEF3F8")
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 0
        button.addTarget(self, action: action, for: .touchUpInside)

        let imageView = UIImageView(image: UIImage(systemName: icon))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = UIColor(hex: "#1579A8")
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.textColor = UIColor(hex: "#283344")
        label.textAlignment = .center
        label.applyScaledFont(size: 14, weight: .semibold, textStyle: .subheadline)

        button.addSubview(imageView)
        button.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            imageView.trailingAnchor.constraint(equalTo: button.centerXAnchor, constant: -6),

            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -12)
        ])
    }

    private func refreshSelectedFileState() {
        let hasFile = selectedFileURL != nil
        selectedFileCard.isHidden = !hasFile
        confirmButton.isEnabled = hasFile
        confirmButton.alpha = hasFile ? 1 : 0.5

        guard let selectedFileURL else { return }
        selectedFileIconView.image = fileIcon(for: selectedFileURL)
        selectedFileNameLabel.text = selectedFileURL.lastPathComponent
        selectedFileSizeLabel.text = formattedFileSize(for: selectedFileURL)
    }

    private func updateDropZoneBorder() {
        dropZoneBorderLayer.removeFromSuperlayer()
        dropZoneBorderLayer.frame = dropZoneButton.bounds
        dropZoneBorderLayer.fillColor = nil
        dropZoneBorderLayer.strokeColor = UIColor(hex: "#9FC8DF").cgColor
        dropZoneBorderLayer.lineWidth = 3
        dropZoneBorderLayer.lineDashPattern = [14, 10]
        dropZoneBorderLayer.path = UIBezierPath(
            roundedRect: dropZoneButton.bounds.insetBy(dx: 1, dy: 1),
            cornerRadius: 22
        ).cgPath
        dropZoneButton.layer.addSublayer(dropZoneBorderLayer)
    }

    private func fileIcon(for url: URL) -> UIImage? {
        let path = url.lastPathComponent.lowercased()
        let symbolName: String
        if path.hasSuffix(".pdf") {
            symbolName = "doc.text"
        } else if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") || path.hasSuffix(".png") || path.hasSuffix(".webp") {
            symbolName = "photo"
        } else {
            symbolName = "doc"
        }
        return UIImage(systemName: symbolName)
    }

    private func formattedFileSize(for url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    @objc private func closeTapped() {
        dismiss(animated: true) { [weak self] in
            guard let self, self.didConfirmSelection == false else { return }
            self.onDismissWithoutSelection?()
        }
    }

    @objc private func filesTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func cameraTapped() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            let alert = UIAlertController(
                title: "Câmera indisponível",
                message: "Esse dispositivo não permite capturar um documento agora.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        present(picker, animated: true)
    }

    @objc private func removeSelectedFile() {
        selectedFileURL = nil
        refreshSelectedFileState()
    }

    @objc private func confirmTapped() {
        guard let selectedFileURL else { return }
        didConfirmSelection = true
        dismiss(animated: true) { [weak self] in
            self?.onConfirmSelectedFile?(selectedFileURL)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        selectedFileURL = urls.first
        refreshSelectedFileState()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        defer { picker.dismiss(animated: true) }
        guard let image = info[.originalImage] as? UIImage,
              let data = image.jpegData(compressionQuality: 0.92) else {
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("camera-contract-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        do {
            try data.write(to: tempURL, options: .atomic)
            selectedFileURL = tempURL
            refreshSelectedFileState()
        } catch {
            let alert = UIAlertController(
                title: "Não consegui preparar a imagem",
                message: "Tente novamente com outro arquivo.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if didConfirmSelection == false {
            onDismissWithoutSelection?()
        }
    }
}
