import AVFoundation
import UIKit

struct ContractAudioCaptureResult {
    let draft: AIContractDraft
    let answers: [ContractAudioCaptureViewController.AudioField: String]
    let combinedText: String
}

/// Aqui eu guio a captura por áudio usando o microfone do usuário e as mesmas rotas do backend web.
final class ContractAudioCaptureViewController: UIViewController {
    enum AudioField: Int, CaseIterable, Hashable {
        case businessType
        case subject
        case description
        case amount
        case dueDate
        case creditorName
        case creditorDocument
        case debtorName
        case debtorDocument
        case paymentMethod

        var title: String {
            switch self {
            case .businessType: return "Tipo do Negócio"
            case .subject: return "Assunto do Contrato"
            case .description: return "Descrição do Acordo"
            case .amount: return "Valor Total"
            case .dueDate: return "1º Vencimento"
            case .creditorName: return "Nome do Credor"
            case .creditorDocument: return "CPF/CNPJ do Credor"
            case .debtorName: return "Nome do Devedor"
            case .debtorDocument: return "CPF/CNPJ do Devedor"
            case .paymentMethod: return "Forma de Pagamento"
            }
        }

        var prompt: String {
            switch self {
            case .businessType: return "Ex: Aluguel, Empréstimo, Prestação de Serviço"
            case .subject: return "Ex: Venda de carro, cobrança de aluguel"
            case .description: return "Descreva o acordo com o máximo de detalhes"
            case .amount: return "Ex: quatro mil e quinhentos reais"
            case .dueDate: return "Ex: quinze de agosto de dois mil e vinte e cinco"
            case .creditorName: return "Fale o nome completo do credor"
            case .creditorDocument: return "Fale o CPF ou CNPJ do credor"
            case .debtorName: return "Fale o nome completo do devedor"
            case .debtorDocument: return "Fale o CPF ou CNPJ do devedor"
            case .paymentMethod: return "Ex: Pix, boleto ou cartão"
            }
        }
    }

    var onCompletion: ((ContractAudioCaptureResult) -> Void)?

    private let aiService: AIExtractionService
    private let dimmingView = UIView()
    private let cardView = UIView()
    private let contentScrollView = UIScrollView()
    private let contentContainerView = UIView()
    private let closeButton = UIButton(type: .system)
    private let progressLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let promptCard = UIView()
    private let promptLeadLabel = UILabel()
    private let promptTitleLabel = UILabel()
    private let promptExampleLabel = UILabel()
    private let microphoneButton = UIButton(type: .system)
    private let helperLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let fieldsStack = UIStackView()

    private var fieldButtons: [AudioField: UIButton] = [:]
    private var answers: [AudioField: String] = [:]
    private var currentField: AudioField = .businessType
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var isRecording = false
    private var isProcessing = false

    init(aiService: AIExtractionService) {
        self.aiService = aiService
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overCurrentContext
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupLayout()
        refreshUI()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopRecordingIfNeeded(cancel: true)
    }

    private func setupView() {
        view.backgroundColor = .clear

        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.42)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor(hex: "#FFFFFF")
        cardView.layer.cornerRadius = 24
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.18
        cardView.layer.shadowOffset = CGSize(width: 0, height: 16)
        cardView.layer.shadowRadius = 28

        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.showsVerticalScrollIndicator = false
        contentScrollView.alwaysBounceVertical = true

        contentContainerView.translatesAutoresizingMaskIntoConstraints = false

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor(hex: "#6A7A91")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.textColor = UIColor(hex: "#6A7A91")
        progressLabel.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)
        progressLabel.textAlignment = .right

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = UIColor(hex: "#E8F2FA")
        progressView.progressTintColor = UIColor(fixedHex: "#2C90BF")
        progressView.layer.cornerRadius = 4
        progressView.clipsToBounds = true

        promptCard.translatesAutoresizingMaskIntoConstraints = false
        promptCard.backgroundColor = UIColor(hex: "#F3F7FB")
        promptCard.layer.cornerRadius = 16
        promptCard.layer.cornerCurve = .continuous
        promptCard.layer.borderWidth = 1
        promptCard.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor

        promptLeadLabel.translatesAutoresizingMaskIntoConstraints = false
        promptLeadLabel.text = "DIGA EM VOZ ALTA:"
        promptLeadLabel.textAlignment = .center
        promptLeadLabel.textColor = UIColor(hex: "#6A7A91")
        promptLeadLabel.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)

        promptTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        promptTitleLabel.textAlignment = .center
        promptTitleLabel.textColor = UIColor(hex: "#252E3A")
        promptTitleLabel.applyScaledFont(size: 22, weight: .black, textStyle: .title2)
        promptTitleLabel.numberOfLines = 2

        promptExampleLabel.translatesAutoresizingMaskIntoConstraints = false
        promptExampleLabel.textAlignment = .center
        promptExampleLabel.textColor = UIColor(hex: "#6A7A91")
        promptExampleLabel.applyScaledFont(size: 15, weight: .medium, textStyle: .body)
        promptExampleLabel.numberOfLines = 0

        microphoneButton.translatesAutoresizingMaskIntoConstraints = false
        microphoneButton.backgroundColor = UIColor(fixedHex: "#0E6D94")
        microphoneButton.tintColor = .white
        microphoneButton.layer.cornerRadius = 40
        microphoneButton.layer.cornerCurve = .continuous
        microphoneButton.layer.shadowColor = UIColor(fixedHex: "#0E6D94").cgColor
        microphoneButton.layer.shadowOpacity = 0.28
        microphoneButton.layer.shadowOffset = CGSize(width: 0, height: 10)
        microphoneButton.layer.shadowRadius = 20
        microphoneButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        microphoneButton.imageView?.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        microphoneButton.addTarget(self, action: #selector(microphoneTapped), for: .touchUpInside)
        microphoneButton.accessibilityIdentifier = "contracts.audio.recordButton"

        helperLabel.translatesAutoresizingMaskIntoConstraints = false
        helperLabel.textAlignment = .center
        helperLabel.textColor = UIColor(hex: "#607993")
        helperLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = UIColor(fixedHex: "#0E6D94")
        activityIndicator.hidesWhenStopped = true

        fieldsStack.translatesAutoresizingMaskIntoConstraints = false
        fieldsStack.axis = .vertical
        fieldsStack.spacing = 8

        let header = makeHeader()
        let promptHeader = makeMiniLabel("PROGRESSO")
        let fieldsHeader = makeMiniLabel("CAMPOS DO CONTRATO")

        view.addSubview(dimmingView)
        view.addSubview(cardView)
        cardView.addSubview(header)
        cardView.addSubview(contentScrollView)
        contentScrollView.addSubview(contentContainerView)
        contentContainerView.addSubview(promptHeader)
        contentContainerView.addSubview(progressLabel)
        contentContainerView.addSubview(progressView)
        contentContainerView.addSubview(promptCard)
        promptCard.addSubview(promptLeadLabel)
        promptCard.addSubview(promptTitleLabel)
        promptCard.addSubview(promptExampleLabel)
        contentContainerView.addSubview(microphoneButton)
        contentContainerView.addSubview(helperLabel)
        contentContainerView.addSubview(fieldsHeader)
        contentContainerView.addSubview(fieldsStack)
        contentContainerView.addSubview(activityIndicator)

        for field in AudioField.allCases {
            let button = makeFieldButton(for: field)
            fieldButtons[field] = button
            fieldsStack.addArrangedSubview(button)
        }

        let preferredCardHeight = cardView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.74)
        preferredCardHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            preferredCardHeight,
            cardView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.74),

            header.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 22),
            header.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),

            contentScrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            contentScrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),

            contentContainerView.topAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.topAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.bottomAnchor),
            contentContainerView.widthAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.widthAnchor),

            promptHeader.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            promptHeader.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: 18),

            progressLabel.centerYAnchor.constraint(equalTo: promptHeader.centerYAnchor),
            progressLabel.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -18),

            progressView.topAnchor.constraint(equalTo: promptHeader.bottomAnchor, constant: 8),
            progressView.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: 18),
            progressView.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -18),
            progressView.heightAnchor.constraint(equalToConstant: 8),

            promptCard.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 18),
            promptCard.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: 18),
            promptCard.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -18),

            promptLeadLabel.topAnchor.constraint(equalTo: promptCard.topAnchor, constant: 18),
            promptLeadLabel.leadingAnchor.constraint(equalTo: promptCard.leadingAnchor, constant: 16),
            promptLeadLabel.trailingAnchor.constraint(equalTo: promptCard.trailingAnchor, constant: -16),

            promptTitleLabel.topAnchor.constraint(equalTo: promptLeadLabel.bottomAnchor, constant: 10),
            promptTitleLabel.leadingAnchor.constraint(equalTo: promptCard.leadingAnchor, constant: 16),
            promptTitleLabel.trailingAnchor.constraint(equalTo: promptCard.trailingAnchor, constant: -16),

            promptExampleLabel.topAnchor.constraint(equalTo: promptTitleLabel.bottomAnchor, constant: 8),
            promptExampleLabel.leadingAnchor.constraint(equalTo: promptCard.leadingAnchor, constant: 16),
            promptExampleLabel.trailingAnchor.constraint(equalTo: promptCard.trailingAnchor, constant: -16),
            promptExampleLabel.bottomAnchor.constraint(equalTo: promptCard.bottomAnchor, constant: -18),

            microphoneButton.topAnchor.constraint(equalTo: promptCard.bottomAnchor, constant: 18),
            microphoneButton.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
            microphoneButton.widthAnchor.constraint(equalToConstant: 80),
            microphoneButton.heightAnchor.constraint(equalToConstant: 80),

            helperLabel.topAnchor.constraint(equalTo: microphoneButton.bottomAnchor, constant: 14),
            helperLabel.centerXAnchor.constraint(equalTo: contentContainerView.centerXAnchor),
            helperLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentContainerView.leadingAnchor, constant: 18),
            helperLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentContainerView.trailingAnchor, constant: -18),

            fieldsHeader.topAnchor.constraint(equalTo: helperLabel.bottomAnchor, constant: 20),
            fieldsHeader.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: 18),

            fieldsStack.topAnchor.constraint(equalTo: fieldsHeader.bottomAnchor, constant: 8),
            fieldsStack.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor, constant: 18),
            fieldsStack.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -18),
            fieldsStack.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor, constant: -18),

            activityIndicator.centerXAnchor.constraint(equalTo: microphoneButton.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: microphoneButton.centerYAnchor)
        ])
    }

    private func setupLayout() {}

    private func makeHeader() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "mic"))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = UIColor(fixedHex: "#0E6D94")
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Gravação por Áudio"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 20, weight: .bold, textStyle: .title3)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor(hex: "#D7DEE8")

        container.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(closeButton)
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            separator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])

        return container
    }

    private func makeMiniLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = UIColor(hex: "#6A7A91")
        label.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)
        return label
    }

    private func makeFieldButton(for field: AudioField) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tag = field.rawValue
        button.contentHorizontalAlignment = .left
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.addTarget(self, action: #selector(fieldButtonTapped(_:)), for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true

        var config = UIButton.Configuration.plain()
        config.title = field.title
        config.image = UIImage(systemName: "circle")
        config.imagePadding = 10
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        button.configuration = config
        return button
    }

    private func refreshUI() {
        let answeredCount = answers.count
        progressLabel.text = "\(answeredCount)/\(AudioField.allCases.count)"
        progressView.progress = Float(answeredCount) / Float(AudioField.allCases.count)
        promptTitleLabel.text = currentField.title
        promptExampleLabel.text = currentField.prompt

        if isProcessing {
            helperLabel.text = "Transcrevendo áudio..."
        } else if isRecording {
            helperLabel.text = "Toque para finalizar"
        } else {
            helperLabel.text = "Toque para gravar"
        }

        microphoneButton.isEnabled = !isProcessing
        closeButton.isEnabled = !isProcessing
        if isProcessing {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        let iconName = isRecording ? "stop.fill" : "mic.fill"
        microphoneButton.setImage(UIImage(systemName: iconName), for: .normal)

        for field in AudioField.allCases {
            guard let button = fieldButtons[field] else { continue }
            let isSelected = field == currentField
            let isAnswered = answers[field]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            var config = button.configuration ?? UIButton.Configuration.plain()
            config.title = field.title
            config.image = UIImage(systemName: isAnswered ? "checkmark.circle.fill" : (isSelected ? "circle.inset.filled" : "circle"))
            config.baseForegroundColor = isSelected ? UIColor(hex: "#1579A8") : UIColor(hex: "#252E3A")
            button.configuration = config
            button.backgroundColor = isSelected ? UIColor(hex: "#E8F2FA") : UIColor(hex: "#FFFFFF")
            button.layer.borderColor = (isSelected ? UIColor(hex: "#2E87C8") : UIColor(hex: "#D7DEE8")).cgColor
        }
    }

    @objc private func fieldButtonTapped(_ sender: UIButton) {
        guard let field = AudioField(rawValue: sender.tag), !isRecording, !isProcessing else { return }
        currentField = field
        refreshUI()
    }

    @objc private func microphoneTapped() {
        if isRecording {
            finishRecordingAndTranscribe()
        } else {
            requestMicrophonePermissionAndStartIfPossible()
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func requestMicrophonePermissionAndStartIfPossible() {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            startRecording()
        case .denied:
            presentMicrophoneSettingsAlert()
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    granted ? self.startRecording() : self.presentMicrophoneSettingsAlert()
                }
            }
        @unknown default:
            presentMicrophoneSettingsAlert()
        }
    }

    private func startRecording() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("contract-audio-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            recorder.record()
            self.recorder = recorder
            self.recordingURL = url
            self.isRecording = true
            refreshUI()
        } catch {
            showSimpleToast("Não foi possível iniciar a gravação.", style: .error)
        }
    }

    private func finishRecordingAndTranscribe() {
        guard let recordingURL else { return }
        stopRecordingIfNeeded(cancel: false)
        isProcessing = true
        refreshUI()

        Task { [weak self] in
            guard let self else { return }

            do {
                let data = try Data(contentsOf: recordingURL)
                let jobID = try await aiService.submitAudioForTranscription(
                    audioData: data,
                    filename: recordingURL.lastPathComponent,
                    mimeType: "audio/m4a"
                )
                let transcription = try await aiService.waitForAudioTranscription(jobID: jobID)
                guard !Task.isCancelled else { return }

                let cleanedText = normalizeAnswer(
                    transcription.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    for: self.currentField
                )
                guard cleanedText.isEmpty == false else {
                    throw AIExtractionServiceError.emptyExtraction
                }

                await MainActor.run {
                    self.answers[self.currentField] = cleanedText
                    self.advanceOrFinishFlow()
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.refreshUI()
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }

            try? FileManager.default.removeItem(at: recordingURL)
        }
    }

    private func stopRecordingIfNeeded(cancel: Bool) {
        recorder?.stop()
        recorder = nil
        isRecording = false
        if cancel, let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
    }

    private func advanceOrFinishFlow() {
        if let nextField = AudioField(rawValue: currentField.rawValue + 1) {
            currentField = nextField
            isProcessing = false
            refreshUI()
            return
        }

        completeCapture()
    }

    private func completeCapture() {
        let combinedText = AudioField.allCases.compactMap { field -> String? in
            guard let answer = answers[field], answer.isEmpty == false else { return nil }
            return "\(field.title): \(answer)"
        }.joined(separator: "\n")

        Task { [weak self] in
            guard let self else { return }
            do {
                let draft = try await aiService.extractContractDraft(
                    fromText: combinedText,
                    context: "Extraia um rascunho de contrato a partir das respostas guiadas por áudio do app iOS."
                )
                await MainActor.run {
                    self.dismiss(animated: true) {
                        self.onCompletion?(ContractAudioCaptureResult(draft: draft, answers: self.answers, combinedText: combinedText))
                    }
                }
            } catch {
                let fallback = makeFallbackDraft(from: combinedText)
                await MainActor.run {
                    self.dismiss(animated: true) {
                        self.onCompletion?(ContractAudioCaptureResult(draft: fallback, answers: self.answers, combinedText: combinedText))
                    }
                }
            }
        }
    }

    @MainActor
    private func makeFallbackDraft(from combinedText: String) -> AIContractDraft {
        AIContractDraft(
            suggestedBusinessType: answers[.businessType],
            suggestedSubject: answers[.subject],
            suggestedDescription: answers[.description] ?? combinedText,
            totalValueText: answers[.amount].map(Formatters.normalizeCurrencyDisplay),
            installmentCount: nil,
            dueDateText: answers[.dueDate].map(Formatters.normalizeDateDisplay),
            creditorName: answers[.creditorName],
            creditorDocument: nil,
            creditorPhone: nil,
            debtorName: answers[.debtorName],
            debtorDocument: answers[.debtorDocument],
            debtorEmail: nil,
            debtorPhone: nil
        )
    }

    @MainActor
    private func normalizeAnswer(_ value: String, for field: AudioField) -> String {
        switch field {
        case .amount:
            return Formatters.normalizeCurrencyDisplay(value)
        case .creditorDocument, .debtorDocument:
            return Formatters.formatCPFOrCNPJ(value)
        case .dueDate:
            return Formatters.normalizeDateDisplay(value)
        default:
            return value
        }
    }

    private func presentMicrophoneSettingsAlert() {
        let alert = UIAlertController(
            title: "Microfone desativado",
            message: "Permita o acesso ao microfone em Ajustes para criar o contrato por áudio.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Agora não", style: .cancel))
        alert.addAction(UIAlertAction(title: "Abrir Ajustes", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }
}
