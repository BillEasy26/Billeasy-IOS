import UIKit
import PDFKit

// MARK: - ContractDocumentSupport

/// Utilitários para geração e exibição de documentos PDF de contratos dentro do app.
enum ContractDocumentSupport {

    /// Gera um PDF simples a partir de um texto de contrato e o salva em um arquivo temporário.
    /// - Parameters:
    ///   - contractText: Corpo do contrato em texto puro.
    ///   - title: Título exibido no topo do documento PDF.
    /// - Returns: URL do arquivo PDF gerado no diretório temporário do app.
    static func makeLocalPDF(contractText: String, title: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("contrato-\(UUID().uuidString).pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        try renderer.writePDF(to: fileURL) { context in
            context.beginPage()

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let bodyParagraph = NSMutableParagraphStyle()
            bodyParagraph.lineSpacing = 4
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.black,
                .paragraphStyle: bodyParagraph
            ]

            NSString(string: title).draw(in: CGRect(x: 40, y: 44, width: 515, height: 30), withAttributes: titleAttributes)
            NSString(string: contractText).draw(in: CGRect(x: 40, y: 92, width: 515, height: 710), withAttributes: bodyAttributes)
        }

        return fileURL
    }
}

// MARK: - PortalActionsService + Retry de PDF

extension PortalActionsService {

    /// Baixa o PDF de um contrato com até 3 tentativas automáticas.
    /// O retry existe porque o backend pode levar alguns segundos para gerar o PDF
    /// logo após a criação do contrato — sem ele o primeiro download costumava falhar.
    func downloadContractDocumentWithShortRetry(contractID: String) async throws -> URL {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await downloadContractDocument(contractID: contractID)
            } catch {
                lastError = error
                guard attempt < 2 else { break }
                // Espera crescente: 600ms, 1200ms.
                try? await Task.sleep(nanoseconds: UInt64((attempt + 1) * 600_000_000))
            }
        }
        throw lastError ?? PortalActionsServiceError.integrationUnavailable
    }
}

// MARK: - UIViewController + Preview de PDF

extension UIViewController {

    /// Apresenta o PDF de um contrato dentro do app em um modal de tela cheia.
    /// - Parameters:
    ///   - fileURL: URL local do arquivo PDF (baixado ou gerado localmente).
    ///   - title: Título exibido na barra de navegação do modal.
    ///   - preferredPresenter: Controller que deve apresentar o modal; usa `self` se `nil`.
    func presentContractDocumentPreview(fileURL: URL, title: String, preferredPresenter: UIViewController? = nil) {
        let previewController = ContractDocumentPreviewViewController(fileURL: fileURL, titleText: title)
        let nav = UINavigationController(rootViewController: previewController)
        nav.modalPresentationStyle = .formSheet
        let presenter = preferredPresenter ?? presentedViewController ?? self
        presenter.present(nav, animated: true)
    }

    /// Gera um PDF localmente a partir de texto e o exibe em seguida.
    /// Útil em modo offline ou para exibir minutas antes de assinar.
    func presentLocalContractDocumentPreview(contractText: String, title: String, preferredPresenter: UIViewController? = nil) throws {
        let fileURL = try ContractDocumentSupport.makeLocalPDF(contractText: contractText, title: title)
        presentContractDocumentPreview(fileURL: fileURL, title: title, preferredPresenter: preferredPresenter)
    }
}

// MARK: - ContractDocumentPreviewViewController

/// Controller que exibe um documento PDF usando `PDFView` do framework `PDFKit`.
/// Apresentado em modal (`formSheet`) com botão "Concluído" para fechar.
final class ContractDocumentPreviewViewController: UIViewController {
    private let fileURL: URL
    private let titleText: String
    private let pdfView = PDFView()

    init(fileURL: URL, titleText: String) {
        self.fileURL = fileURL
        self.titleText = titleText
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = titleText

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(closeTapped)
        )

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: fileURL)
        view.addSubview(pdfView)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Fecha o modal quando o usuário toca em "Concluído".
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
