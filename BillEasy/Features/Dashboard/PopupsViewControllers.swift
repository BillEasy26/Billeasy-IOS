//
//  PopupsViewControllers.swift
//  BillEasy
//

import UIKit

private enum PopupLayout {
    static let cardCornerRadius: CGFloat = 18
    static let cardInset: CGFloat = 16
    static let compactInset: CGFloat = 14
    static let closeButtonSize: CGFloat = 28
    static let primaryButtonHeight: CGFloat = 44
}

/// Aqui eu concentro o comportamento visual base de qualquer popup modal do app.
class BasePopupViewController: UIViewController {
    let dimmingControl = UIControl()
    let popupCard = UIView()
    private let cardWidth: CGFloat

    init(cardWidth: CGFloat = 360) {
        self.cardWidth = cardWidth
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        dimmingControl.translatesAutoresizingMaskIntoConstraints = false
        dimmingControl.backgroundColor = UIColor.black.withAlphaComponent(0.46)
        dimmingControl.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        popupCard.translatesAutoresizingMaskIntoConstraints = false
        popupCard.backgroundColor = UIColor(hex: "#F9FBFD")
        popupCard.layer.cornerRadius = PopupLayout.cardCornerRadius
        popupCard.layer.cornerCurve = .continuous
        popupCard.layer.masksToBounds = true
        popupCard.layer.borderWidth = 1
        popupCard.layer.borderColor = UIColor(hex: "#E1E6EF").cgColor

        view.addSubview(dimmingControl)
        view.addSubview(popupCard)

        let preferredWidth = popupCard.widthAnchor.constraint(equalToConstant: cardWidth)
        preferredWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            dimmingControl.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingControl.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            popupCard.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            popupCard.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            popupCard.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            popupCard.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            popupCard.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            popupCard.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            popupCard.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
            preferredWidth
        ])
    }

    /// Aqui eu gero o botao de fechar padrao para os popups que usam o mesmo comportamento.
    func makeCloseButton(tintColor: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = tintColor
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }

    @objc func closeTapped() {
        dismiss(animated: true)
    }
}

/// Aqui eu represento os contratos e etapas de assinatura com variacoes do mesmo modal base.
final class ContractDigitalPopupViewController: BasePopupViewController {
    enum Mode {
        case creditorActions
        case govBrCreditor
        case debtorActions
        case govBrDebtor
    }

    var onDownload: (() -> Void)?
    var onProtest: (() -> Void)?
    var onSignAsCreditor: (() -> Void)?
    var onSignAsDebtor: (() -> Void)?
    var onDraw: (() -> Void)?
    var onGovBr: (() -> Void)?

    private let mode: Mode
    private let titleText: String
    private let subtitleText: String
    private var resolvedContractText: String?
    private weak var contractTextLabel: UILabel?

    init(
        mode: Mode,
        titleText: String = "Contrato Digital",
        subtitleText: String = "Validado via IA & Assinatura Eletrônica",
        contractTextOverride: String? = nil
    ) {
        self.mode = mode
        self.titleText = titleText
        self.subtitleText = subtitleText
        self.resolvedContractText = contractTextOverride
        super.init(cardWidth: 356)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
    }

    /// Aqui eu monto o popup completo do contrato digital com header, texto e acoes conforme o modo.
    private func setupContent() {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = UIColor(hex: "#163C8F")

        let iconBackground = UIView()
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        iconBackground.layer.cornerRadius = 16
        iconBackground.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: mode == .creditorActions ? "doc.text" : "shield"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .white

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = titleText
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "◉  \(subtitleText)"
        subtitleLabel.textColor = UIColor(hex: "#D8E6FF")
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let closeButton = makeCloseButton(tintColor: .white)

        popupCard.addSubview(header)
        header.addSubview(iconBackground)
        iconBackground.addSubview(icon)
        header.addSubview(titleLabel)
        header.addSubview(subtitleLabel)
        header.addSubview(closeButton)

        let bodyContainer = UIView()
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.backgroundColor = UIColor(hex: "#F9FBFD")
        popupCard.addSubview(bodyContainer)

        let textContainer = UIView()
        textContainer.translatesAutoresizingMaskIntoConstraints = false
        textContainer.backgroundColor = UIColor(hex: "#FBFCFE")
        textContainer.layer.cornerRadius = 14
        textContainer.layer.cornerCurve = .continuous
        textContainer.layer.borderWidth = 1
        textContainer.layer.borderColor = UIColor(hex: "#D8E1ED").cgColor

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let text = UILabel()
        text.translatesAutoresizingMaskIntoConstraints = false
        text.numberOfLines = 0
        text.textColor = UIColor(hex: "#2F3946")
        text.font = .systemFont(ofSize: 14, weight: .regular)
        text.text = contractText
        contractTextLabel = text

        bodyContainer.addSubview(textContainer)
        textContainer.addSubview(scrollView)
        scrollView.addSubview(text)

        let actions = makeFooterActions()
        actions.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(actions)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: popupCard.topAnchor),
            header.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 94),

            iconBackground.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: PopupLayout.compactInset),
            iconBackground.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 40),
            iconBackground.heightAnchor.constraint(equalToConstant: 40),

            icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 16),

            subtitleLabel.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 10),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -PopupLayout.compactInset),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: PopupLayout.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: PopupLayout.closeButtonSize),

            bodyContainer.topAnchor.constraint(equalTo: header.bottomAnchor),
            bodyContainer.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor),
            bodyContainer.bottomAnchor.constraint(equalTo: popupCard.bottomAnchor),

            textContainer.topAnchor.constraint(equalTo: bodyContainer.topAnchor, constant: PopupLayout.cardInset),
            textContainer.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: PopupLayout.cardInset),
            textContainer.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -PopupLayout.cardInset),
            {
                let preferred = textContainer.heightAnchor.constraint(equalToConstant: 372)
                preferred.priority = .defaultHigh
                return preferred
            }(),
            textContainer.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.42),
            textContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),

            scrollView.topAnchor.constraint(equalTo: textContainer.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor, constant: -12),

            text.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            text.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            text.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            text.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            actions.topAnchor.constraint(equalTo: textContainer.bottomAnchor, constant: 12),
            actions.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: PopupLayout.cardInset),
            actions.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -PopupLayout.cardInset),
            actions.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -PopupLayout.cardInset)
        ])
    }

    /// Aqui eu escolho o texto contratual padrao quando a tela nao recebe uma versao customizada.
    var currentContractText: String {
        contractText
    }

    /// Aqui eu permito que a controller injete o texto remoto depois que o modal já estiver visível.
    func updateContractText(_ newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        resolvedContractText = trimmed
        contractTextLabel?.text = trimmed
    }

    /// Aqui eu escolho o texto contratual padrao quando a tela nao recebe uma versao customizada.
    private var contractText: String {
        if let resolvedContractText, !resolvedContractText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return resolvedContractText
        }

        switch mode {
        case .creditorActions, .govBrCreditor:
            return "CONTRATO DE RECONHECIMENTO DE DÍVIDA\n\nPelo presente instrumento particular, as partes abaixo qualificadas têm entre si justo e contratado o seguinte:\n\nCLÁUSULA 1ª - DO OBJETO\nO presente contrato tem por objeto o reconhecimento de dívida referente ao título selecionado nesta cobrança.\n\nCLÁUSULA 2ª - DO VENCIMENTO\nA dívida terá vencimento conforme a data cadastrada no aplicativo.\n\nCLÁUSULA 3ª - DA FORMA DE PAGAMENTO\nO pagamento será realizado conforme condições aprovadas entre as partes.\n\nCLÁUSULA 4ª - DA MULTA E JURO\nEm caso de atraso, poderão incidir multa e juros nos termos legais.\n\nDocumento gerado por IA e validado eletronicamente via BillEasy.ia."
        case .debtorActions, .govBrDebtor:
            return "INSTRUMENTO PARTICULAR DE CONFISSÃO DE DÍVIDA E OUTRAS AVENÇAS\n\nPelo presente INSTRUMENTO PARTICULAR DE CONFISSÃO DE DÍVIDA, de um lado:\n\nCREDORA\n[NOME DA CREDORA], pessoa jurídica de direito privado, inscrita no CNPJ/MF sob o nº [CNPJ], com sede em [ENDEREÇO COMPLETO], doravante denominada simplesmente CREDORA.\n\nE, de outro lado:\n\nDEVEDOR\n[NOME DO DEVEDOR], [ESTADO CIVIL], [PROFISSÃO], inscrito no CPF nº [CPF].\n\nAs partes reconhecem os dados da dívida selecionada no aplicativo e concordam com as condições descritas neste instrumento."
        }
    }

    /// Aqui eu exponho apenas as acoes relevantes para cada fase do fluxo contratual.
    private func makeFooterActions() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 10

        switch mode {
        case .creditorActions:
            let downloadButton = makeTextActionButton(title: "Abrir contrato", icon: "arrow.down.to.line") { [weak self] in
                self?.onDownload?()
            }
            let protestButton = makeFilledButton(title: "Protestar (Serasa)", color: UIColor(hex: "#E74C3C"), icon: "shield") { [weak self] in
                self?.onProtest?()
            }
            let signButton = makeFilledButton(title: "Assinar como Credor", color: UIColor(hex: "#163C8F"), icon: "shield") { [weak self] in
                self?.onSignAsCreditor?()
            }
            container.addArrangedSubview(downloadButton)
            container.addArrangedSubview(protestButton)
            container.addArrangedSubview(signButton)

        case .govBrCreditor, .govBrDebtor:
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually

            let drawButton = makeOutlineButton(title: "Desenhar", icon: "pencil") { [weak self] in
                self?.onDraw?()
            }
            let govButton = makeFilledButton(title: "Assinar gov.br", color: UIColor(hex: "#163C8F"), icon: "g.circle") { [weak self] in
                self?.onGovBr?()
            }

            row.addArrangedSubview(drawButton)
            row.addArrangedSubview(govButton)
            container.addArrangedSubview(row)

        case .debtorActions:
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually

            let downloadButton = makeOutlineButton(title: "Abrir contrato", icon: "arrow.down.to.line") { [weak self] in
                self?.onDownload?()
            }
            let signDebtorButton = makeFilledButton(title: "Assinar como Devedor", color: UIColor(hex: "#2CBF85"), icon: "shield") { [weak self] in
                self?.onSignAsDebtor?()
            }
            row.addArrangedSubview(downloadButton)
            row.addArrangedSubview(signDebtorButton)
            container.addArrangedSubview(row)
        }

        return container
    }

    /// Aqui eu padronizo o CTA preenchido usado nas decisoes principais do popup.
    private func makeFilledButton(title: String, color: UIColor, icon: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("  \(title)", for: .normal)
        button.setImage(UIImage(systemName: icon), for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        button.backgroundColor = color
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        button.heightAnchor.constraint(equalToConstant: PopupLayout.primaryButtonHeight).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    /// Aqui eu padronizo o CTA outline usado em acoes de apoio ou dupla escolha.
    private func makeOutlineButton(title: String, icon: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("  \(title)", for: .normal)
        button.setImage(UIImage(systemName: icon), for: .normal)
        button.tintColor = UIColor(hex: "#2B3442")
        button.setTitleColor(UIColor(hex: "#2B3442"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        button.backgroundColor = UIColor(hex: "#FDFEFF")
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        button.heightAnchor.constraint(equalToConstant: PopupLayout.primaryButtonHeight).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    /// Aqui eu mantenho a acao textual simples para comandos menos prioritarios como abrir um contrato ja existente.
    private func makeTextActionButton(title: String, icon: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("  \(title)", for: .normal)
        button.setImage(UIImage(systemName: icon), for: .normal)
        button.tintColor = UIColor(hex: "#6A7A91")
        button.setTitleColor(UIColor(hex: "#6A7A91"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}

/// Aqui eu simulo a confirmacao de negativacao do Serasa em um fluxo isolado e objetivo.
final class SerasaPopupViewController: BasePopupViewController {
    var onConfirmNegativation: (() -> Void)?
    private let debtTitle: String
    private let amountText: String
    private let documentText: String
    private let overdueText: String
    private weak var debtValueLabel: UILabel?
    private weak var amountValueLabel: UILabel?
    private weak var overdueValueLabel: UILabel?
    private weak var warningBodyLabel: UILabel?

    init(
        debtTitle: String = "Dívida selecionada",
        amountText: String = "R$ 0,00",
        documentText: String = "não informado",
        overdueText: String = "a verificar"
    ) {
        self.debtTitle = debtTitle
        self.amountText = amountText
        self.documentText = documentText
        self.overdueText = overdueText
        super.init(cardWidth: 360)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
    }

    /// Aqui eu monto o resumo de negativacao com alerta, dados da cobranca e confirmacao final.
    private func setupContent() {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = UIColor(hex: "#E31389")

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Serasa Experian"
        title.textColor = .white
        title.font = .italicSystemFont(ofSize: 28)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "Integração Oficial BillEasy.ia"
        subtitle.textColor = UIColor(hex: "#FFD9F0")
        subtitle.font = .systemFont(ofSize: 14, weight: .semibold)

        popupCard.addSubview(header)
        header.addSubview(title)
        header.addSubview(subtitle)

        let warningBox = UIView()
        warningBox.translatesAutoresizingMaskIntoConstraints = false
        warningBox.backgroundColor = UIColor(hex: "#FFFBEF")
        warningBox.layer.cornerRadius = 14
        warningBox.layer.cornerCurve = .continuous
        warningBox.layer.borderWidth = 1
        warningBox.layer.borderColor = UIColor(hex: "#F0DCA5").cgColor

        let warningIcon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        warningIcon.translatesAutoresizingMaskIntoConstraints = false
        warningIcon.tintColor = UIColor(hex: "#C78615")

        let warningTitle = UILabel()
        warningTitle.translatesAutoresizingMaskIntoConstraints = false
        warningTitle.text = "Negativação de CPF"
        warningTitle.textColor = UIColor(hex: "#2B3442")
        warningTitle.font = .systemFont(ofSize: 16, weight: .bold)

        let warningBody = UILabel()
        warningBody.translatesAutoresizingMaskIntoConstraints = false
        warningBody.numberOfLines = 0
        warningBody.text = "Você está prestes a incluir o CPF/CNPJ \(documentText) na base de inadimplentes do Serasa."
        warningBody.textColor = UIColor(hex: "#6A7A91")
        warningBody.font = .systemFont(ofSize: 13, weight: .medium)
        warningBodyLabel = warningBody

        warningBox.addSubview(warningIcon)
        warningBox.addSubview(warningTitle)
        warningBox.addSubview(warningBody)

        let infoStack = UIStackView()
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoStack.axis = .vertical
        infoStack.spacing = 12

        infoStack.addArrangedSubview(makeInfoRow(label: "Dívida:", value: debtTitle, storeIn: &debtValueLabel))
        infoStack.addArrangedSubview(makeInfoRow(label: "Valor Atualizado:", value: amountText, storeIn: &amountValueLabel))
        infoStack.addArrangedSubview(makeInfoRow(label: "Dias em Atraso:", value: overdueText, valueColor: UIColor(hex: "#EF4444"), storeIn: &overdueValueLabel))

        let note = UILabel()
        note.translatesAutoresizingMaskIntoConstraints = false
        note.text = "Ao confirmar, o devedor será notificado e terá seu crédito restrito no mercado em até 24h."
        note.numberOfLines = 0
        note.textAlignment = .center
        note.textColor = UIColor(hex: "#8A9AAE")
        note.font = .systemFont(ofSize: 12, weight: .medium)

        let actionsRow = UIStackView()
        actionsRow.translatesAutoresizingMaskIntoConstraints = false
        actionsRow.axis = .horizontal
        actionsRow.spacing = 12
        actionsRow.distribution = .fillEqually

        let cancel = UIButton(type: .system)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.setTitle("Cancelar", for: .normal)
        cancel.setTitleColor(UIColor(hex: "#6C7E95"), for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        cancel.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let confirm = UIButton(type: .system)
        confirm.translatesAutoresizingMaskIntoConstraints = false
        confirm.setTitle("Confirmar\nNegativação", for: .normal)
        confirm.titleLabel?.numberOfLines = 2
        confirm.titleLabel?.textAlignment = .center
        confirm.setTitleColor(.white, for: .normal)
        confirm.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        confirm.backgroundColor = UIColor(hex: "#E74C3C")
        confirm.layer.cornerRadius = 18
        confirm.layer.cornerCurve = .continuous
        confirm.heightAnchor.constraint(equalToConstant: 56).isActive = true
        confirm.addAction(UIAction { [weak self] _ in
            self?.onConfirmNegativation?()
        }, for: .touchUpInside)

        cancel.heightAnchor.constraint(equalToConstant: PopupLayout.primaryButtonHeight).isActive = true

        actionsRow.addArrangedSubview(cancel)
        actionsRow.addArrangedSubview(confirm)

        let footer = UILabel()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.textAlignment = .center
        footer.textColor = UIColor(hex: "#7A8B9F")
        footer.font = .systemFont(ofSize: 11, weight: .bold)
        footer.text = "🛡  AMBIENTE SEGURO • CRIPTOGRAFIA DE PONTA A PONTA"

        popupCard.addSubview(warningBox)
        popupCard.addSubview(infoStack)
        popupCard.addSubview(note)
        popupCard.addSubview(actionsRow)
        popupCard.addSubview(footer)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: popupCard.topAnchor),
            header.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 92),

            title.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 14),

            subtitle.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),

            warningBox.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            warningBox.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor, constant: 14),
            warningBox.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor, constant: -14),

            warningIcon.leadingAnchor.constraint(equalTo: warningBox.leadingAnchor, constant: 14),
            warningIcon.topAnchor.constraint(equalTo: warningBox.topAnchor, constant: 14),
            warningIcon.widthAnchor.constraint(equalToConstant: 16),
            warningIcon.heightAnchor.constraint(equalToConstant: 16),

            warningTitle.leadingAnchor.constraint(equalTo: warningIcon.trailingAnchor, constant: 10),
            warningTitle.topAnchor.constraint(equalTo: warningBox.topAnchor, constant: 12),

            warningBody.topAnchor.constraint(equalTo: warningTitle.bottomAnchor, constant: 6),
            warningBody.leadingAnchor.constraint(equalTo: warningIcon.trailingAnchor, constant: 10),
            warningBody.trailingAnchor.constraint(equalTo: warningBox.trailingAnchor, constant: -12),
            warningBody.bottomAnchor.constraint(equalTo: warningBox.bottomAnchor, constant: -12),

            infoStack.topAnchor.constraint(equalTo: warningBox.bottomAnchor, constant: 16),
            infoStack.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor, constant: 20),
            infoStack.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor, constant: -20),

            note.topAnchor.constraint(equalTo: infoStack.bottomAnchor, constant: 16),
            note.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor, constant: 22),
            note.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor, constant: -22),

            actionsRow.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 14),
            actionsRow.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor, constant: 16),
            actionsRow.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor, constant: -16),

            footer.topAnchor.constraint(equalTo: actionsRow.bottomAnchor, constant: 14),
            footer.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: popupCard.bottomAnchor, constant: -14)
        ])
    }

    /// Aqui eu reaproveito a linha label/valor do resumo financeiro e juridico do popup.
    private func makeInfoRow(label: String, value: String, valueColor: UIColor = UIColor(hex: "#2B3442"), storeIn target: inout UILabel?) -> UIView {
        let row = UIView()

        let labelView = UILabel()
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.text = label
        labelView.textColor = UIColor(hex: "#6A7A91")
        labelView.font = .systemFont(ofSize: 14, weight: .medium)

        let valueView = UILabel()
        valueView.translatesAutoresizingMaskIntoConstraints = false
        valueView.text = value
        valueView.textColor = valueColor
        valueView.font = .systemFont(ofSize: 14, weight: .bold)
        valueView.textAlignment = .right
        target = valueView

        row.addSubview(labelView)
        row.addSubview(valueView)

        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labelView.topAnchor.constraint(equalTo: row.topAnchor),
            labelView.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            valueView.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            valueView.topAnchor.constraint(equalTo: row.topAnchor),
            valueView.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            valueView.leadingAnchor.constraint(greaterThanOrEqualTo: labelView.trailingAnchor, constant: 8)
        ])

        return row
    }

    /// Aqui eu atualizo a modal com o detalhe remoto da dívida sem recriar o popup.
    func updateSummary(debtTitle: String, amountText: String, documentText: String, overdueText: String) {
        debtValueLabel?.text = debtTitle
        amountValueLabel?.text = amountText
        overdueValueLabel?.text = overdueText
        warningBodyLabel?.text = "Você está prestes a incluir o CPF/CNPJ \(documentText) na base de inadimplentes do Serasa."
    }
}

/// Aqui eu mostro as formas de pagamento em um popup simples com destaque para economia.
final class PaymentMethodPopupViewController: BasePopupViewController {
    private let invoiceTitle: String
    private let originalPriceText: String
    private let discountedPriceText: String
    private let discountBadgeText: String
    private let savingsText: String
    private var availableMethods: [PortalPaymentMethodOption]
    private weak var subtitleLabelRef: UILabel?
    private weak var oldPriceLabelRef: UILabel?
    private weak var totalLabelRef: UILabel?
    private weak var economyLabelRef: UILabel?
    private weak var methodsStackRef: UIStackView?

    var onSelectMethod: ((PortalPaymentMethod) -> Void)?

    init(
        invoiceTitle: String = "Conta selecionada",
        originalPriceText: String = "R$ 0,00",
        discountedPriceText: String = "R$ 0,00",
        discountBadgeText: String = "-6% OFF",
        savingsText: String = "Você economiza R$ 0,00!",
        availableMethods: [PortalPaymentMethodOption] = PortalPaymentMethodOption.fallbackOptions
    ) {
        self.invoiceTitle = invoiceTitle
        self.originalPriceText = originalPriceText
        self.discountedPriceText = discountedPriceText
        self.discountBadgeText = discountBadgeText
        self.savingsText = savingsText
        self.availableMethods = availableMethods
        super.init(cardWidth: 330)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
    }

    /// Aqui eu apresento o resumo do valor e as opcoes de pagamento disponiveis.
    private func setupContent() {
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Escolha como pagar"
        title.textColor = UIColor(hex: "#2A3442")
        title.font = .systemFont(ofSize: 18, weight: .bold)

        let closeButton = makeCloseButton(tintColor: UIColor(hex: "#6A7A91"))

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = invoiceTitle
        subtitle.textAlignment = .center
        subtitle.textColor = UIColor(hex: "#6A7A91")
        subtitle.font = .systemFont(ofSize: 14, weight: .medium)

        let oldPrice = UILabel()
        oldPrice.translatesAutoresizingMaskIntoConstraints = false
        oldPrice.attributedText = NSAttributedString(
            string: originalPriceText,
            attributes: [
                .foregroundColor: UIColor(hex: "#94A3B8"),
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ]
        )

        let discountChip = UILabel()
        discountChip.translatesAutoresizingMaskIntoConstraints = false
        discountChip.text = discountBadgeText
        discountChip.textAlignment = .center
        discountChip.textColor = UIColor(hex: "#1D7C9D")
        discountChip.font = .systemFont(ofSize: 12, weight: .bold)
        discountChip.backgroundColor = UIColor(hex: "#D8ECF6")
        discountChip.layer.cornerRadius = 10
        discountChip.layer.cornerCurve = .continuous
        discountChip.layer.masksToBounds = true

        let total = UILabel()
        total.translatesAutoresizingMaskIntoConstraints = false
        total.text = discountedPriceText
        total.textAlignment = .center
        total.textColor = UIColor(hex: "#2A3442")
        total.font = .systemFont(ofSize: 44, weight: .bold)

        let economy = UILabel()
        economy.translatesAutoresizingMaskIntoConstraints = false
        economy.text = savingsText
        economy.textAlignment = .center
        economy.textColor = UIColor(hex: "#0B8B59")
        economy.font = .systemFont(ofSize: 14, weight: .bold)
        economy.backgroundColor = UIColor(hex: "#DDF5E9")
        economy.layer.cornerRadius = 13
        economy.layer.cornerCurve = .continuous
        economy.layer.masksToBounds = true

        let methodsStack = UIStackView()
        methodsStack.translatesAutoresizingMaskIntoConstraints = false
        methodsStack.axis = .vertical
        methodsStack.spacing = 10

        popupCard.addSubview(title)
        popupCard.addSubview(closeButton)
        popupCard.addSubview(subtitle)
        popupCard.addSubview(oldPrice)
        popupCard.addSubview(discountChip)
        popupCard.addSubview(total)
        popupCard.addSubview(economy)
        popupCard.addSubview(methodsStack)
        subtitleLabelRef = subtitle
        oldPriceLabelRef = oldPrice
        totalLabelRef = total
        economyLabelRef = economy
        methodsStackRef = methodsStack
        renderMethodButtons()

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: popupCard.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor, constant: PopupLayout.cardInset),

            closeButton.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor, constant: -PopupLayout.cardInset),
            closeButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: PopupLayout.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: PopupLayout.closeButtonSize),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            subtitle.centerXAnchor.constraint(equalTo: popupCard.centerXAnchor),

            oldPrice.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 8),
            oldPrice.centerXAnchor.constraint(equalTo: popupCard.centerXAnchor, constant: -38),

            discountChip.centerYAnchor.constraint(equalTo: oldPrice.centerYAnchor),
            discountChip.leadingAnchor.constraint(equalTo: oldPrice.trailingAnchor, constant: 8),
            discountChip.widthAnchor.constraint(equalToConstant: 64),
            discountChip.heightAnchor.constraint(equalToConstant: 20),

            total.topAnchor.constraint(equalTo: oldPrice.bottomAnchor, constant: 6),
            total.centerXAnchor.constraint(equalTo: popupCard.centerXAnchor),

            economy.topAnchor.constraint(equalTo: total.bottomAnchor, constant: 8),
            economy.centerXAnchor.constraint(equalTo: popupCard.centerXAnchor),
            economy.heightAnchor.constraint(equalToConstant: 26),
            economy.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),

            methodsStack.topAnchor.constraint(equalTo: economy.bottomAnchor, constant: PopupLayout.cardInset),
            methodsStack.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor, constant: PopupLayout.cardInset),
            methodsStack.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor, constant: -PopupLayout.cardInset),
            methodsStack.bottomAnchor.constraint(equalTo: popupCard.bottomAnchor, constant: -PopupLayout.cardInset)
        ])
    }

    /// Aqui eu reaplico as opções de pagamento quando a API devolver o catálogo real do backend.
    func updateAvailableMethods(_ methods: [PortalPaymentMethodOption]) {
        let normalized = methods.isEmpty ? PortalPaymentMethodOption.fallbackOptions : methods
        availableMethods = normalized
        renderMethodButtons()
    }

    /// Aqui eu padronizo o bloco de opcao de pagamento para manter toque e leitura consistentes.
    private func makeMethodButton(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> UIView {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor(hex: "#FDFEFF")
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        button.heightAnchor.constraint(equalToConstant: 80).isActive = true

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = UIColor(hex: "#E8F0F7")
        iconContainer.layer.cornerRadius = 12
        iconContainer.layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = UIColor(hex: "#1D7C9D")

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = UIColor(hex: "#2A3442")
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = UIColor(hex: "#6A7A91")
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        button.addSubview(iconContainer)
        iconContainer.addSubview(iconView)
        button.addSubview(titleLabel)
        button.addSubview(subtitleLabel)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: PopupLayout.compactInset),
            iconContainer.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 40),
            iconContainer.heightAnchor.constraint(equalToConstant: 40),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: button.topAnchor, constant: 18),

            subtitleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        ])

        return button
    }

    /// Aqui eu redesenho a lista de métodos para manter o popup alinhado com o catálogo remoto do backend.
    private func renderMethodButtons() {
        guard let methodsStackRef else { return }

        methodsStackRef.arrangedSubviews.forEach { view in
            methodsStackRef.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for option in availableMethods {
            let button = makeMethodButton(
                icon: option.iconSystemName,
                title: option.title,
                subtitle: option.subtitle
            ) { [weak self] in
                self?.onSelectMethod?(option.method)
            }
            methodsStackRef.addArrangedSubview(button)
        }
    }

    /// Aqui eu reflito no popup o valor atualizado da dívida sem precisar reabrir a modal.
    func updateSummary(invoiceTitle: String, originalPriceText: String, discountedPriceText: String, savingsText: String) {
        subtitleLabelRef?.text = invoiceTitle
        oldPriceLabelRef?.attributedText = NSAttributedString(
            string: originalPriceText,
            attributes: [
                .foregroundColor: UIColor(hex: "#94A3B8"),
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        totalLabelRef?.text = discountedPriceText
        economyLabelRef?.text = savingsText
    }
}

/// Aqui eu represento a conciliacao via chat em um modal leve e direto.
final class ConciliationPopupViewController: BasePopupViewController {
    private let messagesStack = UIStackView()
    private let inputField = UITextField()
    private let disputeTitle: String
    private let openingMessage: String

    init(
        disputeTitle: String = "Conta selecionada",
        openingMessage: String? = nil
    ) {
        self.disputeTitle = disputeTitle
        self.openingMessage = openingMessage ?? "Olá! Sou o assistente virtual do BillEasy. Estou aqui para ajudar na conciliação da dívida \"\(disputeTitle)\". Como posso ajudar vocês a chegarem a um acordo?"
        super.init(cardWidth: 330)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
    }

    /// Aqui eu monto o chat inicial com cabecalho, bolha de abertura e campo de envio.
    private func setupContent() {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = UIColor(hex: "#0E7A9F")

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Conciliação BillEasy.ia"
        title.textColor = .white
        title.font = .systemFont(ofSize: 20, weight: .bold)

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "Disputa: \(disputeTitle)"
        subtitle.textColor = UIColor(hex: "#D7F2FF")
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)

        let closeButton = makeCloseButton(tintColor: .white)

        popupCard.addSubview(header)
        header.addSubview(title)
        header.addSubview(subtitle)
        header.addSubview(closeButton)

        let body = UIView()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.backgroundColor = UIColor(hex: "#F8FAFC")
        popupCard.addSubview(body)

        messagesStack.translatesAutoresizingMaskIntoConstraints = false
        messagesStack.axis = .vertical
        messagesStack.spacing = 8
        body.addSubview(messagesStack)

        let greeting = makeMessageBubble(
            sender: "Mediador BillEasy.ia",
            text: openingMessage
        )
        messagesStack.addArrangedSubview(greeting)

        let footer = UIView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.backgroundColor = UIColor(hex: "#F8FAFC")
        footer.layer.borderWidth = 1
        footer.layer.borderColor = UIColor(hex: "#E1E6EF").cgColor
        popupCard.addSubview(footer)

        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.placeholder = "Digite sua proposta ou dúvida.."
        inputField.setPlaceholderColor(UIColor(hex: "#7A8B9F"))
        inputField.textColor = UIColor(hex: "#2A3442")
        inputField.backgroundColor = UIColor(hex: "#F0F4F8")
        inputField.layer.cornerRadius = 20
        inputField.layer.cornerCurve = .continuous
        inputField.setLeftPadding(14)

        let sendButton = UIButton(type: .system)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setImage(UIImage(systemName: "paperplane"), for: .normal)
        sendButton.tintColor = .white
        sendButton.backgroundColor = UIColor(hex: "#0E7A9F")
        sendButton.layer.cornerRadius = 20
        sendButton.layer.cornerCurve = .continuous
        sendButton.addTarget(self, action: #selector(sendMessageTapped), for: .touchUpInside)

        footer.addSubview(inputField)
        footer.addSubview(sendButton)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: popupCard.topAnchor),
            header.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 82),

            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),

            subtitle.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),

            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -PopupLayout.compactInset),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: PopupLayout.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: PopupLayout.closeButtonSize),

            body.topAnchor.constraint(equalTo: header.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor),

            messagesStack.topAnchor.constraint(equalTo: body.topAnchor, constant: 14),
            messagesStack.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 14),
            messagesStack.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -14),
            messagesStack.bottomAnchor.constraint(lessThanOrEqualTo: body.bottomAnchor, constant: -14),

            footer.topAnchor.constraint(equalTo: body.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: popupCard.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: popupCard.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: popupCard.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 80),

            inputField.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
            inputField.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            inputField.heightAnchor.constraint(equalToConstant: 40),

            sendButton.leadingAnchor.constraint(equalTo: inputField.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -14),
            sendButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 40),

            {
                let preferred = body.heightAnchor.constraint(equalToConstant: 380)
                preferred.priority = .defaultHigh
                return preferred
            }(),
            body.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.45),
            body.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8)
        ])
    }

    /// Aqui eu padronizo as bolhas da conversa para a simulacao de conciliacao.
    private func makeMessageBubble(sender: String, text: String) -> UIView {
        let bubble = UIView()
        bubble.backgroundColor = UIColor(hex: "#EEF2F7")
        bubble.layer.cornerRadius = 14
        bubble.layer.cornerCurve = .continuous
        bubble.layer.borderWidth = 1
        bubble.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor

        let senderLabel = UILabel()
        senderLabel.translatesAutoresizingMaskIntoConstraints = false
        senderLabel.text = sender
        senderLabel.textColor = UIColor(hex: "#6A7A91")
        senderLabel.font = .systemFont(ofSize: 11, weight: .bold)

        let textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        textLabel.text = text
        textLabel.textColor = UIColor(hex: "#2A3442")
        textLabel.font = .systemFont(ofSize: 14, weight: .regular)

        bubble.addSubview(senderLabel)
        bubble.addSubview(textLabel)

        NSLayoutConstraint.activate([
            senderLabel.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
            senderLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),

            textLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 8),
            textLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            textLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            textLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -12)
        ])

        return bubble
    }

    /// Aqui eu adiciono a mensagem do usuario na conversa sem dependencia de backend.
    @objc private func sendMessageTapped() {
        let text = inputField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }

        let answer = makeMessageBubble(sender: "Você", text: text)
        messagesStack.addArrangedSubview(answer)
        inputField.text = nil
    }
}

private extension UITextField {
    /// Aqui eu padronizo um padding horizontal minimo para campos que nao usam leftView customizado.
    func setLeftPadding(_ value: CGFloat) {
        let spacer = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        leftView = spacer
        leftViewMode = .always
    }
}
