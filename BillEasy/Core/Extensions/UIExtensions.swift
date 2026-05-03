//
//  UIExtensions.swift
//  BillEasy
//

import UIKit

// MARK: - Mapeamento de cores do tema

private enum BrandColorPalette {
    static let darkReplacements: [String: String] = [
        "E6EAEE": "081220", "DCE2E8": "0D1D30", "DEE3E8": "0D1D30",
        "F7FAFD": "0F2236", "F6FAFD": "0F2236", "FAFCFF": "10263E",
        "F8FAFC": "0F2236", "F3F7FB": "10253D", "F2F6FA": "10253D",
        "F7F9FC": "10263E", "F9FBFD": "10263E", "FBFCFE": "112A41",
        "FFFFFF": "10263E", "D7DEE8": "1E3C58", "D1DFEC": "234A6A",
        "D1DAE6": "1E3C58", "C8D5E3": "234A6A", "C7D4E2": "234A6A",
        "D2DBE7": "234A6A", "D0DBE8": "234A6A", "D4DCE7": "234A6A",
        "C8D6E8": "234A6A", "E1E6EF": "234A6A", "D8E1ED": "234A6A",
        "A9C9E6": "2A5A7D", "E1EEF8": "15324C", "E0EDF8": "15324C",
        "D9E9F6": "15324C", "D8ECFA": "184464", "D6EAF9": "184464",
        "E8F2FA": "173B56", "EFF5FA": "17334A", "E6F0F8": "173B56",
        "F1F8FF": "173B56", "E7F0F9": "173B56", "EAF1F8": "173B56",
        "E8F4FF": "173B56", "EAF4FB": "173B56", "EEF2F7": "17334A",
        "FFFBEF": "3E3A1F", "FFF2F0": "4A2A2A", "FFF0F0": "4A2A2A",
        "FFE1DE": "5A2A2A", "F8D7DA": "4C2730", "F6C6C6": "8A5A63",
        "F4A5A0": "AA6464", "F04A4A": "FF7D7D", "EF4444": "FF7D7D",
        "DC2626": "FF6D6D", "FCECC8": "54431F", "F0DCA5": "8A7640",
        "E5E7EB": "303C52", "DCFCE7": "1D4E39", "252E3A": "F2F7FF",
        "2A3442": "ECF4FF", "283344": "EAF2FF", "2F3946": "E2EEFF",
        "1A2A3E": "DFECFF", "2B3747": "E8F3FF", "1F2A39": "EAF4FF",
        "475569": "D7E6FA", "425870": "D7E6FA", "607993": "B7CBE3",
        "5F7690": "B7CBE3", "688097": "B7CBE3", "6A7A91": "B7CBE3",
        "70849A": "B7CBE3", "74879E": "B7CBE3", "7A8B9F": "B7CBE3",
        "6E7F95": "B7CBE3", "8AA0B6": "B7CBE3", "95A9BD": "B7CBE3",
        "97AABD": "B7CBE3", "73849B": "AEC3DA", "6F8197": "AEC3DA",
        "7D8EA5": "AEC3DA", "A0AEC0": "8FA8C3", "64748B": "AFC3D9",
        "0E6D94": "2495C5", "0B7BBC": "3AA9DD", "2E87C8": "62C4FF",
        "147FB3": "3AA9DD", "1579A8": "2E98CC", "1386BA": "3AA9DD",
        "24874A": "2FAE6C", "0C602D": "1E854E", "B63C3C": "CE5B5B",
        "8B1018": "AF3241", "163C8F": "2456B9", "214567": "2C5E86",
        "34475F": "3D5A76", "203146": "36516B", "5E6B7B": "8CA6BF",
        "8E9CAD": "B4C7DC"
    ]

    static func resolvedHex(for sourceHex: String, userInterfaceStyle: UIUserInterfaceStyle) -> String {
        let normalized = sourceHex.uppercased()
        guard userInterfaceStyle == .dark else { return normalized }
        return darkReplacements[normalized] ?? normalized
    }

    static func components(for hex: String) -> (CGFloat, CGFloat, CGFloat) {
        guard hex.count == 6 else { return (0, 0, 0) }
        let scanner = Scanner(string: hex)
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else { return (0, 0, 0) }
        return (
            CGFloat((value & 0xFF0000) >> 16) / 255,
            CGFloat((value & 0x00FF00) >> 8) / 255,
            CGFloat(value & 0x0000FF) / 255
        )
    }
}

// MARK: - UITextField

extension UITextField {
    /// Define a cor do placeholder sem precisar manipular `attributedPlaceholder` manualmente.
    func setPlaceholderColor(_ color: UIColor) {
        guard let placeholder else { return }
        attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: color])
    }

    /// Aplica Dynamic Type ao campo: a fonte escala automaticamente com as preferências de acessibilidade do usuário.
    func applyScaledFont(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) {
        font = UIFontMetrics(forTextStyle: textStyle).scaledFont(for: .systemFont(ofSize: size, weight: weight))
        adjustsFontForContentSizeCategory = true
    }
}

// MARK: - UIColor

extension UIColor {
    /// Cria uma cor a partir de uma string hex (com ou sem `#`).
    /// Aplica automaticamente a variante escura do tema a partir do trait collection atual.
    convenience init(hex: String, alpha: CGFloat = 1) {
        let rawHex = hex.replacingOccurrences(of: "#", with: "")
        self.init { traitCollection in
            let resolvedHex = BrandColorPalette.resolvedHex(
                for: rawHex,
                userInterfaceStyle: traitCollection.userInterfaceStyle
            )
            let (red, green, blue) = BrandColorPalette.components(for: resolvedHex)
            return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        }
    }

    /// Cria uma cor fixa a partir de hex, sem aplicar o mapeamento de tema escuro.
    /// Use quando o componente já foi desenhado especificamente para cada tema.
    convenience init(fixedHex: String, alpha: CGFloat = 1) {
        let rawHex = fixedHex.replacingOccurrences(of: "#", with: "")
        let (red, green, blue) = BrandColorPalette.components(for: rawHex)
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Themed Views

final class ThemedSurfaceView: UIView {
    private let surfaceBackgroundColor: UIColor
    private let surfaceBorderColor: UIColor
    private let surfaceBorderWidth: CGFloat

    init(
        backgroundColor: UIColor,
        borderColor: UIColor,
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat
    ) {
        self.surfaceBackgroundColor = backgroundColor
        self.surfaceBorderColor = borderColor
        self.surfaceBorderWidth = borderWidth
        super.init(frame: .zero)
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = borderWidth
        updateResolvedColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        updateResolvedColors()
    }

    private func updateResolvedColors() {
        backgroundColor = surfaceBackgroundColor
        layer.borderWidth = surfaceBorderWidth
        layer.borderColor = surfaceBorderColor.resolvedColor(with: traitCollection).cgColor
    }
}

final class GradientCardView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let gradientColors: [UIColor]

    init(colors: [UIColor], cornerRadius: CGFloat) {
        self.gradientColors = colors
        super.init(frame: .zero)
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradientLayer, at: 0)
        updateGradientColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        updateGradientColors()
    }

    private func updateGradientColors() {
        gradientLayer.colors = gradientColors.map { $0.resolvedColor(with: traitCollection).cgColor }
    }
}

final class HostedViewTableViewCell: UITableViewCell {
    static let reuseIdentifier = "HostedViewTableViewCell"

    private var hostedView: UIView?
    private var hostedConstraints: [NSLayoutConstraint] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        preservesSuperviewLayoutMargins = false
        separatorInset = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        NSLayoutConstraint.deactivate(hostedConstraints)
        hostedView?.removeFromSuperview()
        hostedView = nil
        hostedConstraints = []
    }

    func host(_ view: UIView, insets: UIEdgeInsets) {
        hostedView?.removeFromSuperview()
        NSLayoutConstraint.deactivate(hostedConstraints)

        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        hostedView = view
        hostedConstraints = [
            view.topAnchor.constraint(equalTo: contentView.topAnchor, constant: insets.top),
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -insets.right),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -insets.bottom)
        ]
        NSLayoutConstraint.activate(hostedConstraints)
    }
}

// MARK: - UIFont

extension UIFont {
    /// Retorna uma fonte do sistema escalável com Dynamic Type.
    static func billeasyScaledFont(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle).scaledFont(for: .systemFont(ofSize: size, weight: weight))
    }

    /// Retorna uma fonte monoespaçada escalável com Dynamic Type. Ideal para valores numéricos e técnicos.
    static func billeasyScaledMonospacedFont(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle).scaledFont(for: .monospacedSystemFont(ofSize: size, weight: weight))
    }
}

// MARK: - UILabel

extension UILabel {
    /// Aplica Dynamic Type ao label com uma chamada curta e previsível.
    func applyScaledFont(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) {
        font = UIFont.billeasyScaledFont(size: size, weight: weight, textStyle: textStyle)
        adjustsFontForContentSizeCategory = true
    }
}

// MARK: - UIButton

extension UIButton {
    /// Aplica Dynamic Type ao título do botão (quando usa `titleLabel`).
    func applyScaledTitleFont(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) {
        titleLabel?.font = UIFont.billeasyScaledFont(size: size, weight: weight, textStyle: textStyle)
        titleLabel?.adjustsFontForContentSizeCategory = true
    }

    /// Define cores estáveis para os estados normal e desabilitado do botão,
    /// impedindo que o iOS substitua as cores por variantes de contraste automáticas no tema customizado.
    func applyStableStateColors(
        normalBackground: UIColor? = nil,
        normalForeground: UIColor? = nil,
        disabledBackground: UIColor? = nil,
        disabledForeground: UIColor? = nil
    ) {
        let foreground = normalForeground
        let disabledText = disabledForeground ?? foreground?.withAlphaComponent(0.72)

        if let foreground {
            setTitleColor(foreground, for: .normal)
            setTitleColor(foreground, for: .highlighted)
            setTitleColor(foreground, for: .selected)
        }
        if let disabledText { setTitleColor(disabledText, for: .disabled) }

        configurationUpdateHandler = { button in
            let isDisabled = !button.isEnabled
            if let backgroundColor = isDisabled ? (disabledBackground ?? normalBackground) : normalBackground {
                button.backgroundColor = backgroundColor
            }
            if let foreground {
                let resolvedForeground = isDisabled ? (disabledForeground ?? disabledText ?? foreground) : foreground
                button.tintColor = resolvedForeground
                button.setTitleColor(resolvedForeground, for: .normal)
                button.setTitleColor(resolvedForeground, for: .highlighted)
                button.setTitleColor(resolvedForeground, for: .selected)
            }
            button.alpha = isDisabled ? 0.72 : 1
        }
        setNeedsUpdateConfiguration()
    }
}

// MARK: - UITextView

extension UITextView {
    /// Aplica Dynamic Type ao campo de texto multilinha.
    func applyScaledFont(size: CGFloat, weight: UIFont.Weight = .regular, textStyle: UIFont.TextStyle = .body) {
        font = UIFont.billeasyScaledFont(size: size, weight: weight, textStyle: textStyle)
        adjustsFontForContentSizeCategory = true
    }
}

// MARK: - InsetLabel

/// `UILabel` com padding interno configurável.
/// Usado para badges, avisos e etiquetas de status onde o texto não deve encostar nas bordas do fundo.
final class InsetLabel: UILabel {
    var contentInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let insetSize = CGSize(
            width: max(0, size.width - contentInsets.left - contentInsets.right),
            height: max(0, size.height - contentInsets.top - contentInsets.bottom)
        )
        let fitting = super.sizeThatFits(insetSize)
        return CGSize(
            width: fitting.width + contentInsets.left + contentInsets.right,
            height: fitting.height + contentInsets.top + contentInsets.bottom
        )
    }
}

// MARK: - FeedbackToastStyle

/// Define os estilos visuais possíveis para o toast de feedback rápido.
enum FeedbackToastStyle {
    /// Informação neutra.
    case info
    /// Operação concluída com sucesso.
    case success
    /// Erro ou falha que o usuário precisa saber.
    case error

    fileprivate var backgroundColor: UIColor {
        switch self {
        case .info: return UIColor(hex: "#0F2236", alpha: 0.96)
        case .success: return UIColor(hex: "#1E854E", alpha: 0.96)
        case .error: return UIColor(hex: "#8B1018", alpha: 0.96)
        }
    }

    fileprivate var borderColor: UIColor {
        switch self {
        case .info: return UIColor(hex: "#2C5E86", alpha: 0.92)
        case .success: return UIColor(hex: "#2FAE6C", alpha: 0.92)
        case .error: return UIColor(hex: "#CE5B5B", alpha: 0.92)
        }
    }

    fileprivate var iconName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - BrandCardFactory

/// Fábrica de cards visuais reutilizáveis (estado vazio e estado de carregamento).
/// Garante aparência consistente em todas as telas que precisam de feedback de estado de lista.
enum BrandCardFactory {

    /// Cria um card de estado vazio com ícone, título e subtítulo.
    /// Use quando uma lista não tem itens para exibir.
    static func makeEmptyStateCard(
        title: String,
        subtitle: String,
        iconSystemName: String,
        background: UIColor = UIColor(hex: "#F7FAFD"),
        border: UIColor = UIColor(hex: "#D7DEE8"),
        iconBackground: UIColor = UIColor(hex: "#E8F2FA"),
        accentColor: UIColor = UIColor(hex: "#2E87C8"),
        titleColor: UIColor = UIColor(hex: "#283344"),
        subtitleColor: UIColor = UIColor(hex: "#6E7F95"),
        inset: CGFloat = 16
    ) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = background
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = border.cgColor

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = iconBackground
        iconContainer.layer.cornerRadius = 18
        iconContainer.layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: iconSystemName))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = accentColor

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = titleColor
        titleLabel.applyScaledFont(size: 20, weight: .bold, textStyle: .title3)
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = subtitleColor
        subtitleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)
        subtitleLabel.numberOfLines = 0

        card.addSubview(iconContainer)
        iconContainer.addSubview(iconView)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.isAccessibilityElement = true
        card.accessibilityTraits = .staticText
        card.accessibilityLabel = title
        card.accessibilityValue = subtitle

        NSLayoutConstraint.activate([
            iconContainer.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            iconContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            iconContainer.widthAnchor.constraint(equalToConstant: 36),
            iconContainer.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset)
        ])

        return card
    }

    /// Cria um card de carregamento com spinner, título e subtítulo.
    /// Use enquanto o conteúdo da tela ainda está sendo carregado do servidor.
    static func makeLoadingStateCard(
        title: String,
        subtitle: String,
        background: UIColor = UIColor(hex: "#F7FAFD"),
        border: UIColor = UIColor(hex: "#D7DEE8"),
        accentColor: UIColor = UIColor(hex: "#2E87C8"),
        titleColor: UIColor = UIColor(hex: "#283344"),
        subtitleColor: UIColor = UIColor(hex: "#6E7F95"),
        inset: CGFloat = 16
    ) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = background
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = border.cgColor

        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.color = accentColor
        indicator.startAnimating()

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = titleColor
        titleLabel.applyScaledFont(size: 20, weight: .bold, textStyle: .title3)
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = subtitleColor
        subtitleLabel.applyScaledFont(size: 14, weight: .medium, textStyle: .body)
        subtitleLabel.numberOfLines = 0

        card.addSubview(indicator)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.isAccessibilityElement = true
        card.accessibilityTraits = .updatesFrequently
        card.accessibilityLabel = title
        card.accessibilityValue = subtitle

        NSLayoutConstraint.activate([
            indicator.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            indicator.topAnchor.constraint(equalTo: card.topAnchor, constant: inset + 2),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            titleLabel.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset)
        ])

        return card
    }
}

// MARK: - UIViewController + Toast

extension UIViewController {
    /// Exibe uma mensagem de feedback temporária (toast) na parte inferior da tela.
    /// O toast some automaticamente após ~2 segundos sem bloquear a interação do usuário.
    /// - Parameters:
    ///   - message: Texto exibido no toast.
    ///   - style: Estilo visual (`.info`, `.success` ou `.error`).
    func showSimpleToast(_ message: String, style: FeedbackToastStyle = .info) {
        // Remove qualquer toast anterior para não empilhar vários ao mesmo tempo.
        let toastIdentifier = "billeasy.standard.toast"
        view.subviews
            .filter { $0.accessibilityIdentifier == toastIdentifier }
            .forEach { $0.removeFromSuperview() }

        let toast = UIView()
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.accessibilityIdentifier = toastIdentifier
        toast.backgroundColor = style.backgroundColor
        toast.layer.cornerRadius = 14
        toast.layer.cornerCurve = .continuous
        toast.layer.borderWidth = 1
        toast.layer.borderColor = style.borderColor.cgColor
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: 8)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10

        let icon = UIImageView(image: UIImage(systemName: style.iconName))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor(hex: "#F7FBFF")

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.numberOfLines = 0
        label.textColor = UIColor(hex: "#F7FBFF")
        label.applyScaledFont(size: 13, weight: .semibold, textStyle: .callout)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        toast.addSubview(stack)
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            stack.topAnchor.constraint(equalTo: toast.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -12),

            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])

        // Aparece com fade + deslocamento vertical, some após 1,6s.
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
            toast.alpha = 1
            toast.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.22, delay: 1.6, options: .curveEaseIn) {
                toast.alpha = 0
                toast.transform = CGAffineTransform(translationX: 0, y: 6)
            } completion: { _ in
                toast.removeFromSuperview()
            }
        }
    }
}
