import UIKit
import UniformTypeIdentifiers

/// Aqui eu concentro a nova tela full-screen de contrato, alinhada ao layout web atual.
/// O formulário continua salvando localmente primeiro e sincronizando com o backend quando possível.
final class ContractsViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate {
    private enum BusinessType: CaseIterable {
        case general
        case service
        case sale
        case loan
        case rent
        case paymentAgreement

        var title: String {
            switch self {
            case .general: return "Outro / Acordo Geral"
            case .service: return "Prestação de Serviços"
            case .sale: return "Compra e Venda"
            case .loan: return "Empréstimo"
            case .rent: return "Locação"
            case .paymentAgreement: return "Acordo de Pagamento"
            }
        }

        var backendValue: String {
            switch self {
            case .general: return "OUTRO_ACORDO_GERAL"
            case .service: return "PRESTACAO_SERVICOS"
            case .sale: return "COMPRA_VENDA"
            case .loan: return "EMPRESTIMO"
            case .rent: return "LOCACAO"
            case .paymentAgreement: return "ACORDO_PAGAMENTO"
            }
        }
    }

    private enum FrequencyOption: CaseIterable {
        case single
        case installment

        var title: String {
            switch self {
            case .single: return "Único / À Vista"
            case .installment: return "Parcelado"
            }
        }

        var backendValue: String {
            switch self {
            case .single: return "UNICO_A_VISTA"
            case .installment: return "PARCELADO"
            }
        }
    }

    private enum ContractCreationMethod {
        case file
        case ai
    }

    private enum CreditorPersonType: CaseIterable {
        case individual
        case company

        var title: String {
            switch self {
            case .individual: return "Pessoa Física"
            case .company: return "Pessoa Jurídica"
            }
        }

        var backendValue: String {
            switch self {
            case .individual: return "PESSOA_FISICA"
            case .company: return "PESSOA_JURIDICA"
            }
        }
    }

    private enum PixKeyType: CaseIterable {
        case cpfCnpj
        case email
        case phone
        case random

        var title: String {
            switch self {
            case .cpfCnpj: return "CPF/CNPJ"
            case .email: return "E-mail"
            case .phone: return "Telefone"
            case .random: return "Chave Aleatória"
            }
        }

        var backendValue: String {
            switch self {
            case .cpfCnpj: return "CPF_CNPJ"
            case .email: return "EMAIL"
            case .phone: return "TELEFONE"
            case .random: return "CHAVE_ALEATORIA"
            }
        }
    }

    private enum AddressParticipant {
        case creditor
        case debtor
    }

    private enum ExtractionStatusState {
        case hidden
        case loading(fileName: String?)
    }

    private enum PaymentMethod: CaseIterable, Hashable {
        case pix
        case boleto
        case card

        var title: String {
            switch self {
            case .pix: return "PIX"
            case .boleto: return "Boleto"
            case .card: return "Cartão"
            }
        }

        var iconName: String {
            switch self {
            case .pix: return "qrcode"
            case .boleto: return "doc.text"
            case .card: return "creditcard"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .pix: return "contracts.payment.pix"
            case .boleto: return "contracts.payment.boleto"
            case .card: return "contracts.payment.card"
            }
        }

        var aiCode: AIContractPaymentMethodCode {
            switch self {
            case .pix: return .pix
            case .boleto: return .boleto
            case .card: return .card
            }
        }
    }

    private struct PartyFields {
        let nameField: UITextField
        let documentField: UITextField
        let phoneField: UITextField
        let emailField: UITextField
        let addressField: UITextField

        var orderedFields: [UITextField] {
            [nameField, documentField, phoneField, emailField, addressField]
        }
    }

    private enum Layout {
        static let horizontalInset: CGFloat = 16
        static let stackSpacing: CGFloat = 20
        static let sectionSpacing: CGFloat = 14
        static let fieldHeight: CGFloat = 52
        static let actionHeight: CGFloat = 54
        static let methodButtonHeight: CGFloat = 142
        static let compactActionWidth: CGFloat = 56
    }

    /// Aqui eu devolvo para o fluxo de registro tudo o que a UI precisa decidir após a sincronização.
    private struct RemoteContractSyncOutcome {
        let message: String
        let style: FeedbackToastStyle
        let remoteContractID: String?
    }

    private let session: AuthSession
    private let dataStore: LocalAppDataStore
    private let aiService: AIExtractionService
    private let actionsService: PortalActionsService

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let contentStack = UIStackView()

    private let registerButton = ContractPrimaryActionButton(type: .custom)
    private let methodShellView = UIView()
    private let fileMethodButton = ContractMethodChoiceButton(kind: .file)
    private let aiMethodButton = ContractMethodChoiceButton(kind: .ai)
    private let extractionStatusCard = UIView()
    private let extractionStatusSpinner = UIActivityIndicatorView(style: .medium)
    private let extractionStatusIconContainer = UIView()
    private let extractionStatusIconView = UIImageView()
    private let extractionStatusBadgeLabel = UILabel()
    private let extractionStatusTitleLabel = UILabel()
    private let extractionStatusMessageLabel = UILabel()
    private let extractionStatusFileCard = UIView()
    private let extractionStatusFileIconView = UIImageView()
    private let extractionStatusFileLabel = UILabel()

    private let businessTypeButton = UIButton(type: .system)
    private let subjectField = UITextField()
    private let descriptionTextView = UITextView()
    private let descriptionPlaceholderLabel = UILabel()
    private let frequencyButton = UIButton(type: .system)
    private let singleInstallmentSwitch = UISwitch()
    private let totalValueField = UITextField()
    private let dueDateField = UITextField()
    private let dueDatePicker = UIDatePicker()
    private let contractTotalValueLabel = UILabel()
    private let installmentsField = UITextField()
    private let installmentsContainer = UIStackView()
    private let singleInstallmentContainer = UIStackView()
    private let creditorPersonTypeButton = UIButton(type: .system)
    private let creditorPixKeyField = UITextField()
    private let creditorPixKeyTypeButton = UIButton(type: .system)
    private let creditorCEPField = UITextField()
    private let creditorNumberField = UITextField()
    private let creditorComplementField = UITextField()
    private let creditorCEPButton = UIButton(type: .system)
    private let creditorAddressFeedbackLabel = UILabel()
    private let debtorCEPField = UITextField()
    private let debtorNumberField = UITextField()
    private let debtorComplementField = UITextField()
    private let debtorCEPButton = UIButton(type: .system)
    private let debtorAddressFeedbackLabel = UILabel()

    private lazy var creditorFields = makePartyFields(prefix: "contracts.creditor")
    private lazy var debtorFields = makePartyFields(prefix: "contracts.debtor")
    private lazy var orderedFields: [UITextField] = [
        subjectField,
        totalValueField,
        installmentsField,
        dueDateField,
        creditorFields.nameField,
        creditorFields.documentField,
        creditorFields.phoneField,
        creditorPixKeyField,
        creditorFields.emailField,
        creditorCEPField,
        creditorNumberField,
        creditorComplementField,
        debtorFields.nameField,
        debtorFields.documentField,
        debtorFields.phoneField,
        debtorFields.emailField,
        debtorCEPField,
        debtorNumberField,
        debtorComplementField
    ]

    private var paymentMethodButtons: [PaymentMethod: UIButton] = [:]
    private var selectedPaymentMethods: Set<PaymentMethod> = [.pix]
    private var selectedBusinessType: BusinessType = .general
    private var selectedFrequency: FrequencyOption = .single
    private var selectedCreationMethod: ContractCreationMethod = .ai
    private var selectedCreditorPersonType: CreditorPersonType = .individual
    private var selectedPixKeyType: PixKeyType = .cpfCnpj
    private var selectedDueDate: Date?
    private var isApplyingFieldMask = false
    private var explicitInstallmentCount: Int?
    private var debugFileReviewPreviewURL: URL?
    private var didApplyDebugFileReviewPreview = false
    private var registerTask: Task<Void, Never>?
    private var creditorAddressLookupTask: Task<Void, Never>?
    private var debtorAddressLookupTask: Task<Void, Never>?
    private var uploadedContractFilename: String?
    private var creditorAddressPreview: PortalAddressPreview?
    private var debtorAddressPreview: PortalAddressPreview?

    init(
        session: AuthSession,
        dataStore: LocalAppDataStore,
        aiService: AIExtractionService = AIExtractionService(),
        actionsService: PortalActionsService = PortalActionsService()
    ) {
        self.session = session
        self.dataStore = dataStore
        self.aiService = aiService
        self.actionsService = actionsService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        registerTask?.cancel()
        creditorAddressLookupTask?.cancel()
        debtorAddressLookupTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupLayout()
        configureSelectors()
        configureDatePicker()
        configureActions()
        refreshBusinessTypeSelection()
        refreshCreditorPersonTypeSelection()
        refreshCreditorPixKeyTypeSelection()
        refreshFrequencySelection()
        refreshMethodSelection()
        refreshPaymentMethods()
        refreshPixKeyPlaceholder()
        refreshDescriptionPlaceholder()
        refreshTotalSummary()
        refreshPrimaryActionPresentation()
        applyTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyDebugFileReviewPreviewIfNeeded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
        refreshPaymentMethods()
    }

    func configureDebugFileReviewPreview(fileURL: URL) {
        debugFileReviewPreviewURL = fileURL
    }

    private func setupView() {
        definesPresentationContext = true
        providesPresentationContextTransitionStyle = true
        view.backgroundColor = UIColor(hex: "#F3F7FB")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive

        contentView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = Layout.stackSpacing

        registerButton.translatesAutoresizingMaskIntoConstraints = false
        registerButton.accessibilityIdentifier = "contracts.submitButton"
        registerButton.accessibilityHint = "Valida os dados e registra o contrato."
        registerButton.setContent(title: "Registrar Contrato", iconSystemName: "doc.badge.plus")

        methodShellView.translatesAutoresizingMaskIntoConstraints = false
        methodShellView.backgroundColor = UIColor(hex: "#FFFFFF")
        methodShellView.layer.cornerRadius = 18
        methodShellView.layer.cornerCurve = .continuous
        methodShellView.layer.borderWidth = 1
        methodShellView.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor

        configureExtractionStatusCard()

        configureTextField(
            subjectField,
            placeholder: "Ex: Venda Carro",
            keyboardType: .default,
            returnKeyType: .next,
            accessibilityIdentifier: "contracts.subjectField"
        )
        configureTextField(
            totalValueField,
            placeholder: "R$ 0,00",
            keyboardType: .numberPad,
            returnKeyType: .next,
            accessibilityIdentifier: "contracts.amountField"
        )
        configureTextField(
            dueDateField,
            placeholder: "dd/mm/aaaa",
            keyboardType: .default,
            returnKeyType: .done,
            accessibilityIdentifier: "contracts.dueDateField"
        )
        dueDateField.tintColor = .clear

        configureTextField(
            installmentsField,
            placeholder: "2",
            keyboardType: .numberPad,
            returnKeyType: .next,
            accessibilityIdentifier: "contracts.installmentsField"
        )
        installmentsField.addTarget(self, action: #selector(installmentsChanged), for: .editingChanged)

        configureTextField(
            creditorPixKeyField,
            placeholder: "Chave PIX *",
            keyboardType: .default,
            returnKeyType: .next,
            accessibilityIdentifier: "contracts.creditor.pixKeyField"
        )
        creditorPixKeyField.addTarget(self, action: #selector(creditorPixKeyChanged), for: .editingChanged)

        configureTextField(
            creditorCEPField,
            placeholder: "CEP",
            keyboardType: .numberPad,
            returnKeyType: .next,
            accessibilityIdentifier: "contracts.creditor.cepField"
        )
        creditorCEPField.addTarget(self, action: #selector(creditorCEPChanged), for: .editingChanged)

        configureTextField(
            creditorNumberField,
            placeholder: "Número",
            keyboardType: .default,
            returnKeyType: .next,
            accessibilityIdentifier: "contracts.creditor.numberField"
        )

        configureTextField(
            creditorComplementField,
            placeholder: "Complemento (opcional)",
            keyboardType: .default,
            returnKeyType: .next,
            accessibilityIdentifier: "contracts.creditor.complementField"
        )

        configureTextField(
            debtorCEPField,
            placeholder: "CEP *",
            keyboardType: .numberPad,
            returnKeyType: .next,
            accessibilityIdentifier: "contracts.debtor.cepField"
        )
        debtorCEPField.addTarget(self, action: #selector(debtorCEPChanged), for: .editingChanged)

        configureTextField(
            debtorNumberField,
            placeholder: "Número *",
            keyboardType: .default,
            returnKeyType: .next,
            accessibilityIdentifier: "contracts.debtor.numberField"
        )

        configureTextField(
            debtorComplementField,
            placeholder: "Complemento (opcional)",
            keyboardType: .default,
            returnKeyType: .done,
            accessibilityIdentifier: "contracts.debtor.complementField"
        )

        creditorFields.addressField.placeholder = "Endereço localizado pelo CEP"
        creditorFields.addressField.accessibilityIdentifier = "contracts.creditor.addressPreviewField"
        creditorFields.addressField.isUserInteractionEnabled = false
        creditorFields.addressField.backgroundColor = UIColor(hex: "#F3F7FB")
        creditorFields.addressField.textColor = UIColor(hex: "#6A7A91")
        creditorFields.addressField.isHidden = true

        configureAddressFeedbackLabel(
            creditorAddressFeedbackLabel,
            message: "Use o CEP para preencher logradouro, bairro, cidade e estado automaticamente."
        )

        debtorFields.addressField.placeholder = "Endereço localizado pelo CEP"
        debtorFields.addressField.accessibilityIdentifier = "contracts.debtor.addressPreviewField"
        debtorFields.addressField.isUserInteractionEnabled = false
        debtorFields.addressField.backgroundColor = UIColor(hex: "#F3F7FB")
        debtorFields.addressField.textColor = UIColor(hex: "#6A7A91")
        debtorFields.addressField.isHidden = true

        configureAddressFeedbackLabel(
            debtorAddressFeedbackLabel,
            message: "Use o CEP para preencher logradouro, bairro, cidade e estado automaticamente."
        )

        configureCEPButton(
            creditorCEPButton,
            accessibilityIdentifier: "contracts.creditor.cepLookupButton",
            accessibilityLabel: "Buscar CEP do credor",
            action: #selector(lookupCreditorCEP)
        )
        configureCEPButton(
            debtorCEPButton,
            accessibilityIdentifier: "contracts.debtor.cepLookupButton",
            accessibilityLabel: "Buscar CEP do devedor",
            action: #selector(lookupDebtorCEP)
        )
        configureDescriptionTextView()

        view.addSubview(scrollView)
        view.addSubview(registerButton)
        scrollView.addSubview(contentView)
        contentView.addSubview(contentStack)

        buildContent()
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            registerButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.horizontalInset),
            registerButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.horizontalInset),
            registerButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            registerButton.heightAnchor.constraint(equalToConstant: Layout.actionHeight),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: registerButton.topAnchor, constant: -12),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Layout.horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Layout.horizontalInset),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    private func buildContent() {
        contentStack.addArrangedSubview(makeMethodChooserCard())
        contentStack.addArrangedSubview(extractionStatusCard)
        contentStack.setCustomSpacing(22, after: methodShellView)
        contentStack.addArrangedSubview(makeSectionHeader(icon: "doc.text", title: "Dados do Acordo"))
        contentStack.addArrangedSubview(makeTwoColumnRow(
            left: makeInputGroup(title: "TIPO DO NEGÓCIO", input: businessTypeButton),
            right: makeInputGroup(title: "ASSUNTO", input: subjectField)
        ))
        contentStack.addArrangedSubview(makeInputGroup(title: "DESCRIÇÃO DETALHADA DO ACORDO", input: makeDescriptionContainer()))

        contentStack.addArrangedSubview(makeSectionHeader(icon: "dollarsign", title: "Valores e Pagamento"))
        contentStack.addArrangedSubview(makeFrequencyRow())
        contentStack.addArrangedSubview(makeTwoColumnRow(
            left: makeInputGroup(title: "VALOR TOTAL", input: totalValueField),
            right: makeInputGroup(title: "1º VENCIMENTO", input: dueDateField)
        ))
        contentStack.addArrangedSubview(makeContractTotalCard())

        contentStack.addArrangedSubview(makeSectionHeader(icon: "person.2", title: "Dados das Partes"))
        contentStack.addArrangedSubview(makeCreditorPartyCard())
        contentStack.addArrangedSubview(makeDebtorPartyCard())

        contentStack.addArrangedSubview(makeSectionHeader(icon: "creditcard", title: "Meios de Pagamento Aceitos"))
        contentStack.addArrangedSubview(makePaymentMethodsRow())
    }

    private func makeMethodChooserCard() -> UIView {
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "NOVO CONTRATO"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.textAlignment = .center
        titleLabel.applyScaledFont(size: 20, weight: .black, textStyle: .title3)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "ESCOLHA QUAL MÉTODO DESEJA CRIAR SEU CONTRATO"
        subtitleLabel.textColor = UIColor(hex: "#607993")
        subtitleLabel.textAlignment = .center
        subtitleLabel.applyScaledFont(size: 11, weight: .bold, textStyle: .caption1)

        let methodsStack = UIStackView(arrangedSubviews: [fileMethodButton, aiMethodButton])
        methodsStack.translatesAutoresizingMaskIntoConstraints = false
        methodsStack.axis = .horizontal
        methodsStack.distribution = .fillEqually
        methodsStack.spacing = 14

        methodShellView.addSubview(titleLabel)
        methodShellView.addSubview(subtitleLabel)
        methodShellView.addSubview(methodsStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: methodShellView.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: methodShellView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: methodShellView.trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: methodShellView.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: methodShellView.trailingAnchor, constant: -16),

            methodsStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            methodsStack.leadingAnchor.constraint(equalTo: methodShellView.leadingAnchor, constant: 16),
            methodsStack.trailingAnchor.constraint(equalTo: methodShellView.trailingAnchor, constant: -16),
            methodsStack.bottomAnchor.constraint(equalTo: methodShellView.bottomAnchor, constant: -18),
            fileMethodButton.heightAnchor.constraint(equalToConstant: Layout.methodButtonHeight),
            aiMethodButton.heightAnchor.constraint(equalTo: fileMethodButton.heightAnchor)
        ])

        return methodShellView
    }

    private func configureExtractionStatusCard() {
        extractionStatusCard.translatesAutoresizingMaskIntoConstraints = false
        extractionStatusCard.backgroundColor = UIColor(hex: "#FBFCFE")
        extractionStatusCard.layer.cornerRadius = 18
        extractionStatusCard.layer.cornerCurve = .continuous
        extractionStatusCard.layer.borderWidth = 1
        extractionStatusCard.layer.borderColor = UIColor(hex: "#D8E1ED").cgColor
        extractionStatusCard.isHidden = true
        extractionStatusCard.accessibilityIdentifier = "contracts.fileReview.card"

        extractionStatusSpinner.translatesAutoresizingMaskIntoConstraints = false
        extractionStatusSpinner.hidesWhenStopped = true
        extractionStatusSpinner.color = UIColor(hex: "#1579A8")

        extractionStatusIconContainer.translatesAutoresizingMaskIntoConstraints = false
        extractionStatusIconContainer.backgroundColor = UIColor(hex: "#D8EDF8")
        extractionStatusIconContainer.layer.cornerRadius = 22
        extractionStatusIconContainer.layer.cornerCurve = .continuous

        extractionStatusIconView.translatesAutoresizingMaskIntoConstraints = false
        extractionStatusIconView.tintColor = UIColor(hex: "#1579A8")
        extractionStatusIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)

        extractionStatusBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        extractionStatusBadgeLabel.textColor = UIColor(hex: "#6E7F95")
        extractionStatusBadgeLabel.applyScaledFont(size: 11, weight: .bold, textStyle: .caption1)
        extractionStatusBadgeLabel.accessibilityIdentifier = "contracts.fileReview.badgeLabel"

        extractionStatusTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        extractionStatusTitleLabel.text = "Analisando documento com IA..."
        extractionStatusTitleLabel.textColor = UIColor(hex: "#283344")
        extractionStatusTitleLabel.numberOfLines = 0
        extractionStatusTitleLabel.textAlignment = .left
        extractionStatusTitleLabel.applyScaledFont(size: 15, weight: .bold, textStyle: .headline)
        extractionStatusTitleLabel.accessibilityIdentifier = "contracts.fileReview.titleLabel"

        extractionStatusMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        extractionStatusMessageLabel.text = "Isso pode levar alguns segundos."
        extractionStatusMessageLabel.textColor = UIColor(hex: "#6E7F95")
        extractionStatusMessageLabel.numberOfLines = 0
        extractionStatusMessageLabel.textAlignment = .left
        extractionStatusMessageLabel.applyScaledFont(size: 13, weight: .medium, textStyle: .subheadline)
        extractionStatusMessageLabel.accessibilityIdentifier = "contracts.fileReview.messageLabel"

        extractionStatusFileCard.translatesAutoresizingMaskIntoConstraints = false
        extractionStatusFileCard.backgroundColor = UIColor(hex: "#EAF4FB")
        extractionStatusFileCard.layer.cornerRadius = 14
        extractionStatusFileCard.layer.cornerCurve = .continuous

        extractionStatusFileIconView.translatesAutoresizingMaskIntoConstraints = false
        extractionStatusFileIconView.tintColor = UIColor(hex: "#1579A8")
        extractionStatusFileIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)

        extractionStatusFileLabel.translatesAutoresizingMaskIntoConstraints = false
        extractionStatusFileLabel.textColor = UIColor(hex: "#283344")
        extractionStatusFileLabel.numberOfLines = 1
        extractionStatusFileLabel.lineBreakMode = .byTruncatingMiddle
        extractionStatusFileLabel.applyScaledFont(size: 13, weight: .semibold, textStyle: .subheadline)
        extractionStatusFileLabel.accessibilityIdentifier = "contracts.fileReview.fileLabel"

        extractionStatusIconContainer.addSubview(extractionStatusIconView)
        extractionStatusFileCard.addSubview(extractionStatusFileIconView)
        extractionStatusFileCard.addSubview(extractionStatusFileLabel)

        let textStack = UIStackView(arrangedSubviews: [
            extractionStatusBadgeLabel,
            extractionStatusTitleLabel,
            extractionStatusMessageLabel
        ])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4

        let headerRow = UIStackView(arrangedSubviews: [extractionStatusIconContainer, textStack])
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 14

        extractionStatusCard.addSubview(headerRow)
        extractionStatusCard.addSubview(extractionStatusSpinner)
        extractionStatusCard.addSubview(extractionStatusFileCard)

        NSLayoutConstraint.activate([
            extractionStatusIconContainer.widthAnchor.constraint(equalToConstant: 44),
            extractionStatusIconContainer.heightAnchor.constraint(equalToConstant: 44),
            extractionStatusIconView.centerXAnchor.constraint(equalTo: extractionStatusIconContainer.centerXAnchor),
            extractionStatusIconView.centerYAnchor.constraint(equalTo: extractionStatusIconContainer.centerYAnchor),

            headerRow.topAnchor.constraint(equalTo: extractionStatusCard.topAnchor, constant: 18),
            headerRow.leadingAnchor.constraint(equalTo: extractionStatusCard.leadingAnchor, constant: 18),
            headerRow.trailingAnchor.constraint(equalTo: extractionStatusCard.trailingAnchor, constant: -18),

            extractionStatusSpinner.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 14),
            extractionStatusSpinner.centerXAnchor.constraint(equalTo: extractionStatusCard.centerXAnchor),

            extractionStatusFileCard.topAnchor.constraint(equalTo: extractionStatusSpinner.bottomAnchor, constant: 16),
            extractionStatusFileCard.leadingAnchor.constraint(equalTo: extractionStatusCard.leadingAnchor, constant: 18),
            extractionStatusFileCard.trailingAnchor.constraint(equalTo: extractionStatusCard.trailingAnchor, constant: -18),
            extractionStatusFileCard.bottomAnchor.constraint(equalTo: extractionStatusCard.bottomAnchor, constant: -18),

            extractionStatusFileIconView.leadingAnchor.constraint(equalTo: extractionStatusFileCard.leadingAnchor, constant: 14),
            extractionStatusFileIconView.centerYAnchor.constraint(equalTo: extractionStatusFileCard.centerYAnchor),

            extractionStatusFileLabel.topAnchor.constraint(equalTo: extractionStatusFileCard.topAnchor, constant: 14),
            extractionStatusFileLabel.leadingAnchor.constraint(equalTo: extractionStatusFileIconView.trailingAnchor, constant: 10),
            extractionStatusFileLabel.trailingAnchor.constraint(equalTo: extractionStatusFileCard.trailingAnchor, constant: -14),
            extractionStatusFileLabel.bottomAnchor.constraint(equalTo: extractionStatusFileCard.bottomAnchor, constant: -14)
        ])

        applyExtractionStatus(.hidden)
    }

    private func makeSectionHeader(icon: String, title: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = UIColor(hex: "#252E3A")
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.textColor = UIColor(hex: "#252E3A")
        label.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)

        container.addSubview(iconView)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            iconView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        return container
    }

    private func makeInputGroup(title: String, input: UIView) -> UIView {
        let container = UIStackView(arrangedSubviews: [makeGroupLabel(title), input])
        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .vertical
        container.spacing = 8
        return container
    }

    private func makeGroupLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.textColor = UIColor(hex: "#6A7A91")
        label.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)
        return label
    }

    private func makeTwoColumnRow(left: UIView, right: UIView) -> UIView {
        let stack = UIStackView(arrangedSubviews: [left, right])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        return stack
    }

    private func makeDescriptionContainer() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true

        container.addSubview(descriptionTextView)
        container.addSubview(descriptionPlaceholderLabel)

        NSLayoutConstraint.activate([
            descriptionTextView.topAnchor.constraint(equalTo: container.topAnchor),
            descriptionTextView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            descriptionTextView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            descriptionTextView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            descriptionPlaceholderLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            descriptionPlaceholderLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            descriptionPlaceholderLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14)
        ])

        return container
    }

    private func makeFrequencyRow() -> UIView {
        let switchLabel = UILabel()
        switchLabel.text = "PARCELA ÚNICA"
        switchLabel.textColor = UIColor(hex: "#6A7A91")
        switchLabel.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)

        singleInstallmentContainer.arrangedSubviews.forEach {
            singleInstallmentContainer.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        singleInstallmentContainer.axis = .horizontal
        singleInstallmentContainer.alignment = .center
        singleInstallmentContainer.spacing = 10
        singleInstallmentContainer.addArrangedSubview(switchLabel)
        singleInstallmentContainer.addArrangedSubview(singleInstallmentSwitch)

        installmentsContainer.arrangedSubviews.forEach {
            installmentsContainer.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        installmentsContainer.axis = .vertical
        installmentsContainer.spacing = 8
        installmentsContainer.addArrangedSubview(makeGroupLabel("PARCELAS"))
        installmentsContainer.addArrangedSubview(installmentsField)

        let row = UIStackView(arrangedSubviews: [
            makeInputGroup(title: "FREQUÊNCIA", input: frequencyButton),
            installmentsContainer,
            singleInstallmentContainer
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .bottom
        row.spacing = 12

        frequencyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        installmentsContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
        installmentsContainer.setContentHuggingPriority(.required, for: .horizontal)
        singleInstallmentContainer.setContentHuggingPriority(.required, for: .horizontal)
        singleInstallmentSwitch.onTintColor = UIColor(fixedHex: "#1E89B8")
        singleInstallmentSwitch.setOn(true, animated: false)

        return row
    }

    private func makeContractTotalCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(hex: "#E8F2FA")
        card.layer.cornerRadius = 10
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#C8D6E8").cgColor

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Total do Contrato:"
        titleLabel.textColor = UIColor(hex: "#1579A8")
        titleLabel.applyScaledFont(size: 16, weight: .bold, textStyle: .headline)

        contractTotalValueLabel.translatesAutoresizingMaskIntoConstraints = false
        contractTotalValueLabel.textColor = UIColor(hex: "#1579A8")
        contractTotalValueLabel.applyScaledFont(size: 18, weight: .black, textStyle: .headline)
        contractTotalValueLabel.textAlignment = .right

        card.addSubview(titleLabel)
        card.addSubview(contractTotalValueLabel)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),

            contractTotalValueLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            contractTotalValueLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            contractTotalValueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12)
        ])

        return card
    }

    private func makeCreditorPartyCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(hex: "#FBFCFE")
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#D8E1ED").cgColor

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "CREDOR (VOCÊ)"
        titleLabel.textColor = UIColor(hex: "#6A7A91")
        titleLabel.applyScaledFont(size: 13, weight: .bold, textStyle: .caption1)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Eu uso seus dados como base e complemento o endereço pelo CEP."
        subtitleLabel.textColor = UIColor(hex: "#7D8EA5")
        subtitleLabel.numberOfLines = 0
        subtitleLabel.applyScaledFont(size: 12, weight: .medium, textStyle: .caption1)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 4

        let documentPhoneRow = UIStackView(arrangedSubviews: [creditorFields.documentField, creditorFields.phoneField])
        documentPhoneRow.axis = .horizontal
        documentPhoneRow.distribution = .fillEqually
        documentPhoneRow.spacing = 10

        let personPixRow = UIStackView(arrangedSubviews: [creditorPersonTypeButton, creditorPixKeyField])
        personPixRow.axis = .horizontal
        personPixRow.distribution = .fillEqually
        personPixRow.spacing = 10

        let cepRow = UIStackView(arrangedSubviews: [creditorCEPField, creditorCEPButton])
        cepRow.axis = .horizontal
        cepRow.spacing = 10
        creditorCEPButton.widthAnchor.constraint(equalToConstant: Layout.compactActionWidth).isActive = true

        let numberComplementRow = UIStackView(arrangedSubviews: [creditorNumberField, creditorComplementField])
        numberComplementRow.axis = .horizontal
        numberComplementRow.distribution = .fillEqually
        numberComplementRow.spacing = 10

        let addressBlock = makeAddressDetailCard(
            participant: .creditor,
            cepRow: cepRow,
            feedbackLabel: creditorAddressFeedbackLabel,
            numberComplementRow: numberComplementRow,
            addressPreviewField: creditorFields.addressField
        )

        let stack = UIStackView(arrangedSubviews: [
            headerStack,
            creditorFields.nameField,
            documentPhoneRow,
            personPixRow,
            creditorPixKeyTypeButton,
            creditorFields.emailField,
            addressBlock
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 13

        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        return card
    }

    private func makeDebtorPartyCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(hex: "#FBFCFE")
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#D8E1ED").cgColor

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "DEVEDOR (CONTRATANTE)"
        titleLabel.textColor = UIColor(hex: "#6A7A91")
        titleLabel.applyScaledFont(size: 13, weight: .bold, textStyle: .caption1)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Eu complemento o endereço do contratante pelo CEP e deixo esse bloco pronto para o backend."
        subtitleLabel.textColor = UIColor(hex: "#7D8EA5")
        subtitleLabel.numberOfLines = 0
        subtitleLabel.applyScaledFont(size: 12, weight: .medium, textStyle: .caption1)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 4

        let documentPhoneRow = UIStackView(arrangedSubviews: [debtorFields.documentField, debtorFields.phoneField])
        documentPhoneRow.axis = .horizontal
        documentPhoneRow.distribution = .fillEqually
        documentPhoneRow.spacing = 10

        let cepRow = UIStackView(arrangedSubviews: [debtorCEPField, debtorCEPButton])
        cepRow.axis = .horizontal
        cepRow.spacing = 10
        debtorCEPButton.widthAnchor.constraint(equalToConstant: Layout.compactActionWidth).isActive = true

        let numberComplementRow = UIStackView(arrangedSubviews: [debtorNumberField, debtorComplementField])
        numberComplementRow.axis = .horizontal
        numberComplementRow.distribution = .fillEqually
        numberComplementRow.spacing = 10

        let addressBlock = makeAddressDetailCard(
            participant: .debtor,
            cepRow: cepRow,
            feedbackLabel: debtorAddressFeedbackLabel,
            numberComplementRow: numberComplementRow,
            addressPreviewField: debtorFields.addressField
        )

        let stack = UIStackView(arrangedSubviews: [
            headerStack,
            debtorFields.nameField,
            documentPhoneRow,
            debtorFields.emailField,
            addressBlock
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 13

        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        return card
    }

    private func makeAddressDetailCard(
        participant: AddressParticipant,
        cepRow: UIStackView,
        feedbackLabel: UILabel,
        numberComplementRow: UIStackView,
        addressPreviewField: UITextField
    ) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(hex: "#F6FAFD")
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#E1EAF4").cgColor

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "ENDEREÇO"
        titleLabel.textColor = UIColor(hex: "#6A7A91")
        titleLabel.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textColor = UIColor(hex: "#7D8EA5")
        subtitleLabel.applyScaledFont(size: 12, weight: .medium, textStyle: .caption1)
        subtitleLabel.text = participant == .creditor
            ? "Eu consulto o CEP do credor e deixo o resumo do endereço pronto para o envio."
            : "Eu consulto o CEP do devedor e monto o resumo do endereço como o backend espera."

        styleResolvedAddressPreviewField(addressPreviewField)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 4

        let stack = UIStackView(arrangedSubviews: [
            headerStack,
            cepRow,
            feedbackLabel,
            numberComplementRow,
            addressPreviewField
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12

        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private func makePaymentMethodsRow() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(hex: "#FBFCFE")
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(hex: "#D8E1ED").cgColor

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "ESCOLHA COMO O CONTRATO PODE SER PAGO"
        titleLabel.textColor = UIColor(hex: "#6A7A91")
        titleLabel.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = "Eu envio esses meios de pagamento no mesmo formato usado pelo web e pelo backend."
        subtitleLabel.textColor = UIColor(hex: "#7D8EA5")
        subtitleLabel.applyScaledFont(size: 12, weight: .medium, textStyle: .caption1)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12

        for method in PaymentMethod.allCases {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tag = paymentMethodButtons.count
            button.accessibilityIdentifier = method.accessibilityIdentifier
            button.layer.cornerRadius = 14
            button.layer.cornerCurve = .continuous
            button.layer.borderWidth = 1
            button.titleLabel?.numberOfLines = 1
            button.addAction(UIAction { [weak self] _ in
                self?.togglePaymentMethod(method)
            }, for: .touchUpInside)

            let iconView = UIImageView(image: UIImage(systemName: method.iconName))
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.tintColor = UIColor(hex: "#607993")
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            iconView.tag = 1001

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = method.title
            label.textColor = UIColor(hex: "#607993")
            label.textAlignment = .center
            label.applyScaledFont(size: 15, weight: .semibold, textStyle: .headline)
            label.tag = 1002

            button.addSubview(iconView)
            button.addSubview(label)
            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 72),
                iconView.topAnchor.constraint(equalTo: button.topAnchor, constant: 16),
                iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
                label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -8),
                label.bottomAnchor.constraint(lessThanOrEqualTo: button.bottomAnchor, constant: -12)
            ])

            paymentMethodButtons[method] = button
            stack.addArrangedSubview(button)
        }

        let contentStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, stack])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 12

        card.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        return card
    }

    private func makePartyFields(prefix: String) -> PartyFields {
        let nameField = UITextField()
        configureTextField(
            nameField,
            placeholder: "Nome Completo",
            keyboardType: .default,
            returnKeyType: .next,
            accessibilityIdentifier: "\(prefix).nameField"
        )

        let documentField = UITextField()
        configureTextField(
            documentField,
            placeholder: "CPF/CNPJ",
            keyboardType: .numberPad,
            returnKeyType: .next,
            accessibilityIdentifier: "\(prefix).documentField"
        )
        documentField.addTarget(self, action: #selector(documentFieldChanged(_:)), for: .editingChanged)

        let phoneField = UITextField()
        configureTextField(
            phoneField,
            placeholder: "Telefone",
            keyboardType: .numberPad,
            returnKeyType: .next,
            accessibilityIdentifier: "\(prefix).phoneField"
        )
        phoneField.addTarget(self, action: #selector(phoneFieldChanged(_:)), for: .editingChanged)

        let emailField = UITextField()
        configureTextField(
            emailField,
            placeholder: "E-mail",
            keyboardType: .emailAddress,
            returnKeyType: .next,
            accessibilityIdentifier: "\(prefix).emailField"
        )

        let addressField = UITextField()
        configureTextField(
            addressField,
            placeholder: "Endereço Completo",
            keyboardType: .default,
            returnKeyType: .done,
            accessibilityIdentifier: "\(prefix).addressField"
        )

        return PartyFields(
            nameField: nameField,
            documentField: documentField,
            phoneField: phoneField,
            emailField: emailField,
            addressField: addressField
        )
    }

    private func configureTextField(
        _ field: UITextField,
        placeholder: String,
        keyboardType: UIKeyboardType,
        returnKeyType: UIReturnKeyType,
        accessibilityIdentifier: String
    ) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.backgroundColor = UIColor(hex: "#FFFFFF")
        field.textColor = UIColor(hex: "#252E3A")
        field.tintColor = UIColor(hex: "#1579A8")
        field.layer.cornerRadius = 10
        field.layer.cornerCurve = .continuous
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        field.setPlaceholderColor(UIColor(hex: "#95A9BD"))
        field.placeholder = placeholder
        field.keyboardType = keyboardType
        field.returnKeyType = returnKeyType
        field.autocorrectionType = .no
        field.autocapitalizationType = keyboardType == .emailAddress ? .none : .words
        field.applyScaledFont(size: 16, weight: .medium, textStyle: .body)
        field.delegate = self
        field.accessibilityIdentifier = accessibilityIdentifier
        field.heightAnchor.constraint(equalToConstant: Layout.fieldHeight).isActive = true
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always
        field.inputAccessoryView = makeKeyboardToolbar()
    }

    private func configureAddressFeedbackLabel(_ label: UILabel, message: String) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.applyScaledFont(size: 12, weight: .medium, textStyle: .caption1)
        label.textColor = UIColor(hex: "#607993")
        label.text = message
    }

    private func styleResolvedAddressPreviewField(_ field: UITextField) {
        field.backgroundColor = UIColor(hex: "#EFF5FA")
        field.layer.borderColor = UIColor(hex: "#D1DFEC").cgColor
        field.textColor = UIColor(hex: "#425870")
    }

    private func configureCEPButton(
        _ button: UIButton,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#1E89B8").cgColor
        button.backgroundColor = UIColor(hex: "#1E89B8")
        button.tintColor = .white
        button.accessibilityIdentifier = accessibilityIdentifier
        button.accessibilityLabel = accessibilityLabel
        button.heightAnchor.constraint(equalToConstant: Layout.fieldHeight).isActive = true
        let image = UIImage(systemName: "magnifyingglass")
        button.setImage(image, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func configureDescriptionTextView() {
        descriptionTextView.translatesAutoresizingMaskIntoConstraints = false
        descriptionTextView.backgroundColor = UIColor(hex: "#FFFFFF")
        descriptionTextView.textColor = UIColor(hex: "#252E3A")
        descriptionTextView.tintColor = UIColor(hex: "#1579A8")
        descriptionTextView.layer.cornerRadius = 10
        descriptionTextView.layer.cornerCurve = .continuous
        descriptionTextView.layer.borderWidth = 1
        descriptionTextView.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        descriptionTextView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        descriptionTextView.textContainer.lineFragmentPadding = 0
        descriptionTextView.applyScaledFont(size: 16, weight: .medium, textStyle: .body)
        descriptionTextView.delegate = self
        descriptionTextView.inputAccessoryView = makeKeyboardToolbar()
        descriptionTextView.accessibilityIdentifier = "contracts.descriptionField"

        descriptionPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionPlaceholderLabel.numberOfLines = 0
        descriptionPlaceholderLabel.text = "Descreva o objeto do contrato, condições especiais, garantias, etc."
        descriptionPlaceholderLabel.textColor = UIColor(hex: "#95A9BD")
        descriptionPlaceholderLabel.applyScaledFont(size: 16, weight: .medium, textStyle: .body)
    }

    private func configureSelectors() {
        configureSelectorButton(businessTypeButton, accessibilityIdentifier: "contracts.businessTypeButton")
        configureSelectorButton(frequencyButton, accessibilityIdentifier: "contracts.frequencyButton")
        configureSelectorButton(creditorPersonTypeButton, accessibilityIdentifier: "contracts.creditor.personTypeButton")
        configureSelectorButton(creditorPixKeyTypeButton, accessibilityIdentifier: "contracts.creditor.pixKeyTypeButton")

        businessTypeButton.menu = UIMenu(children: BusinessType.allCases.map { option in
            UIAction(title: option.title) { [weak self] _ in
                self?.selectedBusinessType = option
                self?.refreshBusinessTypeSelection()
            }
        })

        frequencyButton.menu = UIMenu(children: FrequencyOption.allCases.map { option in
            UIAction(title: option.title) { [weak self] _ in
                self?.selectedFrequency = option
                self?.singleInstallmentSwitch.setOn(option == .single, animated: true)
                self?.refreshFrequencySelection()
            }
        })

        creditorPersonTypeButton.menu = UIMenu(children: CreditorPersonType.allCases.map { option in
            UIAction(title: option.title) { [weak self] _ in
                self?.selectedCreditorPersonType = option
                self?.refreshCreditorPersonTypeSelection()
                self?.refreshPixKeyPlaceholder()
            }
        })

        creditorPixKeyTypeButton.menu = UIMenu(children: PixKeyType.allCases.map { option in
            UIAction(title: option.title) { [weak self] _ in
                self?.selectedPixKeyType = option
                self?.refreshCreditorPixKeyTypeSelection()
                self?.refreshPixKeyPlaceholder()
            }
        })
    }

    private func configureSelectorButton(_ button: UIButton, accessibilityIdentifier: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        button.accessibilityIdentifier = accessibilityIdentifier
        button.heightAnchor.constraint(equalToConstant: Layout.fieldHeight).isActive = true
        button.applyStableStateColors(
            normalBackground: UIColor(hex: "#FFFFFF"),
            normalForeground: UIColor(hex: "#607993")
        )
        button.titleLabel?.textAlignment = .left
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.showsMenuAsPrimaryAction = true
        button.configuration = makeSelectorConfiguration(title: nil)
    }

    private func configureDatePicker() {
        dueDatePicker.datePickerMode = .date
        dueDatePicker.preferredDatePickerStyle = .wheels
        dueDatePicker.locale = Locale(identifier: "pt_BR")
        dueDateField.inputView = dueDatePicker
        dueDateField.inputAccessoryView = makeDateToolbar()
    }

    private func configureActions() {
        fileMethodButton.addTarget(self, action: #selector(fileMethodTapped), for: .touchUpInside)
        aiMethodButton.addTarget(self, action: #selector(aiMethodTapped), for: .touchUpInside)
        registerButton.addTarget(self, action: #selector(registerTapped), for: .touchUpInside)
        totalValueField.addTarget(self, action: #selector(amountChanged), for: .editingChanged)
        singleInstallmentSwitch.addTarget(self, action: #selector(singleInstallmentChanged), for: .valueChanged)
    }

    private func makeKeyboardToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "OK", style: .done, target: self, action: #selector(doneKeyboardTapped))
        ]
        return toolbar
    }

    private func makeDateToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Selecionar", style: .done, target: self, action: #selector(confirmDueDateSelection))
        ]
        return toolbar
    }

    private func refreshBusinessTypeSelection() {
        businessTypeButton.configuration = makeSelectorConfiguration(title: selectedBusinessType.title)
    }

    private func refreshCreditorPersonTypeSelection() {
        creditorPersonTypeButton.configuration = makeSelectorConfiguration(title: selectedCreditorPersonType.title)
    }

    private func refreshCreditorPixKeyTypeSelection() {
        creditorPixKeyTypeButton.configuration = makeSelectorConfiguration(title: selectedPixKeyType.title)
    }

    private func refreshFrequencySelection() {
        frequencyButton.configuration = makeSelectorConfiguration(title: selectedFrequency.title)
        refreshInstallmentControls()
    }

    private func refreshMethodSelection() {
        fileMethodButton.setSelectedAppearance(selectedCreationMethod == .file)
        aiMethodButton.setSelectedAppearance(selectedCreationMethod == .ai)
    }

    private func refreshPaymentMethods() {
        for method in PaymentMethod.allCases {
            guard let button = paymentMethodButtons[method] else { continue }
            let isSelected = selectedPaymentMethods.contains(method)
            button.backgroundColor = isSelected ? UIColor(hex: "#E8F2FA") : UIColor(hex: "#FFFFFF")
            button.layer.borderColor = (isSelected ? UIColor(hex: "#2E87C8") : UIColor(hex: "#D7DEE8")).cgColor
            button.tintColor = isSelected ? UIColor(hex: "#1579A8") : UIColor(hex: "#607993")
            button.alpha = 1

            if let iconView = button.viewWithTag(1001) as? UIImageView {
                iconView.tintColor = isSelected ? UIColor(hex: "#1579A8") : UIColor(hex: "#607993")
            }
            if let label = button.viewWithTag(1002) as? UILabel {
                label.textColor = isSelected ? UIColor(hex: "#1579A8") : UIColor(hex: "#607993")
            }
        }
    }

    private func refreshDescriptionPlaceholder() {
        let text = descriptionTextView.text ?? ""
        descriptionPlaceholderLabel.text = selectedCreationMethod == .ai
            ? "Descreva livremente o que será contratado. A IA transforma seu texto em minuta jurídica completa."
            : "Depois do upload eu aproveito o arquivo para pré-preencher este formulário."
        descriptionPlaceholderLabel.isHidden = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func refreshPixKeyPlaceholder() {
        switch selectedPixKeyType {
        case .cpfCnpj:
            creditorPixKeyField.placeholder = "Chave PIX (CPF/CNPJ) *"
            creditorPixKeyField.keyboardType = .numberPad
        case .email:
            creditorPixKeyField.placeholder = "Chave PIX (E-mail) *"
            creditorPixKeyField.keyboardType = .emailAddress
        case .phone:
            creditorPixKeyField.placeholder = "Chave PIX (Telefone) *"
            creditorPixKeyField.keyboardType = .phonePad
        case .random:
            creditorPixKeyField.placeholder = "Chave PIX Aleatória *"
            creditorPixKeyField.keyboardType = .default
        }
        creditorPixKeyField.autocapitalizationType = selectedPixKeyType == .email ? .none : .none
    }

    private func refreshTotalSummary() {
        contractTotalValueLabel.text = currentAmount().asCurrency
    }

    private func refreshInstallmentControls() {
        let isInstallment = selectedFrequency == .installment
        installmentsContainer.isHidden = !isInstallment
        singleInstallmentContainer.isHidden = isInstallment
        singleInstallmentSwitch.setOn(!isInstallment, animated: false)

        if isInstallment {
            let currentValue = explicitInstallmentCount ?? Int(Formatters.digitsOnly(installmentsField.text ?? "")) ?? 0
            if currentValue < 2 {
                explicitInstallmentCount = 2
                installmentsField.text = "2"
            } else {
                explicitInstallmentCount = currentValue
                installmentsField.text = String(currentValue)
            }
        } else {
            installmentsField.text = explicitInstallmentCount == 1 ? "1" : nil
        }
    }

    private func applyTheme() {
        descriptionTextView.keyboardAppearance = UserDefaults.standard.bool(forKey: "billeasy.theme.dark_mode_enabled") ? .dark : .light
    }

    private func makeSelectorConfiguration(title: String?) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = UIColor(hex: "#607993")
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        configuration.titleAlignment = .leading
        return configuration
    }

    @objc private func fileMethodTapped() {
        view.endEditing(true)
        selectedCreationMethod = .file
        refreshMethodSelection()
        refreshDescriptionPlaceholder()
        refreshPrimaryActionPresentation()
        presentFileUploadDialog()
    }

    @objc private func aiMethodTapped() {
        view.endEditing(true)
        selectedCreationMethod = .ai
        uploadedContractFilename = nil
        applyExtractionStatus(.hidden)
        refreshMethodSelection()
        refreshDescriptionPlaceholder()
        refreshPrimaryActionPresentation()

        let controller = ContractAIGeneratorViewController(
            aiService: aiService,
            initialText: makeAISeedText().trimmingCharacters(in: .whitespacesAndNewlines)
        )
        controller.onDraftGenerated = { [weak self] draft in
            guard let self else { return }
            self.applyDraftFromAI(draft)
            self.showSimpleToast("Rascunho por IA aplicado. Revise os dados e toque em Registrar Contrato.", style: .success)
        }
        present(controller, animated: true)
    }

    private func presentFileUploadDialog() {
        let controller = ContractFileUploadViewController()
        controller.onDismissWithoutSelection = { [weak self] in
            guard let self else { return }
            if self.selectedCreationMethod == .file, self.uploadedContractFilename == nil {
                self.selectedCreationMethod = .ai
                self.applyExtractionStatus(.hidden)
                self.refreshMethodSelection()
                self.refreshDescriptionPlaceholder()
                self.refreshPrimaryActionPresentation()
            }
        }
        controller.onConfirmSelectedFile = { [weak self] url in
            self?.processUploadedContractFile(url)
        }
        present(controller, animated: true)
    }

    private func processUploadedContractFile(_ fileURL: URL) {
        applyExtractionStatus(.loading(fileName: fileURL.lastPathComponent))
        fileMethodButton.setLoading(true)
        fileMethodButton.isEnabled = false
        uploadedContractFilename = fileURL.lastPathComponent

        Task { [weak self] in
            guard let self else { return }

            do {
                let draft = try await self.makeDraftFromUploadedFile(at: fileURL)
                await MainActor.run {
                    self.fileMethodButton.setLoading(false)
                    self.fileMethodButton.isEnabled = true
                    self.selectedCreationMethod = .file
                    self.applyDraftFromFileUpload(draft)
                    self.applyExtractionStatus(.hidden)
                }
            } catch {
                await MainActor.run {
                    self.applyExtractionStatus(.hidden)
                    self.fileMethodButton.setLoading(false)
                    self.fileMethodButton.isEnabled = true
                    self.uploadedContractFilename = nil
                    self.selectedCreationMethod = .ai
                    self.refreshMethodSelection()
                    self.refreshDescriptionPlaceholder()
                    self.refreshPrimaryActionPresentation()
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    private func applyExtractionStatus(_ state: ExtractionStatusState) {
        switch state {
        case .hidden:
            extractionStatusCard.isHidden = true
            extractionStatusSpinner.stopAnimating()
            extractionStatusBadgeLabel.text = nil
            extractionStatusTitleLabel.text = nil
            extractionStatusMessageLabel.text = nil
            extractionStatusFileLabel.text = nil
        case let .loading(fileName):
            extractionStatusCard.isHidden = false
            extractionStatusSpinner.startAnimating()
            extractionStatusIconContainer.isHidden = false
            extractionStatusIconView.image = UIImage(systemName: "doc.viewfinder")
            extractionStatusBadgeLabel.text = "ANALISANDO ARQUIVO"
            extractionStatusTitleLabel.text = "Analisando documento com IA…"
            extractionStatusMessageLabel.text = "Isso pode levar alguns segundos"
            extractionStatusFileIconView.image = fileIcon(forFilename: fileName)
            extractionStatusFileLabel.text = fileName ?? "Documento enviado para análise"
            extractionStatusFileCard.isHidden = false
        }
    }

    private func makeDraftFromUploadedFile(at fileURL: URL) async throws -> AIContractDraft {
        let lowercasedExtension = fileURL.pathExtension.lowercased()
        let fileData = try Data(contentsOf: fileURL)
        let mimeType: String
        switch lowercasedExtension {
        case "pdf":
            mimeType = "application/pdf"
        case "png":
            mimeType = "image/png"
        case "gif":
            mimeType = "image/gif"
        case "bmp":
            mimeType = "image/bmp"
        case "tif", "tiff":
            mimeType = "image/tiff"
        case "webp":
            mimeType = "image/webp"
        default:
            mimeType = "image/jpeg"
        }

        return try await aiService.extractContractDraft(
            from: fileData,
            filename: fileURL.lastPathComponent,
            mimeType: mimeType
        )
    }

    @objc private func singleInstallmentChanged() {
        if singleInstallmentSwitch.isOn {
            selectedFrequency = .single
            if explicitInstallmentCount != 1 {
                explicitInstallmentCount = nil
            }
        } else if selectedFrequency == .single {
            selectedFrequency = .installment
            if explicitInstallmentCount == nil || explicitInstallmentCount == 1 {
                explicitInstallmentCount = 2
            }
        }
        refreshFrequencySelection()
    }

    @objc private func amountChanged() {
        guard !isApplyingFieldMask else { return }
        isApplyingFieldMask = true
        totalValueField.text = Formatters.formatCurrencyInput(totalValueField.text ?? "")
        isApplyingFieldMask = false
        refreshTotalSummary()
    }

    @objc private func installmentsChanged() {
        let digits = String(Formatters.digitsOnly(installmentsField.text ?? "").prefix(3))
        guard let numericValue = Int(digits), digits.isEmpty == false else {
            explicitInstallmentCount = nil
            installmentsField.text = ""
            return
        }

        let normalizedValue = min(max(numericValue, 2), 120)
        explicitInstallmentCount = normalizedValue
        installmentsField.text = String(normalizedValue)
    }

    @objc private func phoneFieldChanged(_ sender: UITextField) {
        guard !isApplyingFieldMask else { return }
        isApplyingFieldMask = true
        sender.text = formatPhone(sender.text ?? "")
        isApplyingFieldMask = false
    }

    @objc private func documentFieldChanged(_ sender: UITextField) {
        guard !isApplyingFieldMask else { return }
        isApplyingFieldMask = true
        sender.text = Formatters.formatCPFOrCNPJ(sender.text ?? "")
        isApplyingFieldMask = false
    }

    @objc private func creditorPixKeyChanged() {
        guard !isApplyingFieldMask else { return }
        isApplyingFieldMask = true
        switch selectedPixKeyType {
        case .cpfCnpj:
            creditorPixKeyField.text = Formatters.formatCPFOrCNPJ(creditorPixKeyField.text ?? "")
        case .phone:
            creditorPixKeyField.text = formatPhone(creditorPixKeyField.text ?? "")
        case .email:
            creditorPixKeyField.text = creditorPixKeyField.text?.lowercased()
        case .random:
            break
        }
        isApplyingFieldMask = false
    }

    @objc private func creditorCEPChanged() {
        handleCEPFieldChanged(for: .creditor)
    }

    @objc private func debtorCEPChanged() {
        handleCEPFieldChanged(for: .debtor)
    }

    private func handleCEPFieldChanged(for participant: AddressParticipant) {
        guard !isApplyingFieldMask else { return }
        isApplyingFieldMask = true
        let currentField = cepField(for: participant)
        currentField.text = Formatters.formatCEP(currentField.text ?? "")
        isApplyingFieldMask = false

        if Formatters.digitsOnly(currentField.text ?? "").count < 8 {
            resetAddressLookupState(for: participant)
        }
    }

    @objc private func lookupCreditorCEP() {
        lookupCEP(for: .creditor, isRequired: false)
    }

    @objc private func lookupDebtorCEP() {
        lookupCEP(for: .debtor, isRequired: true)
    }

    private func lookupCEP(for participant: AddressParticipant, isRequired: Bool) {
        let rawCEP = Formatters.digitsOnly(cepField(for: participant).text ?? "")
        guard rawCEP.count == 8 else {
            showSimpleToast("Informe um CEP válido com 8 dígitos.", style: .error)
            return
        }

        cancelAddressLookupTask(for: participant)
        setAddressLookupLoading(true, for: participant)
        feedbackLabel(for: participant).text = "Buscando endereço..."
        feedbackLabel(for: participant).textColor = UIColor(hex: "#1E89B8")

        let task = Task { [weak self] in
            guard let self else { return }

            do {
                let preview = try await self.actionsService.fetchAddressPreview(cep: rawCEP)
                await MainActor.run {
                    self.applyAddressPreview(preview, for: participant)
                }
            } catch {
                await MainActor.run {
                    self.clearAddressPreview(for: participant)
                    self.feedbackLabel(for: participant).text = isRequired ? "CEP não encontrado ou inválido." : "CEP não encontrado. Você ainda pode seguir sem o endereço do credor."
                    self.feedbackLabel(for: participant).textColor = UIColor(hex: "#C94D5D")
                    self.setAddressLookupLoading(false, for: participant)
                }
            }
        }

        assignAddressLookupTask(task, for: participant)
    }

    private func applyAddressPreview(_ preview: PortalAddressPreview, for participant: AddressParticipant) {
        setAddressPreview(preview, for: participant)
        cepField(for: participant).text = preview.cep
        previewField(for: participant).text = preview.formattedLine
        previewField(for: participant).isHidden = preview.formattedLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        feedbackLabel(for: participant).text = "Endereço encontrado com sucesso."
        feedbackLabel(for: participant).textColor = UIColor(hex: "#149C5C")
        setAddressLookupLoading(false, for: participant)
    }

    private func resetAddressLookupState(for participant: AddressParticipant) {
        clearAddressPreview(for: participant)
        feedbackLabel(for: participant).text = "Use o CEP para preencher logradouro, bairro, cidade e estado automaticamente."
        feedbackLabel(for: participant).textColor = UIColor(hex: "#607993")
    }

    private func clearAddressPreview(for participant: AddressParticipant) {
        setAddressPreview(nil, for: participant)
        previewField(for: participant).text = nil
        previewField(for: participant).isHidden = true
    }

    private func setAddressLookupLoading(_ isLoading: Bool, for participant: AddressParticipant) {
        let button = lookupButton(for: participant)
        button.isEnabled = !isLoading
        button.alpha = isLoading ? 0.65 : 1
    }

    private func cancelAddressLookupTask(for participant: AddressParticipant) {
        switch participant {
        case .creditor:
            creditorAddressLookupTask?.cancel()
        case .debtor:
            debtorAddressLookupTask?.cancel()
        }
    }

    private func assignAddressLookupTask(_ task: Task<Void, Never>, for participant: AddressParticipant) {
        switch participant {
        case .creditor:
            creditorAddressLookupTask = task
        case .debtor:
            debtorAddressLookupTask = task
        }
    }

    private func setAddressPreview(_ preview: PortalAddressPreview?, for participant: AddressParticipant) {
        switch participant {
        case .creditor:
            creditorAddressPreview = preview
        case .debtor:
            debtorAddressPreview = preview
        }
    }

    private func cepField(for participant: AddressParticipant) -> UITextField {
        switch participant {
        case .creditor:
            return creditorCEPField
        case .debtor:
            return debtorCEPField
        }
    }

    private func previewField(for participant: AddressParticipant) -> UITextField {
        switch participant {
        case .creditor:
            return creditorFields.addressField
        case .debtor:
            return debtorFields.addressField
        }
    }

    private func feedbackLabel(for participant: AddressParticipant) -> UILabel {
        switch participant {
        case .creditor:
            return creditorAddressFeedbackLabel
        case .debtor:
            return debtorAddressFeedbackLabel
        }
    }

    private func lookupButton(for participant: AddressParticipant) -> UIButton {
        switch participant {
        case .creditor:
            return creditorCEPButton
        case .debtor:
            return debtorCEPButton
        }
    }

    @objc private func confirmDueDateSelection() {
        selectedDueDate = dueDatePicker.date
        dueDateField.text = Formatters.shortDate.string(from: dueDatePicker.date)
        dueDateField.resignFirstResponder()
    }

    @objc private func doneKeyboardTapped() {
        view.endEditing(true)
    }

    @objc private func registerTapped() {
        view.endEditing(true)

        let typedSubject = subjectField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = descriptionTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let debtorName = debtorFields.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let debtorDocument = debtorFields.documentField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let debtorEmail = debtorFields.emailField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let debtorPhone = debtorFields.phoneField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let debtorCEP = debtorCEPField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let debtorNumber = debtorNumberField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let debtorComplement = debtorComplementField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let amount = currentAmount()

        guard !(typedSubject.isEmpty && description.isEmpty) else {
            showSimpleToast("Informe pelo menos o assunto ou a descrição do contrato.", style: .error)
            return
        }

        let subject = typedSubject.isEmpty ? inferredContractSubject(fallbackDebtorName: debtorName) : typedSubject
        let title = buildContractTitle(subject: subject)

        guard amount > .zero else {
            showSimpleToast("Informe um valor total maior que zero.", style: .error)
            return
        }

        guard let dueDate = selectedDueDate else {
            showSimpleToast("Selecione o primeiro vencimento.", style: .error)
            return
        }

        guard !debtorName.isEmpty else {
            showSimpleToast("Informe o nome do devedor.", style: .error)
            return
        }

        guard !selectedPaymentMethods.isEmpty else {
            showSimpleToast("Selecione ao menos um meio de pagamento.", style: .error)
            return
        }

        let installmentCount = currentInstallmentCount()
        if selectedFrequency == .installment && installmentCount < 2 {
            showSimpleToast("Informe pelo menos 2 parcelas para o contrato parcelado.", style: .error)
            return
        }

        if actionsService.isRemoteMode && aiService.canUseCompanyScopedIntegration(with: session) {
            guard creditorFields.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                showSimpleToast("Informe o nome do credor.", style: .error)
                return
            }
            guard creditorFields.documentField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                showSimpleToast("Informe o CPF/CNPJ do credor.", style: .error)
                return
            }
            guard creditorFields.phoneField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                showSimpleToast("Informe o telefone do credor.", style: .error)
                return
            }
            guard creditorPixKeyField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                showSimpleToast("Informe a chave PIX do credor.", style: .error)
                return
            }
            guard Formatters.digitsOnly(creditorCEPField.text ?? "").count == 8 else {
                showSimpleToast("Informe um CEP válido do credor.", style: .error)
                return
            }
            guard creditorNumberField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                showSimpleToast("Informe o número do endereço do credor.", style: .error)
                return
            }
            guard debtorDocument.isEmpty == false else {
                showSimpleToast("Informe o CPF/CNPJ do devedor.", style: .error)
                return
            }
            guard debtorEmail.isEmpty == false else {
                showSimpleToast("Informe o e-mail do devedor.", style: .error)
                return
            }
            guard debtorPhone.isEmpty == false else {
                showSimpleToast("Informe o telefone do devedor.", style: .error)
                return
            }
            guard Formatters.digitsOnly(debtorCEP).count == 8 else {
                showSimpleToast("Informe um CEP válido do devedor.", style: .error)
                return
            }
            guard debtorNumber.isEmpty == false else {
                showSimpleToast("Informe o número do endereço do devedor.", style: .error)
                return
            }
        }

        let confirmationInput = AIContractConfirmationInput(
            title: title,
            subject: subject,
            description: description,
            totalValueText: totalValueField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? amount.asCurrency,
            dueDate: dueDate,
            installmentCount: payloadInstallmentCount(),
            businessType: selectedBusinessType.backendValue,
            paymentFrequency: selectedFrequency.backendValue,
            paymentMethods: selectedPaymentMethods.map(\.aiCode).sorted { $0.rawValue < $1.rawValue },
            creditorName: creditorFields.nameField.text,
            creditorDocument: creditorFields.documentField.text,
            creditorEmail: creditorFields.emailField.text,
            creditorPhone: creditorFields.phoneField.text,
            creditorPersonType: selectedCreditorPersonType.backendValue,
            creditorPixKey: creditorPixKeyField.text,
            creditorPixKeyType: selectedPixKeyType.backendValue,
            creditorCEP: creditorCEPField.text,
            creditorAddressNumber: creditorNumberField.text,
            creditorAddressComplement: creditorComplementField.text,
            creditorAddress: normalizedCreditorAddressSummary(),
            debtorName: debtorName,
            debtorDocument: debtorDocument,
            debtorEmail: debtorEmail,
            debtorPhone: debtorPhone,
            debtorCEP: debtorCEP,
            debtorAddressNumber: debtorNumber,
            debtorAddressComplement: debtorComplement,
            debtorAddress: normalizedDebtorAddressSummary()
        )

        persistLocally(subject: subject, debtorName: debtorName, amount: amount, dueDate: dueDate)

        registerTask?.cancel()
        setRegisterProcessing(true)
        registerTask = Task { [weak self] in
            guard let self else { return }
            let syncOutcome = await self.performRemoteConfirmationIfPossible(with: confirmationInput)
            let fallbackContractText = self.creditorContractText(for: confirmationInput)
            let normalizedAmountText = Formatters.normalizeCurrencyDisplay(confirmationInput.totalValueText)

            await MainActor.run {
                self.setRegisterProcessing(false)
                self.showSimpleToast(syncOutcome.message, style: syncOutcome.style)
                if let remoteContractID = syncOutcome.remoteContractID {
                    self.presentCreatedContractPopup(
                        contractID: remoteContractID,
                        fallbackText: fallbackContractText,
                        debtTitle: confirmationInput.subject,
                        amountText: normalizedAmountText,
                        debtorDocument: confirmationInput.debtorDocument
                    )
                } else {
                    self.presentLocalContractPDFPreviewIfPossible(
                        contractText: fallbackContractText,
                        title: confirmationInput.subject
                    )
                }
                self.resetForm()
            }
        }
    }

    private func persistLocally(subject: String, debtorName: String, amount: Decimal, dueDate: Date) {
        dataStore.upsertDebtor(
            name: debtorName,
            document: debtorFields.documentField.text ?? "",
            email: debtorFields.emailField.text ?? "",
            phone: debtorFields.phoneField.text ?? ""
        )
        dataStore.addContract(title: subject, debtorName: debtorName, amount: amount)
        dataStore.addDebt(title: subject, debtorName: debtorName, amount: amount, dueDate: dueDate)
    }

    private func performRemoteConfirmationIfPossible(
        with input: AIContractConfirmationInput
    ) async -> RemoteContractSyncOutcome {
        guard actionsService.isRemoteMode else {
            return RemoteContractSyncOutcome(
                message: "Contrato registrado localmente.",
                style: .success,
                remoteContractID: nil
            )
        }

        guard aiService.canUseCompanyScopedIntegration(with: session) else {
            return RemoteContractSyncOutcome(
                message: "Contrato registrado localmente. A conta atual ainda não possui uma empresa credora vinculada, então não consigo gerar o contrato remoto nem o PDF.",
                style: .info,
                remoteContractID: nil
            )
        }

        do {
            let result = try await aiService.createContractViaFlow(input, session: session)
            return RemoteContractSyncOutcome(
                message: "Contrato registrado localmente e sincronizado com o contrato remoto \(result.contractID). Vou abrir a revisão do contrato para PDF e assinatura.",
                style: .success,
                remoteContractID: result.contractID
            )
        } catch let error as AIExtractionServiceError {
            switch error {
            case let .missingRequiredFields(fields):
                let readableFields = fields.isEmpty ? "dados adicionais" : fields.joined(separator: ", ")
                return RemoteContractSyncOutcome(
                    message: "Contrato registrado localmente. O backend ainda precisa destes campos para concluir a versão remota: \(readableFields).",
                    style: .info,
                    remoteContractID: nil
                )
            case .missingCompanyContext:
                return RemoteContractSyncOutcome(
                    message: "Contrato registrado localmente. A sessão atual não trouxe a empresa credora necessária para concluir a versão remota e o PDF.",
                    style: .info,
                    remoteContractID: nil
                )
            default:
                let errorMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                if errorMessage.isEmpty {
                    return RemoteContractSyncOutcome(
                        message: "Contrato registrado localmente. A sincronização remota do contrato falhou.",
                        style: .info,
                        remoteContractID: nil
                    )
                }

                return RemoteContractSyncOutcome(
                    message: "Contrato registrado localmente. A sincronização remota do contrato falhou: \(errorMessage)",
                    style: .info,
                    remoteContractID: nil
                )
            }
        } catch {
            let errorMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if errorMessage.isEmpty {
                return RemoteContractSyncOutcome(
                    message: "Contrato registrado localmente. A sincronização remota do contrato falhou.",
                    style: .info,
                    remoteContractID: nil
                )
            }

            return RemoteContractSyncOutcome(
                message: "Contrato registrado localmente. A sincronização remota do contrato falhou: \(errorMessage)",
                style: .info,
                remoteContractID: nil
            )
        }
    }

    /// Aqui eu abro a revisão do contrato recém-criado usando o mesmo modal remoto das telas de cobrança.
    private func presentCreatedContractPopup(
        contractID: String,
        fallbackText: String,
        debtTitle: String,
        amountText: String,
        debtorDocument: String?
    ) {
        let popup = ContractDigitalPopupViewController(
            mode: .creditorActions,
            contractTextOverride: fallbackText
        )
        hydrateContractPopup(popup, contractID: contractID)
        popup.onDownload = { [weak self, weak popup] in
            self?.downloadContractIfPossible(
                contractID: contractID,
                fallbackText: fallbackText,
                title: debtTitle,
                presenter: popup
            )
        }
        popup.onProtest = { [weak self, weak popup] in
            popup?.dismiss(animated: true) {
                self?.presentSerasaPopup(
                    debtTitle: debtTitle,
                    amountText: amountText,
                    documentText: debtorDocument ?? "não informado"
                )
            }
        }
        popup.onSignAsCreditor = { [weak self, weak popup] in
            popup?.dismiss(animated: true) {
                self?.presentGovBrCreditorPopup(
                    contractID: contractID,
                    contractText: popup?.currentContractText ?? fallbackText
                )
            }
        }
        present(popup, animated: true) { [weak self, weak popup] in
            self?.previewContractDocumentIfPossible(
                contractID: contractID,
                fallbackText: fallbackText,
                title: debtTitle,
                presenter: popup
            )
        }
    }

    /// Aqui eu apresento a segunda etapa de assinatura do credor usando as mesmas rotas do fluxo web.
    private func presentGovBrCreditorPopup(contractID: String, contractText: String) {
        let popup = ContractDigitalPopupViewController(
            mode: .govBrCreditor,
            contractTextOverride: contractText
        )
        popup.onDraw = { [weak self, weak popup] in
            guard let popup else { return }
            self?.signCreditorContract(contractID: contractID, signatureType: .physical, popup: popup)
        }
        popup.onGovBr = { [weak self, weak popup] in
            guard let popup else { return }
            self?.signCreditorContract(contractID: contractID, signatureType: .govBr, popup: popup)
        }
        present(popup, animated: true)
    }

    /// Aqui eu carrego o texto contratual remoto sem bloquear a abertura do modal recém-criado.
    private func hydrateContractPopup(_ popup: ContractDigitalPopupViewController, contractID: String) {
        Task { [weak self, weak popup] in
            guard let self else { return }

            do {
                let detail = try await self.actionsService.fetchContractDetail(contractID: contractID)
                await MainActor.run {
                    popup?.updateContractText(detail.contractText)
                }
            } catch {
                await MainActor.run {
                    self.showSimpleToast("Não consegui carregar o texto remoto agora. Mantive a minuta local.", style: .info)
                }
            }
        }
    }

    /// Aqui eu obtenho o arquivo do contrato recém-criado pela mesma rota usada no dashboard e no web.
    private func downloadContractIfPossible(
        contractID: String,
        fallbackText: String? = nil,
        title: String? = nil,
        presenter: UIViewController?
    ) {
        Task { [weak self] in
            guard let self else { return }

            do {
                let fileURL = try await self.downloadContractDocumentWithRetry(contractID: contractID)
                await MainActor.run {
                    self.presentDocumentPreview(
                        fileURL: fileURL,
                        title: title ?? "Contrato Digital",
                        preferredPresenter: presenter
                    )
                }
            } catch {
                await MainActor.run {
                    if let fallbackText, let title {
                        self.presentLocalContractPDFPreviewIfPossible(
                            contractText: fallbackText,
                            title: title,
                            preferredPresenter: presenter
                        )
                        self.showSimpleToast("Não consegui abrir o contrato remoto agora. Abri a visualização local do contrato.", style: .info)
                    } else {
                        self.showSimpleToast(error.localizedDescription, style: .error)
                    }
                }
            }
        }
    }

    /// Aqui eu dou uma pequena tolerância para o backend terminar de materializar o arquivo do contrato recém-criado.
    private func downloadContractDocumentWithRetry(contractID: String) async throws -> URL {
        try await actionsService.downloadContractDocumentWithShortRetry(contractID: contractID)
    }

    /// Aqui eu abro automaticamente o contrato recém-gerado para não deixar o usuário sem retorno visual da visualização final.
    private func previewContractDocumentIfPossible(
        contractID: String,
        fallbackText: String,
        title: String,
        presenter: UIViewController?
    ) {
        downloadContractIfPossible(
            contractID: contractID,
            fallbackText: fallbackText,
            title: title,
            presenter: presenter
        )
    }

    /// Aqui eu concluo a assinatura do credor na sequência do contrato recém-gerado.
    private func signCreditorContract(
        contractID: String,
        signatureType: PortalContractSignatureType,
        popup: UIViewController
    ) {
        Task { [weak self, weak popup] in
            guard let self else { return }

            do {
                _ = try await self.actionsService.signContractAsCreditor(
                    contractID: contractID,
                    signatureType: signatureType
                )

                await MainActor.run {
                    popup?.dismiss(animated: true) {
                        self.showSimpleToast("Contrato assinado com sucesso pelo credor.", style: .success)
                    }
                }
            } catch {
                await MainActor.run {
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    /// Aqui eu reaproveito o popup de Serasa para o contrato recém-gerado sem inventar um fluxo paralelo.
    private func presentSerasaPopup(debtTitle: String, amountText: String, documentText: String) {
        let popup = SerasaPopupViewController(
            debtTitle: debtTitle,
            amountText: amountText,
            documentText: documentText,
            overdueText: "a verificar"
        )
        popup.onConfirmNegativation = { [weak self, weak popup] in
            popup?.dismiss(animated: true) {
                self?.showSimpleToast("Negativação enviada para Serasa (simulação).", style: .success)
            }
        }
        present(popup, animated: true)
    }

    /// Aqui eu gero uma minuta de apoio local para não deixar o modal vazio antes da hidratação remota.
    private func creditorContractText(for input: AIContractConfirmationInput) -> String {
        """
        CONTRATO DE RECONHECIMENTO DE DÍVIDA

        Pelo presente instrumento particular, as partes abaixo qualificadas têm entre si justo e contratado o seguinte:

        CLÁUSULA 1ª - DO OBJETO
        O presente contrato tem por objeto o reconhecimento de dívida referente a "\(input.subject)".

        CLÁUSULA 2ª - DO VENCIMENTO
        A dívida tem vencimento em \(Formatters.fullNumericDate.string(from: input.dueDate)).

        CLÁUSULA 3ª - DA FORMA DE PAGAMENTO
        O pagamento será realizado conforme condições acordadas entre as partes, com valor de referência em \(Formatters.normalizeCurrencyDisplay(input.totalValueText)).

        CLÁUSULA 4ª - DA MULTA E JURO
        Em caso de atraso, poderão incidir multa e juros conforme legislação aplicável.

        Documento gerado por IA e validado eletronicamente via BillEasy.ia.
        """
    }

    /// Aqui eu gero um PDF local como fallback quando a conta ainda não está no fluxo remoto ou quando a rota demora.
    private func presentLocalContractPDFPreviewIfPossible(
        contractText: String,
        title: String,
        preferredPresenter: UIViewController? = nil
    ) {
        do {
            try presentLocalContractDocumentPreview(
                contractText: contractText,
                title: title,
                preferredPresenter: preferredPresenter
            )
        } catch {
            showSimpleToast("Não consegui gerar a visualização local do contrato.", style: .error)
        }
    }

    /// Aqui eu mostro o PDF em leitura real no app e deixo o compartilhamento como ação secundária.
    private func presentDocumentPreview(fileURL: URL, title: String, preferredPresenter: UIViewController?) {
        presentContractDocumentPreview(fileURL: fileURL, title: title, preferredPresenter: preferredPresenter)
    }

    private func setRegisterProcessing(_ isProcessing: Bool) {
        registerButton.isEnabled = !isProcessing
        registerButton.alpha = isProcessing ? 0.76 : 1
        refreshPrimaryActionPresentation(isProcessing: isProcessing)
    }

    private func resetForm() {
        selectedCreationMethod = .ai
        selectedBusinessType = .general
        selectedFrequency = .single
        selectedCreditorPersonType = .individual
        selectedPixKeyType = .cpfCnpj
        selectedPaymentMethods = [.pix]
        selectedDueDate = nil
        explicitInstallmentCount = nil
        uploadedContractFilename = nil
        creditorAddressPreview = nil
        debtorAddressPreview = nil

        subjectField.text = nil
        descriptionTextView.text = nil
        totalValueField.text = nil
        installmentsField.text = nil
        dueDateField.text = nil
        creditorFields.orderedFields.forEach { $0.text = nil }
        creditorPixKeyField.text = nil
        creditorCEPField.text = nil
        creditorNumberField.text = nil
        creditorComplementField.text = nil
        creditorFields.addressField.text = nil
        creditorFields.addressField.isHidden = true
        debtorFields.orderedFields.forEach { $0.text = nil }
        debtorCEPField.text = nil
        debtorNumberField.text = nil
        debtorComplementField.text = nil
        debtorFields.addressField.text = nil
        debtorFields.addressField.isHidden = true

        singleInstallmentSwitch.setOn(true, animated: false)
        applyExtractionStatus(.hidden)
        creditorAddressFeedbackLabel.text = "Use o CEP para preencher logradouro, bairro, cidade e estado automaticamente."
        creditorAddressFeedbackLabel.textColor = UIColor(hex: "#607993")
        debtorAddressFeedbackLabel.text = "Use o CEP para preencher logradouro, bairro, cidade e estado automaticamente."
        debtorAddressFeedbackLabel.textColor = UIColor(hex: "#607993")
        refreshBusinessTypeSelection()
        refreshCreditorPersonTypeSelection()
        refreshCreditorPixKeyTypeSelection()
        refreshFrequencySelection()
        refreshMethodSelection()
        refreshPaymentMethods()
        refreshPixKeyPlaceholder()
        refreshDescriptionPlaceholder()
        refreshTotalSummary()
        refreshPrimaryActionPresentation()
    }

    private func togglePaymentMethod(_ method: PaymentMethod) {
        if selectedPaymentMethods.contains(method) {
            selectedPaymentMethods.remove(method)
        } else {
            selectedPaymentMethods.insert(method)
        }
        refreshPaymentMethods()
    }

    private func currentAmount() -> Decimal {
        Formatters.decimalFromCurrencyInput(totalValueField.text ?? "")
    }

    private func currentInstallmentCount() -> Int {
        if selectedFrequency == .single {
            return 1
        }

        let rawValue = Int(Formatters.digitsOnly(installmentsField.text ?? "")) ?? 0
        return max(rawValue, 0)
    }

    private func payloadInstallmentCount() -> Int? {
        if selectedFrequency == .single {
            return explicitInstallmentCount == 1 ? 1 : nil
        }

        let rawValue = Int(Formatters.digitsOnly(installmentsField.text ?? "")) ?? 0
        return rawValue > 1 ? rawValue : explicitInstallmentCount
    }

    private func fileIcon(forFilename filename: String?) -> UIImage? {
        guard let filename else {
            return UIImage(systemName: "doc")
        }

        let lowercasedName = filename.lowercased()
        if lowercasedName.hasSuffix(".pdf") {
            return UIImage(systemName: "doc.text")
        }
        if lowercasedName.hasSuffix(".jpg")
            || lowercasedName.hasSuffix(".jpeg")
            || lowercasedName.hasSuffix(".png")
            || lowercasedName.hasSuffix(".gif")
            || lowercasedName.hasSuffix(".bmp")
            || lowercasedName.hasSuffix(".tif")
            || lowercasedName.hasSuffix(".tiff")
            || lowercasedName.hasSuffix(".webp") {
            return UIImage(systemName: "photo")
        }
        return UIImage(systemName: "doc")
    }

    private func applyDebugFileReviewPreviewIfNeeded() {
        guard didApplyDebugFileReviewPreview == false, let fileURL = debugFileReviewPreviewURL else {
            return
        }

        didApplyDebugFileReviewPreview = true
        uploadedContractFilename = fileURL.lastPathComponent

        let dueDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 4, day: 10))
        applyDraftFromFileUpload(
            AIContractDraft(
                suggestedBusinessType: "ACORDO_PAGAMENTO",
                suggestedSubject: "Acordo de Parcelamento",
                suggestedDescription: "Acordo referente a venda de materiais de construção no valor de R$ 2.500,00.",
                totalValueText: "2500.00",
                installmentCount: 1,
                dueDateText: "2026-04-10",
                creditorName: "BillEasy Credora Ltda",
                creditorDocument: "12345678000190",
                creditorPhone: "11988880000",
                debtorName: "Samuel Jammes",
                debtorDocument: "06427166174",
                debtorEmail: "s.jammes3@gmail.com",
                debtorPhone: "61993011072"
            )
        )
        if let dueDate {
            selectedDueDate = dueDate
            dueDatePicker.date = dueDate
            dueDateField.text = Formatters.shortDate.string(from: dueDate)
        }
        applyExtractionStatus(.hidden)
    }

    private func refreshPrimaryActionPresentation(isProcessing: Bool = false) {
        registerButton.setContent(
            title: isProcessing
                ? "Gerando contrato..."
                : "Gerar Contrato",
            iconSystemName: isProcessing
                ? "arrow.triangle.2.circlepath"
                : (selectedCreationMethod == .ai ? "sparkles" : "doc.badge.plus")
        )
    }

    private func buildContractTitle(subject: String) -> String {
        "\(selectedBusinessType.title) - \(subject)"
    }

    private func inferredContractSubject(fallbackDebtorName: String) -> String {
        let debtorFallback = fallbackDebtorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if debtorFallback.isEmpty == false {
            return debtorFallback
        }
        return "Novo Contrato"
    }

    private func normalizedCreditorAddressSummary() -> String? {
        let preview = creditorFields.addressField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = creditorNumberField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let complement = creditorComplementField.text?.trimmingCharacters(in: .whitespacesAndNewlines)

        var components: [String] = []
        if let preview, !preview.isEmpty { components.append(preview) }
        if let number, !number.isEmpty { components.append("Número: \(number)") }
        if let complement, !complement.isEmpty { components.append("Complemento: \(complement)") }

        return components.isEmpty ? nil : components.joined(separator: " • ")
    }

    private func normalizedDebtorAddressSummary() -> String? {
        let preview = debtorFields.addressField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = debtorNumberField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let complement = debtorComplementField.text?.trimmingCharacters(in: .whitespacesAndNewlines)

        var components: [String] = []
        if let preview, !preview.isEmpty { components.append(preview) }
        if let number, !number.isEmpty { components.append("Número: \(number)") }
        if let complement, !complement.isEmpty { components.append("Complemento: \(complement)") }

        return components.isEmpty ? nil : components.joined(separator: " • ")
    }

    private func formatPhone(_ value: String) -> String {
        let raw = String(value.filter(\.isNumber).prefix(11))
        guard !raw.isEmpty else { return "" }

        var result = ""
        for (index, char) in raw.enumerated() {
            switch index {
            case 0: result.append("(")
            case 2: result.append(") ")
            case 7: result.append("-")
            default: break
            }
            result.append(char)
        }
        return result
    }

    private func makeAISeedText() -> String {
        var lines: [String] = []
        if let subject = subjectField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
            lines.append("Assunto: \(subject)")
        }
        if let description = descriptionTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            lines.append("Descrição do acordo: \(description)")
        }
        if let amount = totalValueField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !amount.isEmpty {
            lines.append("Valor total: \(amount)")
        }
        if let dueDate = dueDateField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !dueDate.isEmpty {
            lines.append("Vencimento: \(dueDate)")
        }
        if let debtorName = debtorFields.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !debtorName.isEmpty {
            lines.append("Devedor: \(debtorName)")
        }
        if let debtorDocument = debtorFields.documentField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !debtorDocument.isEmpty {
            lines.append("CPF/CNPJ do devedor: \(debtorDocument)")
        }
        if let debtorCEP = debtorCEPField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !debtorCEP.isEmpty {
            lines.append("CEP do devedor: \(debtorCEP)")
        }
        if let debtorNumber = debtorNumberField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !debtorNumber.isEmpty {
            lines.append("Número do endereço: \(debtorNumber)")
        }
        if let creditorName = creditorFields.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !creditorName.isEmpty {
            lines.append("Credor: \(creditorName)")
        }
        if let creditorCEP = creditorCEPField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !creditorCEP.isEmpty {
            lines.append("CEP do credor: \(creditorCEP)")
        }
        if let creditorNumber = creditorNumberField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !creditorNumber.isEmpty {
            lines.append("Número do endereço do credor: \(creditorNumber)")
        }
        if let creditorAddress = normalizedCreditorAddressSummary(), !creditorAddress.isEmpty {
            lines.append("Endereço do credor: \(creditorAddress)")
        }
        if lines.isEmpty == false {
            lines.insert("Tipo do negócio: \(selectedBusinessType.title)", at: 0)
        }
        return lines.joined(separator: "\n")
    }

    private func applyAudioCaptureResult(_ result: ContractAudioCaptureResult) {
        selectedCreationMethod = .file
        if let businessTypeAnswer = result.answers[.businessType] {
            applyBusinessTypeAnswer(businessTypeAnswer)
        }
        if let subjectAnswer = result.answers[.subject], subjectField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            subjectField.text = subjectAnswer
        }
        if let descriptionAnswer = result.answers[.description], descriptionTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            descriptionTextView.text = descriptionAnswer
        }
        if let amountAnswer = result.answers[.amount], totalValueField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            totalValueField.text = Formatters.normalizeCurrencyDisplay(amountAnswer)
        }
        if let dueDateAnswer = result.answers[.dueDate], let parsedDate = parseAIExtractedDate(dueDateAnswer) {
            selectedDueDate = parsedDate
            dueDatePicker.date = parsedDate
            dueDateField.text = Formatters.shortDate.string(from: parsedDate)
        }
        if let creditorName = result.answers[.creditorName], creditorFields.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            creditorFields.nameField.text = creditorName
        }
        if let creditorDocument = result.answers[.creditorDocument], creditorFields.documentField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            creditorFields.documentField.text = Formatters.formatCPFOrCNPJ(creditorDocument)
        }
        if let debtorName = result.answers[.debtorName], debtorFields.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            debtorFields.nameField.text = debtorName
        }
        if let debtorDocument = result.answers[.debtorDocument], debtorFields.documentField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            debtorFields.documentField.text = Formatters.formatCPFOrCNPJ(debtorDocument)
        }
        if let paymentMethodAnswer = result.answers[.paymentMethod] {
            applyPaymentMethodAnswer(paymentMethodAnswer)
        }

        applyDraftFromAI(result.draft)
        selectedCreationMethod = .file
        refreshMethodSelection()
        refreshPrimaryActionPresentation()
        refreshDescriptionPlaceholder()
        refreshTotalSummary()
    }

    private func applyDraftFromFileUpload(_ draft: AIContractDraft) {
        applyDraftFromAI(draft)
        selectedCreationMethod = .file
        refreshMethodSelection()
        refreshPrimaryActionPresentation()
        refreshDescriptionPlaceholder()
        refreshTotalSummary()
    }

    private func applyDraftFromAI(_ draft: AIContractDraft) {
        selectedCreationMethod = .ai
        if let businessType = draft.suggestedBusinessType {
            applyBusinessTypeAnswer(businessType)
        }
        if subjectField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            subjectField.text = draft.suggestedSubject ?? "Acordo via IA"
        }
        if descriptionTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            descriptionTextView.text = draft.suggestedDescription
        }
        if totalValueField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let totalValueText = draft.totalValueText {
            totalValueField.text = Formatters.normalizeCurrencyDisplay(totalValueText)
        }
        if let installmentCount = draft.installmentCount {
            explicitInstallmentCount = installmentCount
            if installmentCount > 1 {
                selectedFrequency = .installment
                installmentsField.text = String(installmentCount)
            } else {
                selectedFrequency = .single
                installmentsField.text = "1"
            }
            refreshFrequencySelection()
        } else if selectedFrequency == .single {
            explicitInstallmentCount = nil
            installmentsField.text = nil
        }
        if dueDateField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let dueDate = parseAIExtractedDate(draft.dueDateText) {
            selectedDueDate = dueDate
            dueDatePicker.date = dueDate
            dueDateField.text = Formatters.shortDate.string(from: dueDate)
        }
        if creditorFields.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let creditorName = draft.creditorName?.trimmingCharacters(in: .whitespacesAndNewlines), !creditorName.isEmpty {
            creditorFields.nameField.text = creditorName
        }
        if creditorFields.documentField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let creditorDocument = draft.creditorDocument {
            creditorFields.documentField.text = Formatters.formatCPFOrCNPJ(creditorDocument)
        }
        if creditorFields.phoneField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let creditorPhone = draft.creditorPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !creditorPhone.isEmpty {
            creditorFields.phoneField.text = formatPhone(creditorPhone)
        }
        if debtorFields.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            debtorFields.nameField.text = draft.debtorName
        }
        if debtorFields.documentField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let debtorDocument = draft.debtorDocument {
            debtorFields.documentField.text = Formatters.formatCPFOrCNPJ(debtorDocument)
        }
        if debtorFields.emailField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let debtorEmail = draft.debtorEmail?.trimmingCharacters(in: .whitespacesAndNewlines), !debtorEmail.isEmpty {
            debtorFields.emailField.text = debtorEmail
        }
        if debtorFields.phoneField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           let debtorPhone = draft.debtorPhone?.trimmingCharacters(in: .whitespacesAndNewlines), !debtorPhone.isEmpty {
            debtorFields.phoneField.text = formatPhone(debtorPhone)
        }
        refreshMethodSelection()
        refreshPrimaryActionPresentation()
        refreshDescriptionPlaceholder()
        refreshTotalSummary()
    }

    private func presentAIPreviewIfPossible() {
        let snapshot = ContractAIReviewSnapshot(
            businessType: selectedBusinessType.title,
            subject: subjectField.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Não informado",
            description: descriptionTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Não informada",
            totalValueText: Formatters.normalizeCurrencyDisplay(totalValueField.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "R$ 0,00"),
            dueDateText: Formatters.normalizeDateDisplay(dueDateField.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Não informado"),
            creditorName: creditorFields.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Não informado",
            debtorName: debtorFields.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Não informado"
        )

        let controller = ContractAIPreviewViewController(snapshot: snapshot)
        present(controller, animated: true)
    }

    private func applyBusinessTypeAnswer(_ value: String) {
        let normalized = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        if normalized.contains("alugu") {
            selectedBusinessType = .rent
        } else if normalized.contains("servi") {
            selectedBusinessType = .service
        } else if normalized.contains("emprest") {
            selectedBusinessType = .loan
        } else if normalized.contains("acordo") || normalized.contains("pagament") {
            selectedBusinessType = .paymentAgreement
        } else if normalized.contains("venda") || normalized.contains("compr") || normalized.contains("veicul") || normalized.contains("carro") {
            selectedBusinessType = .sale
        } else {
            selectedBusinessType = .general
        }
        refreshBusinessTypeSelection()
    }

    private func applyPaymentMethodAnswer(_ value: String) {
        let normalized = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        var methods: Set<PaymentMethod> = []
        if normalized.contains("pix") { methods.insert(.pix) }
        if normalized.contains("boleto") { methods.insert(.boleto) }
        if normalized.contains("cart") || normalized.contains("credito") { methods.insert(.card) }
        if methods.isEmpty { methods = [.pix] }
        selectedPaymentMethods = methods
        refreshPaymentMethods()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let currentIndex = orderedFields.firstIndex(of: textField) else {
            textField.resignFirstResponder()
            return true
        }

        var nextIndex = currentIndex + 1
        while nextIndex < orderedFields.count {
            let nextField = orderedFields[nextIndex]
            if isEffectivelyVisible(nextField),
               nextField.isUserInteractionEnabled,
               nextField.isEnabled {
                nextField.becomeFirstResponder()
                return true
            }
            nextIndex += 1
        }

        textField.resignFirstResponder()
        return true
    }

    private func isEffectivelyVisible(_ view: UIView) -> Bool {
        guard view.window != nil else { return false }
        var currentView: UIView? = view
        while let inspectedView = currentView {
            if inspectedView.isHidden || inspectedView.alpha <= 0.01 {
                return false
            }
            currentView = inspectedView.superview
        }
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        guard textField === dueDateField else { return }
        dueDatePicker.date = selectedDueDate ?? Date()
    }

    func textViewDidChange(_ textView: UITextView) {
        refreshDescriptionPlaceholder()
    }

    private func parseAIExtractedDate(_ rawValue: String?) -> Date? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            return nil
        }

        let formatters = [
            Formatters.shortDate,
            Self.makeDateFormatter("dd/MM/yyyy"),
            Self.makeDateFormatter("yyyy-MM-dd"),
            Self.makeDateFormatter("yyyy-MM-dd'T'HH:mm:ss"),
            Self.makeDateFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX")
        ]

        for formatter in formatters {
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }

        let isoFormatter = ISO8601DateFormatter()
        return isoFormatter.date(from: rawValue)
    }

    private static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }
}

private final class ContractMethodChoiceButton: UIButton {
    enum Kind {
        case file
        case ai

        var title: String {
            switch self {
            case .file: return "Analisar com Arquivo"
            case .ai: return "Gerar com IA"
            }
        }

        var subtitle: String {
            switch self {
            case .file: return ""
            case .ai: return ""
            }
        }

        var iconName: String {
            switch self {
            case .file: return "square.and.arrow.up.fill"
            case .ai: return "sparkles"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .file: return "contracts.method.file"
            case .ai: return "contracts.method.ai"
            }
        }
    }

    private let kind: Kind
    private let contentView = UIView()
    private let iconBackgroundView = UIView()
    private let iconView = UIImageView()
    private let methodTitleLabel = UILabel()
    private let methodSubtitleLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let gradientLayer = CAGradientLayer()

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = kind.accessibilityIdentifier
        accessibilityLabel = kind.title
        accessibilityTraits = [.button]
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = contentView.bounds
    }

    private func configureView() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.isUserInteractionEnabled = false
        contentView.layer.cornerRadius = 18
        contentView.layer.cornerCurve = .continuous
        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOpacity = 0.14
        contentView.layer.shadowOffset = CGSize(width: 0, height: 10)
        contentView.layer.shadowRadius = 20
        contentView.layer.masksToBounds = false

        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        switch kind {
        case .file:
            gradientLayer.colors = [UIColor(fixedHex: "#2486B0").cgColor, UIColor(fixedHex: "#0E658B").cgColor]
        case .ai:
            gradientLayer.colors = [UIColor(fixedHex: "#FF932F").cgColor, UIColor(fixedHex: "#F24B1A").cgColor]
        }
        gradientLayer.cornerRadius = 18
        contentView.layer.insertSublayer(gradientLayer, at: 0)

        iconBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        iconBackgroundView.isUserInteractionEnabled = false
        iconBackgroundView.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        iconBackgroundView.layer.cornerRadius = 16
        iconBackgroundView.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        iconView.image = UIImage(systemName: kind.iconName)
        iconView.tintColor = .white
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)

        methodTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        methodTitleLabel.isUserInteractionEnabled = false
        methodTitleLabel.text = kind.title
        methodTitleLabel.textColor = .white
        methodTitleLabel.textAlignment = .center
        methodTitleLabel.numberOfLines = 2
        methodTitleLabel.lineBreakMode = .byWordWrapping
        methodTitleLabel.applyScaledFont(size: 15, weight: .black, textStyle: .headline)

        methodSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        methodSubtitleLabel.isUserInteractionEnabled = false
        methodSubtitleLabel.text = kind.subtitle
        methodSubtitleLabel.textColor = UIColor.white.withAlphaComponent(0.84)
        methodSubtitleLabel.textAlignment = .center
        methodSubtitleLabel.numberOfLines = 0
        methodSubtitleLabel.applyScaledFont(size: 11, weight: .medium, textStyle: .caption1)
        methodSubtitleLabel.isHidden = kind.subtitle.isEmpty

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isUserInteractionEnabled = false
        spinner.color = .white
        spinner.hidesWhenStopped = true

        addSubview(contentView)
        contentView.addSubview(iconBackgroundView)
        iconBackgroundView.addSubview(iconView)
        contentView.addSubview(methodTitleLabel)
        contentView.addSubview(methodSubtitleLabel)
        contentView.addSubview(spinner)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            iconBackgroundView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconBackgroundView.widthAnchor.constraint(equalToConstant: 54),
            iconBackgroundView.heightAnchor.constraint(equalToConstant: 54),

            iconView.centerXAnchor.constraint(equalTo: iconBackgroundView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackgroundView.centerYAnchor),

            methodTitleLabel.topAnchor.constraint(equalTo: iconBackgroundView.bottomAnchor, constant: 16),
            methodTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            methodTitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            methodSubtitleLabel.topAnchor.constraint(equalTo: methodTitleLabel.bottomAnchor, constant: 6),
            methodSubtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            methodSubtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    func setLoading(_ isLoading: Bool) {
        isEnabled = !isLoading
        alpha = isLoading ? 0.82 : 1
        if isLoading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    func setSelectedAppearance(_ isSelected: Bool) {
        contentView.layer.borderWidth = isSelected ? 2 : 0
        contentView.layer.borderColor = UIColor.white.withAlphaComponent(isSelected ? 0.72 : 0).cgColor
        contentView.transform = isSelected ? CGAffineTransform(scaleX: 1.02, y: 1.02) : .identity
        contentView.layer.shadowOpacity = isSelected ? 0.22 : 0.14
    }
}

private final class ContractPrimaryActionButton: UIButton {
    private let gradientLayer = CAGradientLayer()
    private let contentStack = UIStackView()
    private let iconView = UIImageView()
    private let actionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureContent()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
        configureContent()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    private func configureAppearance() {
        tintColor = .white
        layer.cornerRadius = 12
        layer.masksToBounds = false
        layer.shadowColor = UIColor(hex: "#24874A").cgColor
        layer.shadowOpacity = 0.24
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.shadowRadius = 16

        gradientLayer.colors = [
            UIColor(hex: "#48D49A").cgColor,
            UIColor(hex: "#1C9E72").cgColor
        ]
        gradientLayer.cornerRadius = 12
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradientLayer, at: 0)
    }

    private func configureContent() {
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 8
        contentStack.isUserInteractionEnabled = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true

        actionLabel.textColor = .white
        actionLabel.textAlignment = .center
        actionLabel.applyScaledFont(size: 17, weight: .bold, textStyle: .headline)
        actionLabel.adjustsFontSizeToFitWidth = true
        actionLabel.minimumScaleFactor = 0.82

        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(actionLabel)
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18)
        ])
    }

    func setContent(title: String, iconSystemName: String) {
        actionLabel.text = title
        iconView.image = UIImage(
            systemName: iconSystemName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        )
        accessibilityLabel = title
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
