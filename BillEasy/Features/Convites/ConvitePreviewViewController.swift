//
//  ConvitePreviewViewController.swift
//  BillEasy
//

import UIKit

final class ConvitePreviewViewController: UIViewController {

    // MARK: - Layout

    private enum Layout {
        static let horizontalMargin: CGFloat = 16
        static let contentInset: CGFloat = 16
        static let cardCornerRadius: CGFloat = 16
        static let sectionSpacing: CGFloat = 14
        static let bottomMargin: CGFloat = 40
    }

    // MARK: - Dependencies

    private let token: String
    private let session: AuthSession
    private let service: ConvitesService

    // MARK: - State

    private var preview: ConvitePreview?
    private var isLoading = false
    private var isAccepting = false
    private var loadErrorMessage: String?

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let aceitarButton = UIButton(type: .system)
    private let recusarButton = UIButton(type: .system)

    // MARK: - Callbacks

    var onAceitar: (() -> Void)?
    var onRecusar: (() -> Void)?

    // MARK: - Init

    init(
        token: String,
        session: AuthSession,
        service: ConvitesService = ConvitesService()
    ) {
        self.token = token
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
        loadPreview()
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
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    // MARK: - Data

    private func loadPreview() {
        isLoading = true
        loadErrorMessage = nil
        renderContent()

        Task { [weak self] in
            guard let self else { return }
            do {
                let loadedPreview = try await self.service.fetchPreview(token: self.token)
                await MainActor.run {
                    self.preview = loadedPreview
                    self.isLoading = false
                    self.renderContent()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.loadErrorMessage = error.localizedDescription
                    self.renderContent()
                }
            }
        }
    }

    private func aceitarConvite() {
        guard !isAccepting else { return }
        isAccepting = true
        refreshActionButtons()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.aceitar(token: self.token)
                await MainActor.run {
                    self.isAccepting = false
                    self.refreshActionButtons()
                    self.showSimpleToast("Convite aceito com sucesso.", style: .success)
                    self.onAceitar?()
                }
            } catch {
                await MainActor.run {
                    self.isAccepting = false
                    self.refreshActionButtons()
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

        stack.addArrangedSubview(makeHeader())

        if isLoading {
            stack.addArrangedSubview(BrandCardFactory.makeLoadingStateCard(
                title: "Carregando convite",
                subtitle: "Buscando os detalhes do convite recebido…"
            ))
            return
        }

        if let loadErrorMessage {
            stack.addArrangedSubview(BrandCardFactory.makeEmptyStateCard(
                title: "Não foi possível abrir o convite",
                subtitle: loadErrorMessage,
                iconSystemName: "exclamationmark.circle"
            ))
            stack.addArrangedSubview(makeRetryButton())
            return
        }

        guard let preview else {
            stack.addArrangedSubview(BrandCardFactory.makeEmptyStateCard(
                title: "Convite indisponível",
                subtitle: "Este convite não retornou dados válidos. Verifique o link e tente novamente.",
                iconSystemName: "link.badge.plus"
            ))
            return
        }

        stack.addArrangedSubview(makeHeroCard(preview))
        stack.addArrangedSubview(makeDetailsCard(preview))
        stack.addArrangedSubview(makeActionsCard(preview))
    }

    private func refreshActionButtons() {
        aceitarButton.isEnabled = !isAccepting
        recusarButton.isEnabled = !isAccepting

        var aceitarConfiguration = UIButton.Configuration.filled()
        aceitarConfiguration.cornerStyle = .capsule
        aceitarConfiguration.baseBackgroundColor = UIColor(hex: "#2E87C8")
        aceitarConfiguration.baseForegroundColor = UIColor(hex: "#FFFFFF")
        aceitarConfiguration.title = isAccepting ? "Aceitando…" : "Aceitar Convite"
        aceitarConfiguration.image = isAccepting ? nil : UIImage(systemName: "checkmark.circle.fill")
        aceitarConfiguration.imagePadding = 8
        aceitarButton.configuration = aceitarConfiguration

        var recusarConfiguration = UIButton.Configuration.tinted()
        recusarConfiguration.cornerStyle = .capsule
        recusarConfiguration.baseBackgroundColor = UIColor(hex: "#FEE2E2")
        recusarConfiguration.baseForegroundColor = UIColor(hex: "#B91C1C")
        recusarConfiguration.title = "Recusar"
        recusarConfiguration.image = UIImage(systemName: "xmark.circle")
        recusarConfiguration.imagePadding = 8
        recusarButton.configuration = recusarConfiguration
    }

    // MARK: - View factories

    private func makeHeader() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor(hex: "#2E87C8")
        closeButton.accessibilityLabel = "Fechar"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Convite"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 28, weight: .bold, textStyle: .largeTitle)
        titleLabel.accessibilityTraits = [.header]

        container.addSubview(closeButton)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 52),

            closeButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func makeHeroCard(_ preview: ConvitePreview) -> UIView {
        let card = makeCard(background: UIColor(hex: "#122B46"), border: UIColor(hex: "#122B46"))

        let typeLabel = makeLabel(
            preview.tipoDisplay.uppercased(),
            color: UIColor(hex: "#9BD3FF"),
            size: 12,
            weight: .bold,
            textStyle: .caption1
        )
        typeLabel.numberOfLines = 1

        let titleLabel = makeLabel(
            preview.nomeCriador,
            color: UIColor(hex: "#F8FBFF"),
            size: 28,
            weight: .bold,
            textStyle: .title1
        )

        let descriptionLabel = makeLabel(
            preview.descricao,
            color: UIColor(hex: "#D7E4F1"),
            size: 15,
            weight: .medium,
            textStyle: .body
        )

        let badge = makePill(text: preview.papelDisplay, color: UIColor(hex: "#9BD3FF"))

        card.addSubview(typeLabel)
        card.addSubview(titleLabel)
        card.addSubview(descriptionLabel)
        card.addSubview(badge)

        NSLayoutConstraint.activate([
            typeLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            typeLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            typeLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -12),

            badge.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            badge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            titleLabel.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            descriptionLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20)
        ])

        return card
    }

    private func makeDetailsCard(_ preview: ConvitePreview) -> UIView {
        let card = makeCard()
        let detailsStack = UIStackView()
        detailsStack.translatesAutoresizingMaskIntoConstraints = false
        detailsStack.axis = .vertical
        detailsStack.spacing = 12

        detailsStack.addArrangedSubview(makeInfoRow(title: "Convidado", value: preview.nomeConvidado))
        detailsStack.addArrangedSubview(makeInfoRow(title: "Documento", value: preview.documentoDisplay))
        detailsStack.addArrangedSubview(makeInfoRow(title: "E-mail", value: preview.emailConvidado))
        detailsStack.addArrangedSubview(makeInfoRow(title: "Telefone", value: preview.telefoneConvidado))
        detailsStack.addArrangedSubview(makeSeparator())
        detailsStack.addArrangedSubview(makeInfoRow(title: "Valor", value: preview.valorDisplay))
        detailsStack.addArrangedSubview(makeInfoRow(title: "Parcelas", value: "\(preview.quantidadeParcelas)x"))
        detailsStack.addArrangedSubview(makeInfoRow(title: "Método", value: preview.metodoPagamentoDisplay))
        detailsStack.addArrangedSubview(makeInfoRow(title: "Primeiro vencimento", value: preview.vencimentoDisplay))
        detailsStack.addArrangedSubview(makeInfoRow(title: "Referência", value: preview.referenciaDisplay))

        if preview.jaAceito {
            detailsStack.addArrangedSubview(makeStatusBanner(
                title: "Convite já aceito",
                subtitle: "Você já confirmou participação neste documento.",
                color: UIColor(hex: "#2FAE6C")
            ))
        } else if preview.jaPossuiConta == false {
            detailsStack.addArrangedSubview(makeStatusBanner(
                title: "Conta necessária",
                subtitle: "Após aceitar, conclua o cadastro para acessar o documento.",
                color: UIColor(hex: "#2E87C8")
            ))
        }

        card.addSubview(detailsStack)

        NSLayoutConstraint.activate([
            detailsStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            detailsStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            detailsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            detailsStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        return card
    }

    private func makeActionsCard(_ preview: ConvitePreview) -> UIView {
        let card = makeCard()
        let titleLabel = makeLabel(
            "Responder convite",
            color: UIColor(hex: "#252E3A"),
            size: 18,
            weight: .bold,
            textStyle: .headline
        )

        let subtitleLabel = makeLabel(
            "Confirme apenas se os dados acima pertencem a você.",
            color: UIColor(hex: "#5F7085"),
            size: 14,
            weight: .medium,
            textStyle: .body
        )

        let buttonStack = UIStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .vertical
        buttonStack.spacing = 10

        aceitarButton.translatesAutoresizingMaskIntoConstraints = false
        aceitarButton.addTarget(self, action: #selector(aceitarTapped), for: .touchUpInside)
        aceitarButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)

        recusarButton.translatesAutoresizingMaskIntoConstraints = false
        recusarButton.addTarget(self, action: #selector(recusarTapped), for: .touchUpInside)
        recusarButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)

        buttonStack.addArrangedSubview(aceitarButton)
        buttonStack.addArrangedSubview(recusarButton)
        refreshActionButtons()
        aceitarButton.isEnabled = !preview.jaAceito

        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            buttonStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            buttonStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),

            aceitarButton.heightAnchor.constraint(equalToConstant: 52),
            recusarButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        return card
    }

    private func makeRetryButton() -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = UIColor(hex: "#2E87C8")
        configuration.baseForegroundColor = UIColor(hex: "#FFFFFF")
        configuration.title = "Tentar novamente"
        configuration.image = UIImage(systemName: "arrow.clockwise")
        configuration.imagePadding = 8
        button.configuration = configuration
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }

    private func makeInfoRow(title: String, value: String) -> UIView {
        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.distribution = .fill
        row.spacing = 12

        let titleLabel = makeLabel(title, color: UIColor(hex: "#708096"), size: 13, weight: .semibold, textStyle: .caption1)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let valueLabel = makeLabel(value, color: UIColor(hex: "#263241"), size: 15, weight: .semibold, textStyle: .body)
        valueLabel.textAlignment = .right

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func makeStatusBanner(title: String, subtitle: String, color: UIColor) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = color.withAlphaComponent(0.12)
        container.layer.cornerRadius = 12
        container.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: "info.circle.fill"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = color

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 3

        stack.addArrangedSubview(makeLabel(title, color: color, size: 14, weight: .bold, textStyle: .callout))
        stack.addArrangedSubview(makeLabel(subtitle, color: UIColor(hex: "#516276"), size: 13, weight: .medium, textStyle: .footnote))

        container.addSubview(icon)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        return container
    }

    private func makeSeparator() -> UIView {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor(hex: "#E2E8F0")
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

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

    private func makePill(text: String, color: UIColor) -> UIView {
        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = color.withAlphaComponent(0.16)
        pill.layer.cornerRadius = 13
        pill.layer.cornerCurve = .continuous

        let label = makeLabel(text, color: color, size: 12, weight: .bold, textStyle: .caption1)
        label.textAlignment = .center
        label.numberOfLines = 1
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6)
        ])

        return pill
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
        label.applyScaledFont(size: size, weight: weight, textStyle: textStyle)
        label.numberOfLines = 0
        return label
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        onRecusar?()
        dismiss(animated: true)
    }

    @objc private func retryTapped() {
        loadPreview()
    }

    @objc private func aceitarTapped() {
        guard preview?.jaAceito != true else { return }
        let alert = UIAlertController(
            title: "Aceitar convite?",
            message: "Ao confirmar, você passa a participar deste documento no BillEasy.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        alert.addAction(UIAlertAction(title: "Aceitar", style: .default) { [weak self] _ in
            self?.aceitarConvite()
        })
        present(alert, animated: true)
    }

    @objc private func recusarTapped() {
        onRecusar?()
        dismiss(animated: true)
    }
}
