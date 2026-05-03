import UIKit

struct ContractAIReviewSnapshot {
    let businessType: String
    let subject: String
    let description: String
    let totalValueText: String
    let dueDateText: String
    let creditorName: String
    let debtorName: String
}

/// Aqui eu mostro ao usuário um resumo legível do que a IA aplicou no formulário antes de ele registrar o contrato.
final class ContractAIPreviewViewController: UIViewController {
    private enum Layout {
        static let horizontalInset: CGFloat = 18
        static let cardRadius: CGFloat = 24
        static let minimumCardHeight: CGFloat = 520
        static let preferredCardHeightRatio: CGFloat = 0.76
    }

    private let snapshot: ContractAIReviewSnapshot
    private let dimmingView = UIView()
    private let cardView = UIView()
    private let closeButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    init(snapshot: ContractAIReviewSnapshot) {
        self.snapshot = snapshot
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
        buildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        animateEntranceIfNeeded()
    }

    private func setupView() {
        view.backgroundColor = .clear

        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.30)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = UIColor(hex: "#FFFFFF")
        cardView.layer.cornerRadius = Layout.cardRadius
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.14
        cardView.layer.shadowOffset = CGSize(width: 0, height: 22)
        cardView.layer.shadowRadius = 32

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor(hex: "#6A7A91")
        closeButton.accessibilityIdentifier = "contracts.aiPreview.closeButton"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 14

        view.addSubview(dimmingView)
        view.addSubview(cardView)
        cardView.addSubview(scrollView)
        cardView.addSubview(closeButton)
        scrollView.addSubview(stackView)
        cardView.bringSubviewToFront(closeButton)
    }

    private func setupLayout() {
        let preferredHeight = cardView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: Layout.preferredCardHeightRatio)
        preferredHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            preferredHeight,
            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.minimumCardHeight),
            cardView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.82),

            closeButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            closeButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            scrollView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            scrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 0),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -18),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36)
        ])
    }

    private func buildContent() {
        stackView.addArrangedSubview(makeHeader())
        stackView.addArrangedSubview(makeSuccessBanner())
        stackView.addArrangedSubview(makeReviewField(title: "TIPO DO NEGÓCIO", value: snapshot.businessType))
        stackView.addArrangedSubview(makeReviewField(title: "ASSUNTO", value: snapshot.subject))
        stackView.addArrangedSubview(makeReviewField(title: "DESCRIÇÃO", value: snapshot.description, multiline: true))
        stackView.addArrangedSubview(makeReviewField(title: "VALOR TOTAL", value: Formatters.normalizeCurrencyDisplay(snapshot.totalValueText)))
        stackView.addArrangedSubview(makeReviewField(title: "VENCIMENTO", value: Formatters.normalizeDateDisplay(snapshot.dueDateText)))
        stackView.addArrangedSubview(makeReviewField(title: "CREDOR", value: snapshot.creditorName))
        stackView.addArrangedSubview(makeReviewField(title: "DEVEDOR", value: snapshot.debtorName))
    }

    private func makeHeader() -> UIView {
        let container = UIView()

        let iconView = UIImageView(image: UIImage(systemName: "sparkles"))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = UIColor(hex: "#FF7A21")

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Geração por IA"
        titleLabel.textColor = UIColor(hex: "#252E3A")
        titleLabel.applyScaledFont(size: 20, weight: .bold, textStyle: .title3)
        titleLabel.numberOfLines = 2

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor(hex: "#D7DEE8")

        container.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            // Aqui eu mantenho o texto dentro do header sem depender do botão de fechar,
            // porque o closeButton mora fora desta sub-hierarquia, direto no card.
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -44),

            separator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func makeSuccessBanner() -> UIView {
        let banner = UIView()
        banner.backgroundColor = UIColor(hex: "#EAF8EC")
        banner.layer.cornerRadius = 14
        banner.layer.cornerCurve = .continuous
        banner.layer.borderWidth = 1
        banner.layer.borderColor = UIColor(hex: "#B7E4C2").cgColor

        let iconView = UIImageView(image: UIImage(systemName: "checkmark.circle"))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = UIColor(hex: "#22B85D")

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = "Contrato gerado com sucesso! Revise os dados abaixo."
        label.textColor = UIColor(hex: "#1D7A3B")
        label.applyScaledFont(size: 15, weight: .semibold, textStyle: .headline)

        banner.addSubview(iconView)
        banner.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -14)
        ])

        return banner
    }

    private func makeReviewField(title: String, value: String, multiline: Bool = false) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(hex: "#FFFFFF")
        container.layer.cornerRadius = 14
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor(hex: "#D7DEE8").cgColor

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = UIColor(hex: "#607993")
        titleLabel.applyScaledFont(size: 12, weight: .bold, textStyle: .caption1)

        let valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.text = value
        valueLabel.textColor = UIColor(hex: "#252E3A")
        valueLabel.numberOfLines = multiline ? 0 : 1
        valueLabel.applyScaledFont(size: 16, weight: .semibold, textStyle: multiline ? .body : .headline)

        container.addSubview(titleLabel)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            valueLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            valueLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])

        return container
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

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
