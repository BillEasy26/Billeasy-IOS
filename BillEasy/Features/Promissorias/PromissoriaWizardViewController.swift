//
//  PromissoriaWizardViewController.swift
//  BillEasy
//

import UIKit

final class PromissoriaWizardViewController: UIViewController {

    // MARK: - Step

    private enum Step: Int, CaseIterable {
        case valorParcelas
        case vencimentoJuros
        case partes
        case revisao

        var title: String {
            switch self {
            case .valorParcelas: return "Valor e Parcelas"
            case .vencimentoJuros: return "Vencimento e Juros"
            case .partes: return "Partes"
            case .revisao: return "Revisão"
            }
        }

        var subtitle: String {
            switch self {
            case .valorParcelas: return "Defina o valor, a quantidade de parcelas e o método de pagamento."
            case .vencimentoJuros: return "Configure o primeiro vencimento e os percentuais de cobrança."
            case .partes: return "Informe os dados do emissor e do beneficiário da promissória."
            case .revisao: return "Confira os dados antes de criar a promissória."
            }
        }

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    // MARK: - Layout

    private enum Layout {
        static let horizontalMargin: CGFloat = 16
        static let sectionSpacing: CGFloat = 14
        static let cardCornerRadius: CGFloat = 16
    }

    // MARK: - Dependencies

    private let session: AuthSession
    private let service: PromissoriasService

    // MARK: - State

    private var currentStep: Step = .valorParcelas
    private var isSubmitting = false

    // MARK: - UI

    private let headerView = UIView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let footerView = UIView()
    private let backButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)

    private let valorField = UITextField()
    private let parcelasStepper = UIStepper()
    private let parcelasLabel = UILabel()
    private let metodoSegment = UISegmentedControl(items: ["PIX", "Boleto", "TED"])

    private let vencimentoPicker = UIDatePicker()
    private let jurosField = UITextField()
    private let multaField = UITextField()

    private let emissorNomeField = UITextField()
    private let emissorDocumentoField = UITextField()
    private let emissorEmailField = UITextField()
    private let emissorTelefoneField = UITextField()
    private let emissorCEPField = UITextField()
    private let emissorNumeroField = UITextField()
    private let emissorComplementoField = UITextField()

    private let beneficiarioNomeField = UITextField()
    private let beneficiarioDocumentoField = UITextField()
    private let beneficiarioEmailField = UITextField()
    private let beneficiarioTelefoneField = UITextField()
    private let beneficiarioCEPField = UITextField()
    private let beneficiarioNumeroField = UITextField()
    private let beneficiarioComplementoField = UITextField()
    private let beneficiarioChavePixField = UITextField()
    private let beneficiarioBancoField = UITextField()
    private let beneficiarioAgenciaField = UITextField()
    private let beneficiarioContaField = UITextField()
    private let beneficiarioTipoContaSegment = UISegmentedControl(items: ["Corrente", "Poupança"])

    // MARK: - Callbacks

    var onConcluido: (() -> Void)?
    var onCancelar: (() -> Void)?

    // MARK: - Init

    init(session: AuthSession, service: PromissoriasService = PromissoriasService()) {
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
        setupFields()
        renderStep()
    }

    // MARK: - Setup

    private func setupView() {
        view.backgroundColor = UIColor(hex: "#E6EAEE")

        setupHeader()
        setupScrollView()
        setupFooter()
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = UIColor(hex: "#E6EAEE")

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor(hex: "#2E87C8")
        closeButton.accessibilityLabel = "Cancelar"
        closeButton.addTarget(self, action: #selector(cancelarTapped), for: .touchUpInside)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Nova Promissória"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 24, weight: .bold, textStyle: .title1)
        titleLabel.accessibilityTraits = [.header]

        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.textColor = UIColor(hex: "#607188")
        progressLabel.textAlignment = .right
        progressLabel.applyScaledFont(size: 13, weight: .semibold, textStyle: .footnote)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = UIColor(hex: "#2E87C8")
        progressView.trackTintColor = UIColor(hex: "#C9D4E2")
        progressView.layer.cornerRadius = 2
        progressView.clipsToBounds = true

        view.addSubview(headerView)
        headerView.addSubview(closeButton)
        headerView.addSubview(titleLabel)
        headerView.addSubview(progressLabel)
        headerView.addSubview(progressView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 78),

            closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: Layout.horizontalMargin),
            closeButton.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: progressLabel.leadingAnchor, constant: -12),

            progressLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -Layout.horizontalMargin),
            progressLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            progressView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: Layout.horizontalMargin),
            progressView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -Layout.horizontalMargin),
            progressView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -12),
            progressView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = Layout.sectionSpacing
        stack.layoutMargins = UIEdgeInsets(top: 16, left: Layout.horizontalMargin, bottom: 24, right: Layout.horizontalMargin)
        stack.isLayoutMarginsRelativeArrangement = true

        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func setupFooter() {
        footerView.translatesAutoresizingMaskIntoConstraints = false
        footerView.backgroundColor = UIColor(hex: "#E6EAEE")
        view.addSubview(footerView)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        footerView.addSubview(backButton)
        footerView.addSubview(nextButton)

        NSLayoutConstraint.activate([
            footerView.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 82),

            backButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: Layout.horizontalMargin),
            backButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            backButton.heightAnchor.constraint(equalToConstant: 52),
            backButton.widthAnchor.constraint(equalToConstant: 112),

            nextButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 12),
            nextButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -Layout.horizontalMargin),
            nextButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            nextButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func setupFields() {
        configureField(valorField, placeholder: "R$ 0,00", keyboard: .numberPad)
        configureField(jurosField, placeholder: "0,00", keyboard: .decimalPad)
        configureField(multaField, placeholder: "0,00", keyboard: .decimalPad)

        configurePartyFields(
            nome: emissorNomeField,
            documento: emissorDocumentoField,
            email: emissorEmailField,
            telefone: emissorTelefoneField,
            cep: emissorCEPField,
            numero: emissorNumeroField,
            complemento: emissorComplementoField
        )
        configurePartyFields(
            nome: beneficiarioNomeField,
            documento: beneficiarioDocumentoField,
            email: beneficiarioEmailField,
            telefone: beneficiarioTelefoneField,
            cep: beneficiarioCEPField,
            numero: beneficiarioNumeroField,
            complemento: beneficiarioComplementoField
        )
        configureField(beneficiarioChavePixField, placeholder: "CPF, e-mail, telefone ou chave aleatória", keyboard: .default)
        configureField(beneficiarioBancoField, placeholder: "Banco", keyboard: .default)
        configureField(beneficiarioAgenciaField, placeholder: "Agência", keyboard: .numberPad)
        configureField(beneficiarioContaField, placeholder: "Conta", keyboard: .numberPad)

        parcelasStepper.minimumValue = 1
        parcelasStepper.maximumValue = 60
        parcelasStepper.value = 1
        parcelasStepper.stepValue = 1
        parcelasStepper.addTarget(self, action: #selector(parcelasChanged), for: .valueChanged)
        parcelasLabel.textColor = UIColor(hex: "#252E3A")
        parcelasLabel.applyScaledFont(size: 20, weight: .bold, textStyle: .title3)
        updateParcelasLabel()

        metodoSegment.selectedSegmentIndex = 0
        metodoSegment.selectedSegmentTintColor = UIColor(hex: "#2E87C8")
        metodoSegment.setTitleTextAttributes([.foregroundColor: UIColor(hex: "#FFFFFF")], for: .selected)
        metodoSegment.setTitleTextAttributes([.foregroundColor: UIColor(hex: "#2E87C8")], for: .normal)

        vencimentoPicker.datePickerMode = .date
        vencimentoPicker.preferredDatePickerStyle = .inline
        vencimentoPicker.minimumDate = Calendar.current.startOfDay(for: Date())

        beneficiarioTipoContaSegment.selectedSegmentIndex = 0
        beneficiarioTipoContaSegment.selectedSegmentTintColor = UIColor(hex: "#2E87C8")
        beneficiarioTipoContaSegment.setTitleTextAttributes([.foregroundColor: UIColor(hex: "#FFFFFF")], for: .selected)
        beneficiarioTipoContaSegment.setTitleTextAttributes([.foregroundColor: UIColor(hex: "#2E87C8")], for: .normal)

        emissorNomeField.text = session.displayName
        emissorEmailField.text = session.email
        emissorTelefoneField.text = session.phone.map(formatPhone)
    }

    private func configurePartyFields(
        nome: UITextField,
        documento: UITextField,
        email: UITextField,
        telefone: UITextField,
        cep: UITextField,
        numero: UITextField,
        complemento: UITextField
    ) {
        configureField(nome, placeholder: "Nome completo", keyboard: .default)
        configureField(documento, placeholder: "CPF ou CNPJ", keyboard: .numberPad)
        configureField(email, placeholder: "email@exemplo.com", keyboard: .emailAddress)
        configureField(telefone, placeholder: "(00) 00000-0000", keyboard: .phonePad)
        configureField(cep, placeholder: "00000-000", keyboard: .numberPad)
        configureField(numero, placeholder: "Número", keyboard: .numbersAndPunctuation)
        configureField(complemento, placeholder: "Complemento opcional", keyboard: .default)
    }

    private func configureField(_ field: UITextField, placeholder: String, keyboard: UIKeyboardType) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = placeholder
        field.keyboardType = keyboard
        field.autocorrectionType = .no
        field.autocapitalizationType = keyboard == .emailAddress ? .none : .words
        field.clearButtonMode = .whileEditing
        field.backgroundColor = UIColor(hex: "#FFFFFF")
        field.textColor = UIColor(hex: "#243142")
        field.tintColor = UIColor(hex: "#2E87C8")
        field.layer.cornerRadius = 12
        field.layer.cornerCurve = .continuous
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.rightViewMode = .always
        field.applyScaledFont(size: 16, weight: .medium, textStyle: .body)
        field.delegate = self
        field.addTarget(self, action: #selector(textFieldEditingChanged(_:)), for: .editingChanged)
        field.heightAnchor.constraint(equalToConstant: 50).isActive = true
    }

    // MARK: - Rendering

    private func renderStep() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let stepIndex = currentStep.rawValue + 1
        progressLabel.text = "\(stepIndex)/\(Step.allCases.count)"
        progressView.setProgress(Float(stepIndex) / Float(Step.allCases.count), animated: true)

        stack.addArrangedSubview(makeIntroCard(title: currentStep.title, subtitle: currentStep.subtitle))

        switch currentStep {
        case .valorParcelas:
            stack.addArrangedSubview(makeValorParcelasCard())
        case .vencimentoJuros:
            stack.addArrangedSubview(makeVencimentoJurosCard())
        case .partes:
            stack.addArrangedSubview(makePartesCard())
        case .revisao:
            stack.addArrangedSubview(makeResumoCard())
        }

        refreshFooter()
        scrollView.setContentOffset(.zero, animated: false)
    }

    private func refreshFooter() {
        backButton.isHidden = currentStep == .valorParcelas

        var backConfiguration = UIButton.Configuration.tinted()
        backConfiguration.cornerStyle = .capsule
        backConfiguration.baseBackgroundColor = UIColor(hex: "#DCE8F3")
        backConfiguration.baseForegroundColor = UIColor(hex: "#2E87C8")
        backConfiguration.title = "Voltar"
        backConfiguration.image = UIImage(systemName: "chevron.left")
        backConfiguration.imagePadding = 6
        backButton.configuration = backConfiguration

        var nextConfiguration = UIButton.Configuration.filled()
        nextConfiguration.cornerStyle = .capsule
        nextConfiguration.baseBackgroundColor = UIColor(hex: "#2E87C8")
        nextConfiguration.baseForegroundColor = UIColor(hex: "#FFFFFF")
        nextConfiguration.title = isSubmitting
            ? "Criando…"
            : (currentStep == .revisao ? "Criar Promissória" : "Continuar")
        nextConfiguration.image = currentStep == .revisao
            ? UIImage(systemName: "checkmark.circle.fill")
            : UIImage(systemName: "chevron.right")
        nextConfiguration.imagePlacement = .trailing
        nextConfiguration.imagePadding = 8
        nextButton.configuration = nextConfiguration

        backButton.isEnabled = !isSubmitting
        nextButton.isEnabled = !isSubmitting
        closeButton.isEnabled = !isSubmitting
    }

    // MARK: - Cards

    private func makeIntroCard(title: String, subtitle: String) -> UIView {
        let card = makeCard(background: UIColor(hex: "#122B46"), border: UIColor(hex: "#122B46"))

        let titleLabel = makeLabel(title, color: UIColor(hex: "#F8FBFF"), size: 24, weight: .bold, textStyle: .title2)
        let subtitleLabel = makeLabel(subtitle, color: UIColor(hex: "#D7E4F1"), size: 14, weight: .medium, textStyle: .body)

        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        return card
    }

    private func makeValorParcelasCard() -> UIView {
        let card = makeCard()
        let form = makeFormStack()

        form.addArrangedSubview(makeFieldBlock(title: "Valor total", field: valorField))

        let parcelasContainer = UIView()
        parcelasContainer.translatesAutoresizingMaskIntoConstraints = false
        let parcelasTitle = makeLabel("Quantidade de parcelas", color: UIColor(hex: "#607188"), size: 13, weight: .bold, textStyle: .caption1)
        parcelasStepper.translatesAutoresizingMaskIntoConstraints = false
        parcelasLabel.translatesAutoresizingMaskIntoConstraints = false

        parcelasContainer.addSubview(parcelasTitle)
        parcelasContainer.addSubview(parcelasLabel)
        parcelasContainer.addSubview(parcelasStepper)

        NSLayoutConstraint.activate([
            parcelasTitle.topAnchor.constraint(equalTo: parcelasContainer.topAnchor),
            parcelasTitle.leadingAnchor.constraint(equalTo: parcelasContainer.leadingAnchor),
            parcelasTitle.trailingAnchor.constraint(equalTo: parcelasContainer.trailingAnchor),

            parcelasLabel.topAnchor.constraint(equalTo: parcelasTitle.bottomAnchor, constant: 10),
            parcelasLabel.leadingAnchor.constraint(equalTo: parcelasContainer.leadingAnchor),
            parcelasLabel.centerYAnchor.constraint(equalTo: parcelasStepper.centerYAnchor),

            parcelasStepper.topAnchor.constraint(equalTo: parcelasTitle.bottomAnchor, constant: 8),
            parcelasStepper.trailingAnchor.constraint(equalTo: parcelasContainer.trailingAnchor),
            parcelasStepper.bottomAnchor.constraint(equalTo: parcelasContainer.bottomAnchor)
        ])
        form.addArrangedSubview(parcelasContainer)

        form.addArrangedSubview(makeSegmentBlock(title: "Método de pagamento", segment: metodoSegment))
        addForm(form, to: card)
        return card
    }

    private func makeVencimentoJurosCard() -> UIView {
        let card = makeCard()
        let form = makeFormStack()

        let vencimentoBlock = UIStackView()
        vencimentoBlock.translatesAutoresizingMaskIntoConstraints = false
        vencimentoBlock.axis = .vertical
        vencimentoBlock.spacing = 8
        vencimentoBlock.addArrangedSubview(makeLabel("Primeiro vencimento", color: UIColor(hex: "#607188"), size: 13, weight: .bold, textStyle: .caption1))
        vencimentoPicker.translatesAutoresizingMaskIntoConstraints = false
        vencimentoBlock.addArrangedSubview(vencimentoPicker)

        form.addArrangedSubview(vencimentoBlock)
        form.addArrangedSubview(makeFieldBlock(title: "Juros mensais (%)", field: jurosField))
        form.addArrangedSubview(makeFieldBlock(title: "Multa por atraso (%)", field: multaField))

        addForm(form, to: card)
        return card
    }

    private func makePartesCard() -> UIView {
        let card = makeCard()
        let form = makeFormStack(spacing: 16)

        form.addArrangedSubview(makeSectionTitle("Emissor"))
        form.addArrangedSubview(makeFieldBlock(title: "Nome", field: emissorNomeField))
        form.addArrangedSubview(makeFieldBlock(title: "CPF/CNPJ", field: emissorDocumentoField))
        form.addArrangedSubview(makeFieldBlock(title: "E-mail", field: emissorEmailField))
        form.addArrangedSubview(makeFieldBlock(title: "Telefone", field: emissorTelefoneField))
        form.addArrangedSubview(makeTwoColumnFields(
            leftTitle: "CEP",
            leftField: emissorCEPField,
            rightTitle: "Número",
            rightField: emissorNumeroField
        ))
        form.addArrangedSubview(makeFieldBlock(title: "Complemento", field: emissorComplementoField))

        form.addArrangedSubview(makeSeparator())
        form.addArrangedSubview(makeSectionTitle("Beneficiário"))
        form.addArrangedSubview(makeFieldBlock(title: "Nome", field: beneficiarioNomeField))
        form.addArrangedSubview(makeFieldBlock(title: "CPF/CNPJ", field: beneficiarioDocumentoField))
        form.addArrangedSubview(makeFieldBlock(title: "E-mail", field: beneficiarioEmailField))
        form.addArrangedSubview(makeFieldBlock(title: "Telefone", field: beneficiarioTelefoneField))
        form.addArrangedSubview(makeTwoColumnFields(
            leftTitle: "CEP",
            leftField: beneficiarioCEPField,
            rightTitle: "Número",
            rightField: beneficiarioNumeroField
        ))
        form.addArrangedSubview(makeFieldBlock(title: "Complemento", field: beneficiarioComplementoField))
        form.addArrangedSubview(makeFieldBlock(title: "Chave PIX", field: beneficiarioChavePixField))
        form.addArrangedSubview(makeTwoColumnFields(
            leftTitle: "Banco",
            leftField: beneficiarioBancoField,
            rightTitle: "Agência",
            rightField: beneficiarioAgenciaField
        ))
        form.addArrangedSubview(makeFieldBlock(title: "Conta", field: beneficiarioContaField))
        form.addArrangedSubview(makeSegmentBlock(title: "Tipo de conta", segment: beneficiarioTipoContaSegment))

        addForm(form, to: card)
        return card
    }

    private func makeResumoCard() -> UIView {
        let card = makeCard()
        let form = makeFormStack(spacing: 12)

        form.addArrangedSubview(makeSectionTitle("Resumo"))
        form.addArrangedSubview(makeSummaryRow(title: "Valor", value: Formatters.currencyText(from: valorDecimal)))
        form.addArrangedSubview(makeSummaryRow(title: "Parcelas", value: "\(Int(parcelasStepper.value))x"))
        form.addArrangedSubview(makeSummaryRow(title: "Pagamento", value: metodoPagamentoDisplay))
        form.addArrangedSubview(makeSummaryRow(title: "Primeiro vencimento", value: Formatters.shortDate.string(from: vencimentoPicker.date)))
        form.addArrangedSubview(makeSummaryRow(title: "Juros", value: "\(plainDecimalText(jurosField.text))% ao mês"))
        form.addArrangedSubview(makeSummaryRow(title: "Multa", value: "\(plainDecimalText(multaField.text))%"))

        form.addArrangedSubview(makeSeparator())
        form.addArrangedSubview(makeSummaryRow(title: "Emissor", value: requiredText(emissorNomeField)))
        form.addArrangedSubview(makeSummaryRow(title: "Documento", value: requiredText(emissorDocumentoField)))
        form.addArrangedSubview(makeSummaryRow(title: "Beneficiário", value: requiredText(beneficiarioNomeField)))
        form.addArrangedSubview(makeSummaryRow(title: "Documento", value: requiredText(beneficiarioDocumentoField)))

        addForm(form, to: card)
        return card
    }

    // MARK: - Helpers

    private func makeCard(
        background: UIColor = UIColor(hex: "#F8FBFF"),
        border: UIColor = UIColor(hex: "#D7DEE8")
    ) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = background
        card.layer.cornerRadius = Layout.cardCornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = border.cgColor
        return card
    }

    private func makeFormStack(spacing: CGFloat = 14) -> UIStackView {
        let form = UIStackView()
        form.translatesAutoresizingMaskIntoConstraints = false
        form.axis = .vertical
        form.spacing = spacing
        return form
    }

    private func addForm(_ form: UIStackView, to card: UIView) {
        card.addSubview(form)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            form.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            form.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            form.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
    }

    private func makeFieldBlock(title: String, field: UITextField) -> UIView {
        let block = UIStackView()
        block.translatesAutoresizingMaskIntoConstraints = false
        block.axis = .vertical
        block.spacing = 7
        block.addArrangedSubview(makeLabel(title, color: UIColor(hex: "#607188"), size: 13, weight: .bold, textStyle: .caption1))
        block.addArrangedSubview(field)
        return block
    }

    private func makeSegmentBlock(title: String, segment: UISegmentedControl) -> UIView {
        let block = UIStackView()
        block.translatesAutoresizingMaskIntoConstraints = false
        block.axis = .vertical
        block.spacing = 8
        block.addArrangedSubview(makeLabel(title, color: UIColor(hex: "#607188"), size: 13, weight: .bold, textStyle: .caption1))
        segment.translatesAutoresizingMaskIntoConstraints = false
        block.addArrangedSubview(segment)
        segment.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return block
    }

    private func makeTwoColumnFields(
        leftTitle: String,
        leftField: UITextField,
        rightTitle: String,
        rightField: UITextField
    ) -> UIView {
        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually
        row.addArrangedSubview(makeFieldBlock(title: leftTitle, field: leftField))
        row.addArrangedSubview(makeFieldBlock(title: rightTitle, field: rightField))
        return row
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        makeLabel(text, color: UIColor(hex: "#252E3A"), size: 18, weight: .bold, textStyle: .headline)
    }

    private func makeSummaryRow(title: String, value: String) -> UIView {
        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12

        let titleLabel = makeLabel(title, color: UIColor(hex: "#607188"), size: 13, weight: .semibold, textStyle: .footnote)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let valueLabel = makeLabel(value, color: UIColor(hex: "#253244"), size: 15, weight: .bold, textStyle: .body)
        valueLabel.textAlignment = .right

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func makeSeparator() -> UIView {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor(hex: "#E2E8F0")
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func makeLabel(
        _ text: String,
        color: UIColor,
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle
    ) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = color
        label.numberOfLines = 0
        label.applyScaledFont(size: size, weight: weight, textStyle: textStyle)
        return label
    }

    // MARK: - Validation and payload

    private var valorDecimal: Decimal {
        Formatters.decimalFromCurrencyInput(valorField.text ?? "")
    }

    private var metodoPagamento: String {
        switch metodoSegment.selectedSegmentIndex {
        case 0: return "PIX"
        case 1: return "BOLETO"
        default: return "TED"
        }
    }

    private var metodoPagamentoDisplay: String {
        switch metodoPagamento {
        case "PIX": return "Pix"
        case "BOLETO": return "Boleto"
        default: return "TED"
        }
    }

    private func validateCurrentStep() -> Bool {
        view.endEditing(true)
        switch currentStep {
        case .valorParcelas:
            guard valorDecimal > .zero else {
                showSimpleToast("Informe um valor maior que zero.", style: .error)
                return false
            }
            return true

        case .vencimentoJuros:
            guard vencimentoPicker.date >= Calendar.current.startOfDay(for: Date()) else {
                showSimpleToast("Selecione um vencimento válido.", style: .error)
                return false
            }
            guard decimalFromPlainInput(jurosField.text) >= .zero, decimalFromPlainInput(multaField.text) >= .zero else {
                showSimpleToast("Informe percentuais válidos.", style: .error)
                return false
            }
            return true

        case .partes:
            return validateParty(prefix: "emissor", fields: partyFields(for: .emissor))
                && validateParty(prefix: "beneficiário", fields: partyFields(for: .beneficiario))
                && validatePaymentFieldsIfNeeded()

        case .revisao:
            return true
        }
    }

    private enum PartyKind {
        case emissor
        case beneficiario
    }

    private typealias PartyFields = (
        nome: UITextField,
        documento: UITextField,
        email: UITextField,
        telefone: UITextField,
        cep: UITextField,
        numero: UITextField,
        complemento: UITextField
    )

    private func partyFields(for kind: PartyKind) -> PartyFields {
        switch kind {
        case .emissor:
            return (emissorNomeField, emissorDocumentoField, emissorEmailField, emissorTelefoneField, emissorCEPField, emissorNumeroField, emissorComplementoField)
        case .beneficiario:
            return (beneficiarioNomeField, beneficiarioDocumentoField, beneficiarioEmailField, beneficiarioTelefoneField, beneficiarioCEPField, beneficiarioNumeroField, beneficiarioComplementoField)
        }
    }

    private func validateParty(prefix: String, fields: PartyFields) -> Bool {
        guard requiredText(fields.nome).isEmpty == false else {
            showSimpleToast("Informe o nome do \(prefix).", style: .error)
            return false
        }

        let documentDigits = Formatters.digitsOnly(requiredText(fields.documento))
        guard documentDigits.count == 11 || documentDigits.count == 14 else {
            showSimpleToast("Informe um CPF/CNPJ válido para o \(prefix).", style: .error)
            return false
        }

        guard isValidEmail(requiredText(fields.email)) else {
            showSimpleToast("Informe um e-mail válido para o \(prefix).", style: .error)
            return false
        }

        guard Formatters.digitsOnly(requiredText(fields.telefone)).count >= 10 else {
            showSimpleToast("Informe um telefone válido para o \(prefix).", style: .error)
            return false
        }

        guard Formatters.digitsOnly(requiredText(fields.cep)).count == 8 else {
            showSimpleToast("Informe um CEP válido para o \(prefix).", style: .error)
            return false
        }

        guard requiredText(fields.numero).isEmpty == false else {
            showSimpleToast("Informe o número do endereço do \(prefix).", style: .error)
            return false
        }

        return true
    }

    private func validatePaymentFieldsIfNeeded() -> Bool {
        if metodoPagamento == "PIX", requiredText(beneficiarioChavePixField).isEmpty {
            showSimpleToast("Informe a chave PIX do beneficiário.", style: .error)
            return false
        }

        if metodoPagamento == "TED" {
            guard requiredText(beneficiarioBancoField).isEmpty == false,
                  requiredText(beneficiarioAgenciaField).isEmpty == false,
                  requiredText(beneficiarioContaField).isEmpty == false
            else {
                showSimpleToast("Informe banco, agência e conta do beneficiário.", style: .error)
                return false
            }
        }

        return true
    }

    private func buildInput() -> CriarPromissoriaInput {
        CriarPromissoriaInput(
            valorMontante: valorDecimal,
            metodoPagamento: metodoPagamento,
            quantidadeParcelas: Int(parcelasStepper.value),
            primeiroVencimento: vencimentoPicker.date,
            jurosMensalPercent: decimalFromPlainInput(jurosField.text),
            multaAtrasoPercent: decimalFromPlainInput(multaField.text),
            emissor: buildParteInput(fields: partyFields(for: .emissor), includePaymentFields: false),
            beneficiario: buildParteInput(fields: partyFields(for: .beneficiario), includePaymentFields: true)
        )
    }

    private func buildParteInput(fields: PartyFields, includePaymentFields: Bool) -> PromissoriaParteInput {
        PromissoriaParteInput(
            nome: requiredText(fields.nome),
            documento: requiredText(fields.documento),
            email: requiredText(fields.email),
            telefone: requiredText(fields.telefone),
            cep: requiredText(fields.cep),
            numero: requiredText(fields.numero),
            complemento: optionalText(fields.complemento),
            chavePix: includePaymentFields ? optionalText(beneficiarioChavePixField) : nil,
            banco: includePaymentFields ? optionalText(beneficiarioBancoField) : nil,
            agencia: includePaymentFields ? optionalText(beneficiarioAgenciaField) : nil,
            conta: includePaymentFields ? optionalText(beneficiarioContaField) : nil,
            tipoConta: includePaymentFields ? tipoContaSelecionado : nil
        )
    }

    private var tipoContaSelecionado: String {
        beneficiarioTipoContaSegment.selectedSegmentIndex == 1 ? "POUPANCA" : "CORRENTE"
    }

    private func requiredText(_ field: UITextField) -> String {
        (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optionalText(_ field: UITextField) -> String? {
        let value = requiredText(field)
        return value.isEmpty ? nil : value
    }

    private func isValidEmail(_ value: String) -> Bool {
        value.contains("@") && value.contains(".") && value.count >= 5
    }

    private func decimalFromPlainInput(_ value: String?) -> Decimal {
        let normalized = (value ?? "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: normalized) ?? .zero
    }

    private func plainDecimalText(_ value: String?) -> String {
        let decimal = decimalFromPlainInput(value)
        return NSDecimalNumber(decimal: decimal).stringValue.replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Actions

    @objc private func cancelarTapped() {
        onCancelar?()
    }

    @objc private func backTapped() {
        guard let previous = currentStep.previous else { return }
        currentStep = previous
        renderStep()
    }

    @objc private func nextTapped() {
        guard validateCurrentStep() else { return }

        if currentStep == .revisao {
            criarPromissoria()
            return
        }

        if let next = currentStep.next {
            currentStep = next
            renderStep()
        }
    }

    @objc private func parcelasChanged() {
        updateParcelasLabel()
    }

    @objc private func textFieldEditingChanged(_ textField: UITextField) {
        switch textField {
        case valorField:
            textField.text = Formatters.formatCurrencyInput(textField.text ?? "")
        case emissorDocumentoField, beneficiarioDocumentoField:
            textField.text = Formatters.formatCPFOrCNPJ(textField.text ?? "")
        case emissorCEPField, beneficiarioCEPField:
            textField.text = Formatters.formatCEP(textField.text ?? "")
        case emissorTelefoneField, beneficiarioTelefoneField:
            textField.text = formatPhone(textField.text ?? "")
        default:
            break
        }
    }

    private func criarPromissoria() {
        guard !isSubmitting else { return }
        isSubmitting = true
        refreshFooter()

        let input = buildInput()
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.service.criar(input: input)
                await MainActor.run {
                    self.isSubmitting = false
                    self.refreshFooter()
                    self.showSimpleToast("Promissória criada com sucesso.", style: .success)
                    self.onConcluido?()
                }
            } catch {
                await MainActor.run {
                    self.isSubmitting = false
                    self.refreshFooter()
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    private func updateParcelasLabel() {
        let value = Int(parcelasStepper.value)
        parcelasLabel.text = value == 1 ? "1 parcela" : "\(value) parcelas"
    }

    private func formatPhone(_ value: String) -> String {
        let digits = String(Formatters.digitsOnly(value).prefix(11))
        guard digits.isEmpty == false else { return "" }

        var result = ""
        for (index, character) in digits.enumerated() {
            switch index {
            case 0: result.append("(")
            case 2: result.append(") ")
            case 7 where digits.count > 10: result.append("-")
            case 6 where digits.count <= 10: result.append("-")
            default: break
            }
            result.append(character)
        }
        return result
    }
}

// MARK: - UITextFieldDelegate

extension PromissoriaWizardViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
