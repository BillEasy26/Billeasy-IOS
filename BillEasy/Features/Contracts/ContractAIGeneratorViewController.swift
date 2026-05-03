import PhotosUI
import UIKit

/// Aqui eu concentro a entrada de IA com um pop-up próprio, separado do fluxo de áudio.
final class ContractAIGeneratorViewController: UIViewController, UITextViewDelegate, PHPickerViewControllerDelegate {
    private enum InputMode: CaseIterable {
        case text
        case document

        var title: String {
            switch self {
            case .text: return "Texto"
            case .document: return "Documento"
            }
        }

        var iconName: String {
            switch self {
            case .text: return "text.alignleft"
            case .document: return "doc.viewfinder"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .text: return "contracts.aiGenerator.mode.text"
            case .document: return "contracts.aiGenerator.mode.document"
            }
        }
    }

    private enum Layout {
        static let horizontalInset: CGFloat = 18
        static let cardRadius: CGFloat = 24
        static let buttonHeight: CGFloat = 56
        static let minimumCardHeight: CGFloat = 580
        static let minimumScrollableHeight: CGFloat = 320
    }

    private let aiService: AIExtractionService
    private let initialText: String

    var onDraftGenerated: ((AIContractDraft) -> Void)?

    private let dimmingView = UIView()
    private let cardView = UIView()
    private let headerView = UIView()
    private let headerIconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let separatorView = UIView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let infoBanner = UIView()
    private let infoBannerIconView = UIImageView()
    private let infoBannerLabel = UILabel()
    private let modeTitleLabel = UILabel()
    private let modeStack = UIStackView()
    private let textModeButton = UIButton(type: .system)
    private let documentModeButton = UIButton(type: .system)
    private let textContainer = UIView()
    private let textHintLabel = UILabel()
    private let textView = UITextView()
    private let textPlaceholderLabel = UILabel()
    private let characterCountLabel = UILabel()
    private let documentContainer = UIView()
    private let documentHintLabel = UILabel()
    private let documentButton = UIButton(type: .system)
    private let documentPreviewCard = UIView()
    private let documentPreviewImageView = UIImageView()
    private let documentFileNameLabel = UILabel()
    private let documentRemoveButton = UIButton(type: .system)
    private let actionButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var selectedMode: InputMode = .text
    private var selectedImageData: Data?
    private var selectedImageName: String?
    private var generationTask: Task<Void, Never>?

    init(aiService: AIExtractionService, initialText: String) {
        self.aiService = aiService
        self.initialText = initialText
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overCurrentContext
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        generationTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupLayout()
        refreshModeSelection()
        refreshTextPlaceholder()
        refreshDocumentPreview()
        refreshGenerateButtonState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        animateEntranceIfNeeded()
    }

    private func setupView() {
        view.backgroundColor = .clear

        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.42)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.accessibilityIdentifier = "contracts.aiGenerator.card"
        cardView.backgroundColor = UIColor(hex: "#FFFFFF")
        cardView.layer.cornerRadius = Layout.cardRadius
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.18
        cardView.layer.shadowOffset = CGSize(width: 0, height: 16)
        cardView.layer.shadowRadius = 28

        headerView.translatesAutoresizingMaskIntoConstraints = false

        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        headerIconView.image = UIImage(systemName: "sparkles")
        headerIconView.tintColor = UIColor(fixedHex: "#FF7A21")
        headerIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Geração por IA"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 22, weight: .black, textStyle: .title3)
        titleLabel.accessibilityIdentifier = "contracts.aiGenerator.titleLabel"

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Descreva o caso ou envie um documento para a IA montar o contrato como no fluxo do web."
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textColor = UIColor(hex: "#607993")
        subtitleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor(hex: "#6A7A91")
        closeButton.accessibilityIdentifier = "contracts.aiGenerator.closeButton"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = UIColor(hex: "#D7DEE8")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive

        contentView.translatesAutoresizingMaskIntoConstraints = false

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 18

        configureInfoBanner()

        modeTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        modeTitleLabel.text = "COMO VOCÊ QUER GERAR O CONTRATO"
        modeTitleLabel.textColor = UIColor(hex: "#6A7A91")
        modeTitleLabel.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)

        modeStack.translatesAutoresizingMaskIntoConstraints = false
        modeStack.axis = .horizontal
        modeStack.spacing = 10
        modeStack.distribution = .fillEqually

        configureModeButton(textModeButton, mode: .text)
        configureModeButton(documentModeButton, mode: .document)

        configureTextContainer()
        configureDocumentContainer()
        configureActionButton()

        view.addSubview(dimmingView)
        view.addSubview(cardView)

        cardView.addSubview(headerView)
        headerView.addSubview(headerIconView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(subtitleLabel)
        headerView.addSubview(closeButton)
        cardView.addSubview(separatorView)
        cardView.addSubview(scrollView)
        cardView.addSubview(actionButton)
        actionButton.addSubview(activityIndicator)

        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)

        modeStack.addArrangedSubview(textModeButton)
        modeStack.addArrangedSubview(documentModeButton)

        stackView.addArrangedSubview(infoBanner)
        stackView.addArrangedSubview(modeTitleLabel)
        stackView.addArrangedSubview(modeStack)
        stackView.addArrangedSubview(textContainer)
        stackView.addArrangedSubview(documentContainer)
    }

    private func setupLayout() {
        let preferredHeight = cardView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.76)
        preferredHeight.priority = .defaultHigh
        let minimumHeight = cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.minimumCardHeight)
        minimumHeight.priority = .required

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
            preferredHeight,
            minimumHeight,

            headerView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 22),
            headerView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Layout.horizontalInset),
            headerView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Layout.horizontalInset),

            closeButton.topAnchor.constraint(equalTo: headerView.topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            headerIconView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 2),
            headerIconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerIconView.widthAnchor.constraint(equalToConstant: 22),
            headerIconView.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: headerIconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),

            separatorView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
            separatorView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1),

            actionButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Layout.horizontalInset),
            actionButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Layout.horizontalInset),
            actionButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),
            actionButton.heightAnchor.constraint(equalToConstant: Layout.buttonHeight),

            activityIndicator.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor, constant: -18),

            scrollView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -16),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.minimumScrollableHeight),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.horizontalInset),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.horizontalInset),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 190)
        ])
    }

    private func configureInfoBanner() {
        infoBanner.translatesAutoresizingMaskIntoConstraints = false
        infoBanner.backgroundColor = UIColor(hex: "#FFFBEF")
        infoBanner.layer.cornerRadius = 14
        infoBanner.layer.cornerCurve = .continuous
        infoBanner.layer.borderWidth = 1
        infoBanner.layer.borderColor = UIColor(hex: "#F0DCA5").cgColor

        infoBannerIconView.translatesAutoresizingMaskIntoConstraints = false
        infoBannerIconView.image = UIImage(systemName: "wand.and.stars")
        infoBannerIconView.tintColor = UIColor(fixedHex: "#C88A12")

        infoBannerLabel.translatesAutoresizingMaskIntoConstraints = false
        infoBannerLabel.numberOfLines = 0
        infoBannerLabel.text = "Escolha texto ou documento. O app usa as mesmas rotas do web para OCR e extração estruturada do contrato."
        infoBannerLabel.textColor = UIColor(hex: "#607993")
        infoBannerLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .callout)

        infoBanner.addSubview(infoBannerIconView)
        infoBanner.addSubview(infoBannerLabel)

        NSLayoutConstraint.activate([
            infoBannerIconView.leadingAnchor.constraint(equalTo: infoBanner.leadingAnchor, constant: 14),
            infoBannerIconView.topAnchor.constraint(equalTo: infoBanner.topAnchor, constant: 14),
            infoBannerIconView.widthAnchor.constraint(equalToConstant: 18),
            infoBannerIconView.heightAnchor.constraint(equalToConstant: 18),

            infoBannerLabel.topAnchor.constraint(equalTo: infoBanner.topAnchor, constant: 12),
            infoBannerLabel.leadingAnchor.constraint(equalTo: infoBannerIconView.trailingAnchor, constant: 10),
            infoBannerLabel.trailingAnchor.constraint(equalTo: infoBanner.trailingAnchor, constant: -14),
            infoBannerLabel.bottomAnchor.constraint(equalTo: infoBanner.bottomAnchor, constant: -12)
        ])
    }

    private func configureModeButton(_ button: UIButton, mode: InputMode) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = mode.accessibilityIdentifier
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        button.addTarget(self, action: #selector(modeButtonTapped(_:)), for: .touchUpInside)
        button.tag = mode == .text ? 0 : 1
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true

        let iconView = UIImageView(image: UIImage(systemName: mode.iconName))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = UIColor(hex: "#607993")
        iconView.isUserInteractionEnabled = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = mode.title
        label.textAlignment = .center
        label.textColor = UIColor(hex: "#607993")
        label.applyScaledFont(size: 15, weight: .bold, textStyle: .headline)
        label.isUserInteractionEnabled = false

        button.addSubview(iconView)
        button.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
    }

    private func configureTextContainer() {
        textContainer.translatesAutoresizingMaskIntoConstraints = false

        textHintLabel.translatesAutoresizingMaskIntoConstraints = false
        textHintLabel.numberOfLines = 0
        textHintLabel.text = "Descreva o acordo em linguagem natural. Exemplo: contrato de prestação de serviço, valor, vencimento, partes e forma de pagamento."
        textHintLabel.textColor = UIColor(hex: "#607993")
        textHintLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .callout)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = UIColor(hex: "#FFFFFF")
        textView.textColor = UIColor(hex: "#252E3A")
        textView.tintColor = UIColor(hex: "#1579A8")
        textView.layer.cornerRadius = 18
        textView.layer.cornerCurve = .continuous
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 14, bottom: 16, right: 14)
        textView.applyScaledFont(size: 15, weight: .regular, textStyle: .body)
        textView.delegate = self
        textView.accessibilityIdentifier = "contracts.aiGenerator.textView"
        textView.keyboardAppearance = UserDefaults.standard.bool(forKey: "billeasy.theme.dark_mode_enabled") ? .dark : .light
        textView.text = initialText

        textPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textPlaceholderLabel.numberOfLines = 0
        textPlaceholderLabel.text = "Exemplo: Quero um contrato de prestação de serviço para desenvolvimento de website, valor total de R$ 4.500,00, pagamento em parcela única e vencimento em 15/08/2025."
        textPlaceholderLabel.textColor = UIColor(hex: "#95A9BD")
        textPlaceholderLabel.applyScaledFont(size: 15, weight: .regular, textStyle: .body)
        textPlaceholderLabel.isUserInteractionEnabled = false

        characterCountLabel.translatesAutoresizingMaskIntoConstraints = false
        characterCountLabel.textColor = UIColor(hex: "#607993")
        characterCountLabel.textAlignment = .right
        characterCountLabel.applyScaledFont(size: 12, weight: .semibold, textStyle: .caption1)

        textContainer.addSubview(textHintLabel)
        textContainer.addSubview(textView)
        textView.addSubview(textPlaceholderLabel)
        textContainer.addSubview(characterCountLabel)

        NSLayoutConstraint.activate([
            textHintLabel.topAnchor.constraint(equalTo: textContainer.topAnchor),
            textHintLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            textHintLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),

            textView.topAnchor.constraint(equalTo: textHintLabel.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),

            textPlaceholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 16),
            textPlaceholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 18),
            textPlaceholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -18),

            characterCountLabel.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 8),
            characterCountLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
            characterCountLabel.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor)
        ])
    }

    private func configureDocumentContainer() {
        documentContainer.translatesAutoresizingMaskIntoConstraints = false

        documentHintLabel.translatesAutoresizingMaskIntoConstraints = false
        documentHintLabel.numberOfLines = 0
        documentHintLabel.text = "Envie uma imagem ou PDF do documento. O app usa /api/ia/extrair-de-imagem para pré-preencher o contrato igual ao Kotlin/web atual."
        documentHintLabel.textColor = UIColor(hex: "#607993")
        documentHintLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .callout)

        documentButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Selecionar documento"
        configuration.image = UIImage(systemName: "photo.on.rectangle")
        configuration.imagePlacement = .leading
        configuration.imagePadding = 10
        configuration.baseBackgroundColor = UIColor(hex: "#E8F2FA")
        configuration.baseForegroundColor = UIColor(hex: "#1579A8")
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        documentButton.configuration = configuration
        documentButton.applyScaledTitleFont(size: 15, weight: .bold, textStyle: .headline)
        documentButton.addTarget(self, action: #selector(documentButtonTapped), for: .touchUpInside)
        documentButton.accessibilityIdentifier = "contracts.aiGenerator.documentButton"

        documentPreviewCard.translatesAutoresizingMaskIntoConstraints = false
        documentPreviewCard.backgroundColor = UIColor(hex: "#FFFFFF")
        documentPreviewCard.layer.cornerRadius = 18
        documentPreviewCard.layer.cornerCurve = .continuous
        documentPreviewCard.layer.borderWidth = 1
        documentPreviewCard.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor

        documentPreviewImageView.translatesAutoresizingMaskIntoConstraints = false
        documentPreviewImageView.contentMode = .scaleAspectFit
        documentPreviewImageView.clipsToBounds = true
        documentPreviewImageView.layer.cornerRadius = 12
        documentPreviewImageView.layer.cornerCurve = .continuous
        documentPreviewImageView.backgroundColor = UIColor(hex: "#F7FAFD")

        documentFileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        documentFileNameLabel.numberOfLines = 2
        documentFileNameLabel.textColor = UIColor(hex: "#252E3A")
        documentFileNameLabel.applyScaledFont(size: 14, weight: .semibold, textStyle: .body)

        documentRemoveButton.translatesAutoresizingMaskIntoConstraints = false
        documentRemoveButton.setTitle("Remover", for: .normal)
        documentRemoveButton.setTitleColor(UIColor(hex: "#EF4444"), for: .normal)
        documentRemoveButton.applyScaledTitleFont(size: 13, weight: .semibold, textStyle: .callout)
        documentRemoveButton.addTarget(self, action: #selector(removeDocumentTapped), for: .touchUpInside)

        documentContainer.addSubview(documentHintLabel)
        documentContainer.addSubview(documentButton)
        documentContainer.addSubview(documentPreviewCard)
        documentPreviewCard.addSubview(documentPreviewImageView)
        documentPreviewCard.addSubview(documentFileNameLabel)
        documentPreviewCard.addSubview(documentRemoveButton)

        NSLayoutConstraint.activate([
            documentHintLabel.topAnchor.constraint(equalTo: documentContainer.topAnchor),
            documentHintLabel.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
            documentHintLabel.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),

            documentButton.topAnchor.constraint(equalTo: documentHintLabel.bottomAnchor, constant: 12),
            documentButton.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
            documentButton.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),
            documentButton.heightAnchor.constraint(equalToConstant: 52),

            documentPreviewCard.topAnchor.constraint(equalTo: documentButton.bottomAnchor, constant: 14),
            documentPreviewCard.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
            documentPreviewCard.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),
            documentPreviewCard.bottomAnchor.constraint(equalTo: documentContainer.bottomAnchor),

            documentPreviewImageView.topAnchor.constraint(equalTo: documentPreviewCard.topAnchor, constant: 14),
            documentPreviewImageView.leadingAnchor.constraint(equalTo: documentPreviewCard.leadingAnchor, constant: 14),
            documentPreviewImageView.widthAnchor.constraint(equalToConstant: 74),
            documentPreviewImageView.heightAnchor.constraint(equalToConstant: 74),

            documentFileNameLabel.topAnchor.constraint(equalTo: documentPreviewCard.topAnchor, constant: 16),
            documentFileNameLabel.leadingAnchor.constraint(equalTo: documentPreviewImageView.trailingAnchor, constant: 12),
            documentFileNameLabel.trailingAnchor.constraint(equalTo: documentPreviewCard.trailingAnchor, constant: -14),

            documentRemoveButton.leadingAnchor.constraint(equalTo: documentFileNameLabel.leadingAnchor),
            documentRemoveButton.topAnchor.constraint(equalTo: documentFileNameLabel.bottomAnchor, constant: 10),
            documentRemoveButton.bottomAnchor.constraint(lessThanOrEqualTo: documentPreviewCard.bottomAnchor, constant: -14),

            documentPreviewCard.bottomAnchor.constraint(greaterThanOrEqualTo: documentPreviewImageView.bottomAnchor, constant: 14)
        ])
    }

    private func configureActionButton() {
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Gerar contrato"
        configuration.image = UIImage(systemName: "sparkles")
        configuration.imagePlacement = .leading
        configuration.imagePadding = 10
        configuration.baseBackgroundColor = UIColor(hex: "#2495C5")
        configuration.baseForegroundColor = UIColor(hex: "#FFFFFF")
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        actionButton.configuration = configuration
        actionButton.applyScaledTitleFont(size: 17, weight: .bold, textStyle: .headline)
        actionButton.applyStableStateColors(
            normalBackground: UIColor(hex: "#2495C5"),
            normalForeground: UIColor(hex: "#FFFFFF"),
            disabledBackground: UIColor(hex: "#C7D4E2"),
            disabledForeground: UIColor(hex: "#FFFFFF")
        )
        actionButton.addTarget(self, action: #selector(generateTapped), for: .touchUpInside)
        actionButton.accessibilityIdentifier = "contracts.aiGenerator.generateButton"

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = UIColor(hex: "#FFFFFF")
    }

    private func refreshModeSelection() {
        styleModeButton(textModeButton, isSelected: selectedMode == .text)
        styleModeButton(documentModeButton, isSelected: selectedMode == .document)
        textContainer.isHidden = selectedMode != .text
        documentContainer.isHidden = selectedMode != .document
        refreshGenerateButtonState()
    }

    private func styleModeButton(_ button: UIButton, isSelected: Bool) {
        button.backgroundColor = isSelected ? UIColor(hex: "#E8F2FA") : UIColor(hex: "#FFFFFF")
        button.layer.borderColor = (isSelected ? UIColor(hex: "#2E87C8") : UIColor(hex: "#D7DEE8")).cgColor
        button.tintColor = isSelected ? UIColor(hex: "#1579A8") : UIColor(hex: "#607993")

        button.subviews.forEach { subview in
            if let imageView = subview as? UIImageView {
                imageView.tintColor = isSelected ? UIColor(hex: "#1579A8") : UIColor(hex: "#607993")
            }
            if let label = subview as? UILabel {
                label.textColor = isSelected ? UIColor(hex: "#1579A8") : UIColor(hex: "#607993")
            }
        }
    }

    private func refreshTextPlaceholder() {
        let normalized = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        textPlaceholderLabel.isHidden = normalized.isEmpty == false
        characterCountLabel.text = "\(normalized.count) caracteres"
    }

    private func refreshDocumentPreview() {
        let hasDocument = selectedImageData != nil
        documentPreviewCard.isHidden = !hasDocument
        documentFileNameLabel.text = selectedImageName ?? "Documento selecionado"
        refreshGenerateButtonState()
    }

    private func refreshGenerateButtonState() {
        let canGenerate: Bool
        switch selectedMode {
        case .text:
            canGenerate = (textView.text?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0) > 10
        case .document:
            canGenerate = selectedImageData != nil
        }

        actionButton.isEnabled = canGenerate && generationTask == nil
    }

    private func animateEntranceIfNeeded() {
        guard cardView.transform == .identity else { return }
        cardView.alpha = 0
        cardView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)

        UIView.animate(withDuration: 0.24) {
            self.cardView.alpha = 1
            self.cardView.transform = .identity
        }
    }

    private func setProcessing(_ isProcessing: Bool) {
        closeButton.isEnabled = !isProcessing
        textModeButton.isEnabled = !isProcessing
        documentModeButton.isEnabled = !isProcessing
        documentButton.isEnabled = !isProcessing
        documentRemoveButton.isEnabled = !isProcessing
        textView.isEditable = !isProcessing
        actionButton.isEnabled = !isProcessing

        var configuration = actionButton.configuration ?? UIButton.Configuration.filled()
        configuration.title = isProcessing ? "Gerando..." : "Gerar contrato"
        configuration.image = isProcessing ? nil : UIImage(systemName: "sparkles")
        actionButton.configuration = configuration

        if isProcessing {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
            refreshGenerateButtonState()
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func modeButtonTapped(_ sender: UIButton) {
        selectedMode = sender === textModeButton || sender.tag == 0 ? .text : .document
        refreshModeSelection()
    }

    @objc private func documentButtonTapped() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func removeDocumentTapped() {
        selectedImageData = nil
        selectedImageName = nil
        documentPreviewImageView.image = nil
        refreshDocumentPreview()
    }

    @objc private func generateTapped() {
        view.endEditing(true)
        generationTask?.cancel()
        generationTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.setProcessing(true)
            }

            do {
                let draft: AIContractDraft
                switch self.selectedMode {
                case .text:
                    let text = self.textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard text.count > 10 else {
                        throw AIExtractionServiceError.emptyExtraction
                    }
                    draft = try await self.aiService.extractContractDraft(
                        fromText: text,
                        context: "Extraia os dados estruturados de contrato a partir do texto livre digitado no app iOS."
                    )
                case .document:
                    guard let imageData = self.selectedImageData else {
                        throw AIExtractionServiceError.invalidImage
                    }
                    draft = try await self.aiService.extractContractDraft(from: imageData)
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.generationTask = nil
                    self.setProcessing(false)
                    self.dismiss(animated: true) {
                        self.onDraftGenerated?(draft)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.generationTask = nil
                    self.setProcessing(false)
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        refreshTextPlaceholder()
        refreshGenerateButtonState()
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }

        let provider = result.itemProvider
        guard provider.canLoadObject(ofClass: UIImage.self) else {
            showSimpleToast("Selecione uma imagem válida para continuar.", style: .error)
            return
        }

        provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
                return
            }

            guard
                let image = object as? UIImage,
                let imageData = image.jpegData(compressionQuality: 0.88),
                !imageData.isEmpty
            else {
                DispatchQueue.main.async {
                    self.showSimpleToast("Não consegui ler a imagem selecionada.", style: .error)
                }
                return
            }

            DispatchQueue.main.async {
                self.selectedImageData = imageData
                self.selectedImageName = result.itemProvider.suggestedName ?? "documento.jpg"
                self.documentPreviewImageView.image = image
                self.refreshDocumentPreview()
            }
        }
    }
}
