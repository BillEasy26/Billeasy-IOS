//
//  PromissoriaDetalheViewController.swift
//  BillEasy
//

import UIKit

final class PromissoriaDetalheViewController: UIViewController {

    // MARK: - Layout

    private enum Layout {
        static let horizontalMargin: CGFloat = 16
        static let cardCornerRadius: CGFloat = 16
        static let sectionSpacing: CGFloat = 14
        static let contentInset: CGFloat = 16
        static let bottomMargin: CGFloat = 40
    }

    // MARK: - Dependencies

    private let promissoriaID: String
    private let service: PromissoriasService
    private let session: AuthSession

    // MARK: - State

    private var promissoria: Promissoria?
    private var isLoading = false
    private var isActing = false

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let loadingOverlay = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    // MARK: - Callbacks

    var onVoltar: (() -> Void)?
    var onAbrirPDF: ((String) -> Void)?

    // MARK: - Init

    init(
        promissoriaID: String,
        session: AuthSession,
        service: PromissoriasService = PromissoriasService()
    ) {
        self.promissoriaID = promissoriaID
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
        loadDetalhe()
    }

    func setExternalLoading(_ loading: Bool) {
        loadingOverlay.isHidden = !loading
        loading ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
        view.isUserInteractionEnabled = !loading
        loadingOverlay.isUserInteractionEnabled = loading
    }

    // MARK: - Setup

    private func setupView() {
        view.backgroundColor = UIColor(hex: "#E6EAEE")

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = Layout.sectionSpacing
        stack.layoutMargins = UIEdgeInsets(
            top: Layout.contentInset,
            left: Layout.horizontalMargin,
            bottom: Layout.bottomMargin,
            right: Layout.horizontalMargin
        )
        stack.isLayoutMarginsRelativeArrangement = true

        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        setupLoadingOverlay()
    }

    private func setupLoadingOverlay() {
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.backgroundColor = UIColor(hex: "#E6EAEE")
        loadingOverlay.isHidden = true

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = UIColor(hex: "#2E87C8")

        loadingOverlay.addSubview(activityIndicator)
        view.addSubview(loadingOverlay)

        NSLayoutConstraint.activate([
            loadingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor)
        ])
    }

    // MARK: - Data

    private func loadDetalhe() {
        isLoading = true
        renderContent()

        Task { [weak self] in
            guard let self else { return }
            do {
                let p = try await self.service.fetchDetalhe(id: self.promissoriaID)
                await MainActor.run {
                    self.promissoria = p
                    self.isLoading = false
                    self.renderContent()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.renderContent()
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    // MARK: - Rendering

    private func renderContent() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        stack.addArrangedSubview(makeNavBar())

        if isLoading {
            stack.addArrangedSubview(BrandCardFactory.makeLoadingStateCard(
                title: "Carregando promissória",
                subtitle: "Buscando os detalhes do documento…"
            ))
            return
        }

        guard let p = promissoria else {
            stack.addArrangedSubview(BrandCardFactory.makeEmptyStateCard(
                title: "Promissória não encontrada",
                subtitle: "Não foi possível carregar os detalhes. Volte e tente novamente.",
                iconSystemName: "exclamationmark.circle"
            ))
            return
        }

        stack.addArrangedSubview(makeHeroCard(p))
        stack.addArrangedSubview(makeSectionLabel("Partes"))
        for parte in p.partes {
            stack.addArrangedSubview(makeParteCard(parte))
        }
        if p.etapa.hasDocumento {
            stack.addArrangedSubview(makeDocumentoCard(p))
        }
        stack.addArrangedSubview(makeActionsCard(p))
    }

    // MARK: - View factories

    private func makeNavBar() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let backButton = UIButton(type: .system)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.setTitle("  Voltar", for: .normal)
        backButton.tintColor = UIColor(hex: "#2E87C8")
        backButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        backButton.addTarget(self, action: #selector(voltarTapped), for: .touchUpInside)
        backButton.accessibilityLabel = "Voltar"

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Promissória"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 18, weight: .bold, textStyle: .headline)

        container.addSubview(backButton)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),
            backButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func makeHeroCard(_ p: Promissoria) -> UIView {
        let card = makeSurface()
        let (badgeBg, badgeText) = p.etapa.badgeColor

        let badgeView = makePill(
            text: p.etapa.displayTitle.uppercased(),
            bg: badgeBg,
            fg: badgeText
        )

        let valorLabel = UILabel()
        valorLabel.translatesAutoresizingMaskIntoConstraints = false
        valorLabel.text = p.valorDisplay
        valorLabel.textColor = UIColor(hex: "#1A2B3C")
        valorLabel.applyScaledFont(size: 32, weight: .bold, textStyle: .title1)

        let metodoLabel = UILabel()
        metodoLabel.translatesAutoresizingMaskIntoConstraints = false
        let parcText = p.quantidadeParcelas > 1 ? "\(p.quantidadeParcelas) parcelas" : "À vista"
        metodoLabel.text = "\(parcText) · \(p.metodoPagamentoDisplay)"
        metodoLabel.textColor = UIColor(hex: "#5A7291")
        metodoLabel.applyScaledFont(size: 15, weight: .medium, textStyle: .body)

        let separator = makeSeparator()

        let vencRow = makeInfoRow(label: "1º Vencimento", value: p.primeiroVencimentoDisplay)
        let jurosRow = makeInfoRow(label: "Juros mensais", value: "\(p.jurosMensalPercent)%")
        let multaRow = makeInfoRow(label: "Multa por atraso", value: "\(p.multaAtrasoPercent)%")

        let infoStack = UIStackView(arrangedSubviews: [vencRow, jurosRow, multaRow])
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoStack.axis = .vertical
        infoStack.spacing = 8

        for sub in [badgeView, valorLabel, metodoLabel, separator, infoStack] as [UIView] {
            sub.translatesAutoresizingMaskIntoConstraints = true
            card.addSubview(sub)
        }
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        valorLabel.translatesAutoresizingMaskIntoConstraints = false
        metodoLabel.translatesAutoresizingMaskIntoConstraints = false
        separator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            badgeView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            badgeView.topAnchor.constraint(equalTo: card.topAnchor, constant: Layout.contentInset),

            valorLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            valorLabel.topAnchor.constraint(equalTo: badgeView.bottomAnchor, constant: 12),
            valorLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),

            metodoLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            metodoLabel.topAnchor.constraint(equalTo: valorLabel.bottomAnchor, constant: 4),

            separator.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            separator.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            separator.topAnchor.constraint(equalTo: metodoLabel.bottomAnchor, constant: 14),
            separator.heightAnchor.constraint(equalToConstant: 1),

            infoStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            infoStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            infoStack.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 14),
            infoStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Layout.contentInset)
        ])

        return card
    }

    private func makeParteCard(_ parte: PartePromissoria) -> UIView {
        let card = makeSurface()

        let papelPill = makePill(
            text: parte.papelDisplay.uppercased(),
            bg: "#E8F2FA",
            fg: "#1D5E8A"
        )

        let nomeLabel = UILabel()
        nomeLabel.translatesAutoresizingMaskIntoConstraints = false
        nomeLabel.text = parte.nome
        nomeLabel.textColor = UIColor(hex: "#252E3A")
        nomeLabel.applyScaledFont(size: 16, weight: .semibold, textStyle: .body)

        let docLabel = UILabel()
        docLabel.translatesAutoresizingMaskIntoConstraints = false
        docLabel.text = "\(parte.documentoTipo.uppercased()) \(parte.documentoFormatado)"
        docLabel.textColor = UIColor(hex: "#6E7F95")
        docLabel.applyScaledFont(size: 13, weight: .regular, textStyle: .footnote)

        let kycBadge: UIView
        if parte.kycAprovado {
            kycBadge = makePill(text: "KYC APROVADO", bg: "#D1FAE5", fg: "#065F46")
        } else if parte.kycVerificacaoId != nil {
            kycBadge = makePill(text: "KYC PENDENTE", bg: "#FEF3C7", fg: "#92400E")
        } else {
            kycBadge = makePill(text: "SEM KYC", bg: "#F1F5F9", fg: "#475569")
        }

        let assinIcon = UIImageView(image: UIImage(systemName: parte.assinadoEm != nil ? "checkmark.seal.fill" : "clock"))
        assinIcon.translatesAutoresizingMaskIntoConstraints = false
        assinIcon.tintColor = parte.assinadoEm != nil ? UIColor(hex: "#22C55E") : UIColor(hex: "#94A3B8")

        for sub in [papelPill, nomeLabel, docLabel, kycBadge, assinIcon] as [UIView] {
            card.addSubview(sub)
        }

        NSLayoutConstraint.activate([
            papelPill.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            papelPill.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),

            nomeLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            nomeLabel.topAnchor.constraint(equalTo: papelPill.bottomAnchor, constant: 8),
            nomeLabel.trailingAnchor.constraint(lessThanOrEqualTo: assinIcon.leadingAnchor, constant: -8),

            docLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            docLabel.topAnchor.constraint(equalTo: nomeLabel.bottomAnchor, constant: 4),

            kycBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            kycBadge.topAnchor.constraint(equalTo: docLabel.bottomAnchor, constant: 8),
            kycBadge.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            assinIcon.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            assinIcon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            assinIcon.widthAnchor.constraint(equalToConstant: 24),
            assinIcon.heightAnchor.constraint(equalToConstant: 24)
        ])

        return card
    }

    private func makeDocumentoCard(_ p: Promissoria) -> UIView {
        let card = makeSurface()

        let icon = UIImageView(image: UIImage(systemName: "doc.richtext"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor(hex: "#2E87C8")

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Documento gerado"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 16, weight: .semibold, textStyle: .body)

        let geradoLabel = UILabel()
        geradoLabel.translatesAutoresizingMaskIntoConstraints = false
        if let dt = p.documentoGeradoEm {
            geradoLabel.text = Formatters.shortDate.string(from: dt)
        } else {
            geradoLabel.text = "—"
        }
        geradoLabel.textColor = UIColor(hex: "#6E7F95")
        geradoLabel.applyScaledFont(size: 13, weight: .regular, textStyle: .footnote)

        let pdfButton = UIButton(type: .system)
        pdfButton.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.tinted()
        config.title = "Ver PDF"
        config.image = UIImage(systemName: "arrow.down.doc")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        pdfButton.configuration = config
        pdfButton.tintColor = UIColor(hex: "#2E87C8")
        pdfButton.addTarget(self, action: #selector(verPDFTapped), for: .touchUpInside)

        card.addSubview(icon)
        card.addSubview(titleLabel)
        card.addSubview(geradoLabel)
        card.addSubview(pdfButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: Layout.contentInset),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: icon.centerYAnchor),

            geradoLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            geradoLabel.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),

            pdfButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            pdfButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            pdfButton.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -12)
        ])

        geradoLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Layout.contentInset).isActive = true

        return card
    }

    private func makeActionsCard(_ p: Promissoria) -> UIView {
        let card = makeSurface()
        let actionsStack = UIStackView()
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionsStack.axis = .vertical
        actionsStack.spacing = 10

        if p.etapa.canIniciarKyc {
            actionsStack.addArrangedSubview(makeActionButton(
                title: "Iniciar KYC",
                icon: "person.badge.shield.checkmark",
                style: .filled,
                color: UIColor(hex: "#2E87C8"),
                action: #selector(iniciarKycTapped)
            ))
        }

        if p.etapa.canEnviarAssinatura {
            actionsStack.addArrangedSubview(makeActionButton(
                title: "Enviar para Assinatura",
                icon: "signature",
                style: .filled,
                color: UIColor(hex: "#2E87C8"),
                action: #selector(enviarAssinaturaTapped)
            ))
        }

        if p.etapa.canCancelar {
            actionsStack.addArrangedSubview(makeActionButton(
                title: "Cancelar Promissória",
                icon: "xmark.circle",
                style: .tinted,
                color: UIColor(hex: "#EF4444"),
                action: #selector(cancelarTapped)
            ))
        }

        guard actionsStack.arrangedSubviews.isEmpty == false else { return UIView() }

        card.addSubview(actionsStack)
        NSLayoutConstraint.activate([
            actionsStack.topAnchor.constraint(equalTo: card.topAnchor, constant: Layout.contentInset),
            actionsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Layout.contentInset),
            actionsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Layout.contentInset),
            actionsStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Layout.contentInset)
        ])

        return card
    }

    private func makeActionButton(
        title: String,
        icon: String,
        style: UIButton.Configuration.ButtonStyle,
        color: UIColor,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        var config: UIButton.Configuration
        switch style {
        case .filled:
            config = .filled()
            config.baseForegroundColor = .white
            config.baseBackgroundColor = color
        default:
            config = .tinted()
            config.baseForegroundColor = color
        }
        config.title = title
        config.image = UIImage(systemName: icon)
        config.imagePadding = 8
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
        button.configuration = config
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - Helper views

    private func makeSurface() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor(hex: "#F8FAFC")
        v.layer.cornerRadius = Layout.cardCornerRadius
        v.layer.cornerCurve = .continuous
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor
        return v
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = UIColor(hex: "#4B6378")
        label.applyScaledFont(size: 13, weight: .semibold, textStyle: .footnote)
        label.accessibilityTraits = [.header]
        return label
    }

    private func makePill(text: String, bg: String, fg: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor(hex: bg)
        container.layer.cornerRadius = 8
        container.layer.cornerCurve = .continuous

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = UIColor(hex: fg)
        label.applyScaledFont(size: 10, weight: .bold, textStyle: .caption1)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    private func makeSeparator() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor(hex: "#E2E8F0")
        return v
    }

    private func makeInfoRow(label: String, value: String) -> UIView {
        let labelView = UILabel()
        labelView.text = label
        labelView.textColor = UIColor(hex: "#6E7F95")
        labelView.applyScaledFont(size: 13, weight: .regular, textStyle: .footnote)

        let valueView = UILabel()
        valueView.text = value
        valueView.textColor = UIColor(hex: "#252E3A")
        valueView.applyScaledFont(size: 14, weight: .semibold, textStyle: .subheadline)
        valueView.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [labelView, valueView])
        row.axis = .horizontal
        row.distribution = .fill
        row.alignment = .center
        return row
    }

    // MARK: - Actions

    @objc private func voltarTapped() {
        onVoltar?()
    }

    @objc private func verPDFTapped() {
        onAbrirPDF?(promissoriaID)
    }

    @objc private func iniciarKycTapped() {
        guard !isActing else { return }
        isActing = true

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.iniciarKyc(id: self.promissoriaID)
                await MainActor.run {
                    self.isActing = false
                    self.showSimpleToast("KYC iniciado com sucesso.", style: .success)
                    self.loadDetalhe()
                }
            } catch {
                await MainActor.run {
                    self.isActing = false
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    @objc private func enviarAssinaturaTapped() {
        guard !isActing else { return }

        let alert = UIAlertController(
            title: "Enviar para assinatura",
            message: "As partes receberão um link para assinar a promissória. Deseja continuar?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Enviar", style: .default) { [weak self] _ in
            self?.confirmarEnvioAssinatura()
        })
        present(alert, animated: true)
    }

    private func confirmarEnvioAssinatura() {
        isActing = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.enviarParaAssinatura(id: self.promissoriaID)
                await MainActor.run {
                    self.isActing = false
                    self.showSimpleToast("Enviada para assinatura com sucesso.", style: .success)
                    self.loadDetalhe()
                }
            } catch {
                await MainActor.run {
                    self.isActing = false
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }

    @objc private func cancelarTapped() {
        guard !isActing else { return }

        let alert = UIAlertController(
            title: "Cancelar promissória",
            message: "Informe o motivo do cancelamento:",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Motivo"
            tf.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: "Não cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Cancelar promissória", style: .destructive) { [weak self, weak alert] _ in
            let motivo = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !motivo.isEmpty else { return }
            self?.confirmarCancelamento(motivo: motivo)
        })
        present(alert, animated: true)
    }

    private func confirmarCancelamento(motivo: String) {
        isActing = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.cancelar(id: self.promissoriaID, motivo: motivo)
                await MainActor.run {
                    self.isActing = false
                    self.showSimpleToast("Promissória cancelada.", style: .success)
                    self.loadDetalhe()
                }
            } catch {
                await MainActor.run {
                    self.isActing = false
                    self.showSimpleToast(error.localizedDescription, style: .error)
                }
            }
        }
    }
}

// MARK: - UIButton.Configuration.ButtonStyle helper

private extension UIButton.Configuration {
    enum ButtonStyle { case filled, tinted }
}
