import Foundation

/// Aqui eu mantenho o endereço normalizado para cards, formulários e fallback local.
struct PortalDirectoryAddress {
    let cep: String
    let logradouro: String
    let numero: String
    let complemento: String?
    let bairro: String
    let cidade: String
    let estado: String

    var streetLine: String {
        let base = [logradouro.nilIfEmpty, numero.nilIfEmpty].compactMap { $0 }.joined(separator: ", ")
        guard let complemento = complemento?.nilIfEmpty else { return base }
        return [base, complemento].filter { $0.isEmpty == false }.joined(separator: " · ")
    }

    var regionLine: String {
        [bairro.nilIfEmpty, cidade.nilIfEmpty, estado.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var summary: String {
        [streetLine.nilIfEmpty, regionLine.nilIfEmpty, Formatters.formatCEP(cep).nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: " • ")
    }
}

/// Aqui eu exponho a empresa pronta para listagem e edição, já convertida do contrato remoto.
struct PortalCompanyRecord {
    let id: String
    let name: String
    let document: String
    let phone: String
    let type: String
    let status: String
    let responsibleID: String?
    let responsibleName: String?
    let address: PortalDirectoryAddress?
    let addressSummary: String?
    let pixKey: String?
    let pixKeyType: String?

    var isActive: Bool {
        status.uppercased() == "ATIVA"
    }
}

/// Aqui eu exponho o devedor com o vínculo de empresa quando o backend trouxer isso na resposta.
struct PortalDebtorRecord {
    let id: String
    let companyID: String?
    let companyName: String?
    let name: String
    let document: String
    let email: String
    let phone: String
    let status: String
    let address: PortalDirectoryAddress?
    let addressSummary: String?
}

/// Aqui eu centralizo os dados que o formulário de empresa precisa enviar no create/update.
struct PortalCompanyFormInput {
    let name: String
    let document: String
    let phone: String
    let type: String
    let cep: String?
    let number: String?
    let complement: String?
    let pixKey: String?
    let pixKeyType: String?
}

/// Aqui eu centralizo os dados que o formulário de devedor precisa enviar no create/update.
struct PortalDebtorFormInput {
    let companyID: String?
    let name: String
    let document: String
    let email: String
    let phone: String
    let cep: String
    let number: String
    let complement: String?
}

enum PortalDirectoryServiceError: LocalizedError {
    case invalidContext(String)

    var errorDescription: String? {
        switch self {
        case let .invalidContext(message):
            return message
        }
    }
}

enum PortalCompanyLifecycleAction {
    case activate
    case suspend
    case block
}

enum PortalDebtorLifecycleAction {
    case activate
    case block
}

/// Aqui eu concentro o CRUD de empresas e devedores em um único serviço para manter as telas leves.
final class PortalDirectoryService {
    private struct PaginatedResponse<Item: Decodable>: Decodable {
        let content: [Item]
    }

    private struct IdentifierReference: Encodable {
        let id: String
    }

    private struct AddressRequest: Encodable {
        let cep: String
        let numero: String
        let complemento: String?
    }

    private struct CompanyCreateRequest: Encodable {
        let nome: String
        let cpfCnpj: String
        let telefone: String
        let tipo: String
        let responsavel: IdentifierReference
        let endereco: AddressRequest?
        let chavePix: String?
        let tipoChavePix: String?
    }

    private struct CompanyUpdateRequest: Encodable {
        let nome: String
        let telefone: String
        let endereco: AddressRequest
    }

    private struct DebtorCreateRequest: Encodable {
        let nome: String
        let cpfCnpjEnc: String
        let email: String
        let telefone: String
        let endereco: AddressRequest
    }

    private struct DebtorUpdateRequest: Encodable {
        let nome: String
        let telefone: String
        let endereco: AddressRequest
    }

    private struct CompanyResponse: Decodable {
        struct ResponsiblePayload: Decodable {
            let id: String?
            let nome: String?
        }

        struct AddressPayload: Decodable {
            let cep: String?
            let logradouro: String?
            let numero: String?
            let complemento: String?
            let bairro: String?
            let cidade: String?
            let estado: String?
        }

        let id: String
        let nome: String?
        let cpfCnpj: String?
        let telefone: String?
        let tipo: String?
        let status: String?
        let responsavel: ResponsiblePayload?
        let endereco: AddressPayload?
        let chavePix: String?
        let tipoChavePix: String?
    }

    private struct DebtorResponse: Decodable {
        struct CompanyPayload: Decodable {
            let id: String?
            let nome: String?
            let cnpj: String?
        }

        struct AddressPayload: Decodable {
            let cep: String?
            let logradouro: String?
            let numero: String?
            let complemento: String?
            let bairro: String?
            let cidade: String?
            let estado: String?
        }

        let id: String
        let nome: String?
        let cpfCnpjEnc: String?
        let email: String?
        let telefone: String?
        let status: String?
        let empresa: CompanyPayload?
        let endereco: AddressPayload?
    }

    private let apiClient: RemoteAPIClient
    private let mode: AppAuthMode
    private let dataStore: LocalAppDataStore

    init(
        apiClient: RemoteAPIClient = RemoteAPIClient(),
        mode: AppAuthMode = AppRuntimeConfiguration.authMode,
        dataStore: LocalAppDataStore
    ) {
        self.apiClient = apiClient
        self.mode = mode
        self.dataStore = dataStore
    }

    var isRemoteMode: Bool {
        mode == .remote
    }

    /// Aqui eu listo as empresas do backend quando possível e caio para o snapshot local no resto dos casos.
    func listCompanies(session: AuthSession, searchName: String? = nil) async throws -> [PortalCompanyRecord] {
        if isRemoteMode {
            let response: PaginatedResponse<CompanyResponse> = try await apiClient.request(
                target: .backend,
                path: makePagedPath(
                    basePath: APIRoutes.Empresas.base,
                    page: 0,
                    size: 60,
                    additionalQueryItems: [URLQueryItem(name: "nome", value: searchName?.nilIfEmpty)]
                )
            )

            let companies = response.content.map(makeCompanyRecord(from:))
            persistCompaniesLocally(companies)
            return companies
        }

        return makeLocalCompanyRecords(searchName: searchName)
    }

    /// Aqui eu crio a empresa no backend usando o mesmo contrato da web e atualizo o fallback local junto.
    func createCompany(session: AuthSession, input: PortalCompanyFormInput) async throws -> PortalCompanyRecord {
        if isRemoteMode {
            let request = CompanyCreateRequest(
                nome: normalizedName(input.name),
                cpfCnpj: normalizedDocument(input.document),
                telefone: normalizedPhone(input.phone),
                tipo: input.type,
                responsavel: IdentifierReference(id: session.userID),
                endereco: makeOptionalAddressRequest(cep: input.cep, number: input.number, complement: input.complement),
                chavePix: input.pixKey?.nilIfEmpty,
                tipoChavePix: input.pixKeyType?.nilIfEmpty
            )

            let response: CompanyResponse = try await apiClient.request(
                target: .backend,
                path: APIRoutes.Empresas.base,
                method: "POST",
                body: request
            )

            let company = makeCompanyRecord(from: response)
            persistCompanyLocally(company)
            return company
        }

        guard let localCompany = dataStore.upsertCompany(
            name: normalizedName(input.name),
            document: Formatters.formatCPFOrCNPJ(input.document),
            phone: normalizedPhoneDisplay(input.phone),
            isActive: true,
            type: input.type,
            status: "ATIVA",
            addressSummary: localAddressSummary(cep: input.cep, number: input.number, complement: input.complement),
            responsibleName: session.displayName
        ) else {
            throw PortalDirectoryServiceError.invalidContext("Não encontrei dados suficientes para cadastrar a empresa localmente.")
        }

        return makeCompanyRecord(from: localCompany)
    }

    /// Aqui eu atualizo a empresa pelo mesmo contrato do backend; documento e tipo permanecem imutáveis.
    func updateCompany(companyID: String, input: PortalCompanyFormInput) async throws -> PortalCompanyRecord {
        if isRemoteMode {
            let address = try makeRequiredAddressRequest(
                cep: input.cep,
                number: input.number,
                complement: input.complement,
                errorMessage: "Informe CEP e número da empresa para salvar a edição remota."
            )

            let response: CompanyResponse = try await apiClient.request(
                target: .backend,
                path: APIRoutes.Empresas.byID(companyID),
                method: "PUT",
                body: CompanyUpdateRequest(
                    nome: normalizedName(input.name),
                    telefone: normalizedPhone(input.phone),
                    endereco: address
                )
            )

            let company = makeCompanyRecord(from: response)
            persistCompanyLocally(company)
            return company
        }

        guard let localCompany = dataStore.upsertCompany(
            id: companyID,
            name: normalizedName(input.name),
            document: Formatters.formatCPFOrCNPJ(input.document),
            phone: normalizedPhoneDisplay(input.phone),
            isActive: true,
            type: input.type,
            status: "ATIVA",
            addressSummary: localAddressSummary(cep: input.cep, number: input.number, complement: input.complement)
        ) else {
            throw PortalDirectoryServiceError.invalidContext("Não encontrei a empresa local para atualizar.")
        }

        return makeCompanyRecord(from: localCompany)
    }

    /// Aqui eu sigo o ciclo de vida real das empresas: ativar, suspender ou bloquear.
    func updateCompanyLifecycle(companyID: String, action: PortalCompanyLifecycleAction) async throws -> PortalCompanyRecord {
        if isRemoteMode {
            let path: String
            let method: String

            switch action {
            case .activate:
                path = APIRoutes.Empresas.ativar(companyID)
                method = "PUT"
            case .suspend:
                path = APIRoutes.Empresas.suspender(companyID)
                method = "DELETE"
            case .block:
                path = APIRoutes.Empresas.bloquear(companyID)
                method = "DELETE"
            }

            try await apiClient.sendVoid(
                target: .backend,
                path: path,
                method: method
            )

            let refreshed: CompanyResponse = try await apiClient.request(
                target: .backend,
                path: APIRoutes.Empresas.byID(companyID)
            )

            let company = makeCompanyRecord(from: refreshed)
            persistCompanyLocally(company)
            return company
        }

        let localStatus: String
        let isActive: Bool
        let auditAction: String

        switch action {
        case .activate:
            localStatus = "ATIVA"
            isActive = true
            auditAction = "ativar_empresa"
        case .suspend:
            localStatus = "SUSPENSO"
            isActive = false
            auditAction = "suspender_empresa"
        case .block:
            localStatus = "BLOQUEADO"
            isActive = false
            auditAction = "bloquear_empresa"
        }

        guard let localCompany = dataStore.updateCompanyLifecycle(
            companyID: companyID,
            isActive: isActive,
            status: localStatus,
            auditAction: auditAction
        ) else {
            throw PortalDirectoryServiceError.invalidContext("Não encontrei a empresa local para atualizar o status.")
        }

        return makeCompanyRecord(from: localCompany)
    }

    /// Aqui eu listo os devedores pelo endpoint certo da empresa e uso o global só para perfis admin sem empresa vinculada.
    func listDebtors(
        session: AuthSession,
        searchName: String? = nil,
        companyID: String? = nil
    ) async throws -> [PortalDebtorRecord] {
        if isRemoteMode {
            if let effectiveCompanyID = resolvedCompanyID(session: session, explicitCompanyID: companyID) {
                let response: PaginatedResponse<DebtorResponse> = try await apiClient.request(
                    target: .backend,
                    path: makePagedPath(
                        basePath: APIRoutes.Empresas.devedores(effectiveCompanyID),
                        page: 0,
                        size: 60,
                        additionalQueryItems: [URLQueryItem(name: "nome", value: searchName?.nilIfEmpty)]
                    )
                )
                let debtors = response.content.map(makeDebtorRecord(from:))
                persistDebtorsLocally(debtors)
                return debtors
            }

            if session.isAdminLike {
                let response: PaginatedResponse<DebtorResponse> = try await apiClient.request(
                    target: .backend,
                    path: makePagedPath(
                        basePath: APIRoutes.Devedores.base,
                        page: 0,
                        size: 60,
                        additionalQueryItems: [URLQueryItem(name: "nome", value: searchName?.nilIfEmpty)]
                    )
                )
                let debtors = response.content.map(makeDebtorRecord(from:))
                persistDebtorsLocally(debtors)
                return debtors
            }
        }

        return makeLocalDebtorRecords(searchName: searchName)
    }

    /// Aqui eu crio o devedor usando a empresa da sessão ou a empresa escolhida no formulário.
    func createDebtor(session: AuthSession, input: PortalDebtorFormInput) async throws -> PortalDebtorRecord {
        let effectiveCompanyID = try resolvedCompanyIDForWrite(session: session, explicitCompanyID: input.companyID)

        if isRemoteMode {
            let response: DebtorResponse = try await apiClient.request(
                target: .backend,
                path: APIRoutes.Empresas.devedores(effectiveCompanyID),
                method: "POST",
                body: DebtorCreateRequest(
                    nome: normalizedName(input.name),
                    cpfCnpjEnc: normalizedDocument(input.document),
                    email: normalizedEmail(input.email),
                    telefone: normalizedPhone(input.phone),
                    endereco: try makeRequiredAddressRequest(
                        cep: input.cep,
                        number: input.number,
                        complement: input.complement,
                        errorMessage: "Informe CEP e número do devedor para concluir o cadastro."
                    )
                )
            )

            let debtor = makeDebtorRecord(from: response)
            persistDebtorLocally(debtor)
            return debtor
        }

        guard let localDebtor = dataStore.upsertDebtor(
            name: normalizedName(input.name),
            document: Formatters.formatCPFOrCNPJ(input.document),
            email: normalizedEmail(input.email),
            phone: normalizedPhoneDisplay(input.phone),
            status: "Ativo",
            companyID: effectiveCompanyID,
            companyName: localCompanyName(for: effectiveCompanyID),
            addressSummary: localAddressSummary(cep: input.cep, number: input.number, complement: input.complement)
        ) else {
            throw PortalDirectoryServiceError.invalidContext("Não encontrei dados suficientes para cadastrar o devedor localmente.")
        }

        return makeDebtorRecord(from: localDebtor)
    }

    /// Aqui eu atualizo o devedor pelo endpoint de empresa para seguir exatamente o backend atual.
    func updateDebtor(session: AuthSession, debtorID: String, input: PortalDebtorFormInput) async throws -> PortalDebtorRecord {
        let effectiveCompanyID = try resolvedCompanyIDForWrite(session: session, explicitCompanyID: input.companyID)

        if isRemoteMode {
            let response: DebtorResponse = try await apiClient.request(
                target: .backend,
                path: "\(APIRoutes.Empresas.devedores(effectiveCompanyID))/\(debtorID)",
                method: "PUT",
                body: DebtorUpdateRequest(
                    nome: normalizedName(input.name),
                    telefone: normalizedPhone(input.phone),
                    endereco: try makeRequiredAddressRequest(
                        cep: input.cep,
                        number: input.number,
                        complement: input.complement,
                        errorMessage: "Informe CEP e número do devedor para salvar a edição."
                    )
                )
            )

            let debtor = makeDebtorRecord(from: response)
            persistDebtorLocally(debtor)
            return debtor
        }

        guard let localDebtor = dataStore.upsertDebtor(
            id: debtorID,
            name: normalizedName(input.name),
            document: Formatters.formatCPFOrCNPJ(input.document),
            email: normalizedEmail(input.email),
            phone: normalizedPhoneDisplay(input.phone),
            status: "Ativo",
            companyID: effectiveCompanyID,
            companyName: localCompanyName(for: effectiveCompanyID),
            addressSummary: localAddressSummary(cep: input.cep, number: input.number, complement: input.complement)
        ) else {
            throw PortalDirectoryServiceError.invalidContext("Não encontrei o devedor local para atualizar.")
        }

        return makeDebtorRecord(from: localDebtor)
    }

    /// Aqui eu uso as rotas por empresa do backend para ativar ou bloquear devedores, sem cair na rota global incorreta.
    func updateDebtorLifecycle(
        session: AuthSession,
        debtorID: String,
        companyID: String?,
        action: PortalDebtorLifecycleAction
    ) async throws -> PortalDebtorRecord {
        let effectiveCompanyID = try resolvedCompanyIDForWrite(session: session, explicitCompanyID: companyID)

        if isRemoteMode {
            let path: String
            let method: String

            switch action {
            case .activate:
                path = APIRoutes.Empresas.ativarDevedor(effectiveCompanyID, debtorID)
                method = "PUT"
            case .block:
                path = APIRoutes.Empresas.bloquearDevedor(effectiveCompanyID, debtorID)
                method = "DELETE"
            }

            try await apiClient.sendVoid(
                target: .backend,
                path: path,
                method: method
            )

            let refreshed: DebtorResponse = try await apiClient.request(
                target: .backend,
                path: APIRoutes.Devedores.byID(debtorID)
            )

            let debtor = makeDebtorRecord(from: refreshed)
            persistDebtorLocally(debtor)
            return debtor
        }

        let localStatus: String
        let auditAction: String

        switch action {
        case .activate:
            localStatus = "ATIVO"
            auditAction = "ativar_devedor"
        case .block:
            localStatus = "BLOQUEADO"
            auditAction = "bloquear_devedor"
        }

        guard let localDebtor = dataStore.updateDebtorLifecycle(
            debtorID: debtorID,
            status: localStatus,
            auditAction: auditAction
        ) else {
            throw PortalDirectoryServiceError.invalidContext("Não encontrei o devedor local para atualizar o status.")
        }

        return makeDebtorRecord(from: localDebtor)
    }

    private func resolvedCompanyID(session: AuthSession, explicitCompanyID: String?) -> String? {
        explicitCompanyID?.nilIfEmpty ?? session.empresaID?.nilIfEmpty
    }

    private func resolvedCompanyIDForWrite(session: AuthSession, explicitCompanyID: String?) throws -> String {
        if let effectiveCompanyID = resolvedCompanyID(session: session, explicitCompanyID: explicitCompanyID) {
            return effectiveCompanyID
        }

        throw PortalDirectoryServiceError.invalidContext("Selecione a empresa responsável antes de salvar o devedor.")
    }

    private func makePagedPath(
        basePath: String,
        page: Int,
        size: Int,
        additionalQueryItems: [URLQueryItem] = []
    ) -> String {
        var components = URLComponents()
        components.path = basePath
        components.queryItems = [
            URLQueryItem(name: "page", value: String(max(0, page))),
            URLQueryItem(name: "size", value: String(max(1, size)))
        ] + additionalQueryItems.filter { $0.value?.isEmpty == false }
        return components.string ?? components.path
    }

    private func makeCompanyRecord(from response: CompanyResponse) -> PortalCompanyRecord {
        PortalCompanyRecord(
            id: response.id,
            name: response.nome?.nilIfEmpty ?? "Empresa sem nome",
            document: response.cpfCnpj?.nilIfEmpty ?? "",
            phone: response.telefone?.nilIfEmpty ?? "",
            type: response.tipo?.nilIfEmpty ?? "PESSOA_JURIDICA",
            status: response.status?.nilIfEmpty ?? "ATIVA",
            responsibleID: response.responsavel?.id?.nilIfEmpty,
            responsibleName: response.responsavel?.nome?.nilIfEmpty,
            address: makeAddress(from: response.endereco),
            addressSummary: makeAddress(from: response.endereco)?.summary,
            pixKey: response.chavePix?.nilIfEmpty,
            pixKeyType: response.tipoChavePix?.nilIfEmpty
        )
    }

    private func makeDebtorRecord(from response: DebtorResponse) -> PortalDebtorRecord {
        PortalDebtorRecord(
            id: response.id,
            companyID: response.empresa?.id?.nilIfEmpty,
            companyName: response.empresa?.nome?.nilIfEmpty,
            name: response.nome?.nilIfEmpty ?? "Devedor sem nome",
            document: response.cpfCnpjEnc?.nilIfEmpty ?? "",
            email: response.email?.nilIfEmpty ?? "",
            phone: response.telefone?.nilIfEmpty ?? "",
            status: response.status?.nilIfEmpty ?? "ATIVO",
            address: makeAddress(from: response.endereco),
            addressSummary: makeAddress(from: response.endereco)?.summary
        )
    }

    private func makeAddress(from payload: CompanyResponse.AddressPayload?) -> PortalDirectoryAddress? {
        guard let payload else { return nil }
        return makeAddress(
            cep: payload.cep,
            logradouro: payload.logradouro,
            numero: payload.numero,
            complemento: payload.complemento,
            bairro: payload.bairro,
            cidade: payload.cidade,
            estado: payload.estado
        )
    }

    private func makeAddress(from payload: DebtorResponse.AddressPayload?) -> PortalDirectoryAddress? {
        guard let payload else { return nil }
        return makeAddress(
            cep: payload.cep,
            logradouro: payload.logradouro,
            numero: payload.numero,
            complemento: payload.complemento,
            bairro: payload.bairro,
            cidade: payload.cidade,
            estado: payload.estado
        )
    }

    private func makeAddress(
        cep: String?,
        logradouro: String?,
        numero: String?,
        complemento: String?,
        bairro: String?,
        cidade: String?,
        estado: String?
    ) -> PortalDirectoryAddress? {
        guard
            let cep = cep?.nilIfEmpty,
            let logradouro = logradouro?.nilIfEmpty,
            let numero = numero?.nilIfEmpty,
            let bairro = bairro?.nilIfEmpty,
            let cidade = cidade?.nilIfEmpty,
            let estado = estado?.nilIfEmpty
        else {
            return nil
        }

        return PortalDirectoryAddress(
            cep: cep,
            logradouro: logradouro,
            numero: numero,
            complemento: complemento?.nilIfEmpty,
            bairro: bairro,
            cidade: cidade,
            estado: estado
        )
    }

    private func makeOptionalAddressRequest(cep: String?, number: String?, complement: String?) -> AddressRequest? {
        guard let cep = cep?.nilIfEmpty, let number = number?.nilIfEmpty else { return nil }
        return AddressRequest(
            cep: Formatters.digitsOnly(cep),
            numero: number,
            complemento: complement?.nilIfEmpty
        )
    }

    private func makeRequiredAddressRequest(
        cep: String?,
        number: String?,
        complement: String?,
        errorMessage: String
    ) throws -> AddressRequest {
        guard let request = makeOptionalAddressRequest(cep: cep, number: number, complement: complement) else {
            throw PortalDirectoryServiceError.invalidContext(errorMessage)
        }
        return request
    }

    private func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedDocument(_ value: String) -> String {
        Formatters.digitsOnly(value)
    }

    private func normalizedPhone(_ value: String) -> String {
        Formatters.digitsOnly(value)
    }

    private func normalizedPhoneDisplay(_ value: String) -> String {
        let digits = Formatters.digitsOnly(value)
        return digits.count <= 10 ? Self.formatPhone10(digits) : Self.formatPhone11(digits)
    }

    private func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func localAddressSummary(cep: String?, number: String?, complement: String?) -> String? {
        guard let cep = cep?.nilIfEmpty, let number = number?.nilIfEmpty else { return nil }
        let pieces = ["CEP \(Formatters.formatCEP(cep))", "Número \(number)", complement?.nilIfEmpty]
        return pieces.compactMap { $0 }.joined(separator: " • ")
    }

    private func localCompanyName(for companyID: String?) -> String? {
        guard let companyID = companyID?.nilIfEmpty else { return nil }
        return dataStore.fetchCompanies().first(where: { $0.id == companyID })?.nome
    }

    private func makeLocalCompanyRecords(searchName: String?) -> [PortalCompanyRecord] {
        let query = searchName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return dataStore.fetchCompanies()
            .filter { item in
                guard let query, query.isEmpty == false else { return true }
                return item.nome.lowercased().contains(query)
            }
            .map(makeCompanyRecord(from:))
    }

    private func makeLocalDebtorRecords(searchName: String?) -> [PortalDebtorRecord] {
        let query = searchName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return dataStore.fetchDebtors()
            .filter { item in
                guard let query, query.isEmpty == false else { return true }
                return item.nome.lowercased().contains(query)
            }
            .map(makeDebtorRecord(from:))
    }

    private func persistCompaniesLocally(_ companies: [PortalCompanyRecord]) {
        companies.forEach(persistCompanyLocally)
    }

    private func persistCompanyLocally(_ company: PortalCompanyRecord) {
        _ = dataStore.upsertCompany(
            id: company.id,
            name: company.name,
            document: Formatters.formatCPFOrCNPJ(company.document),
            phone: normalizedPhoneDisplay(company.phone),
            isActive: company.isActive,
            type: company.type,
            status: company.status,
            addressSummary: company.address?.summary,
            responsibleName: company.responsibleName
        )
    }

    private func persistDebtorsLocally(_ debtors: [PortalDebtorRecord]) {
        debtors.forEach(persistDebtorLocally)
    }

    private func persistDebtorLocally(_ debtor: PortalDebtorRecord) {
        _ = dataStore.upsertDebtor(
            id: debtor.id,
            name: debtor.name,
            document: Formatters.formatCPFOrCNPJ(debtor.document),
            email: debtor.email,
            phone: normalizedPhoneDisplay(debtor.phone),
            status: debtor.status,
            companyID: debtor.companyID,
            companyName: debtor.companyName,
            addressSummary: debtor.address?.summary
        )
    }

    private func makeCompanyRecord(from item: CompanyItem) -> PortalCompanyRecord {
        PortalCompanyRecord(
            id: item.id,
            name: item.nome,
            document: item.documento,
            phone: item.telefone,
            type: item.tipo ?? "PESSOA_JURIDICA",
            status: item.status ?? (item.ativa ? "ATIVA" : "INATIVA"),
            responsibleID: nil,
            responsibleName: item.responsibleName,
            address: nil,
            addressSummary: item.addressSummary,
            pixKey: nil,
            pixKeyType: nil
        )
    }

    private func makeDebtorRecord(from item: DebtorItem) -> PortalDebtorRecord {
        PortalDebtorRecord(
            id: item.id,
            companyID: item.companyID,
            companyName: item.companyName,
            name: item.nome,
            document: item.cpfCnpj,
            email: item.email,
            phone: item.telefone,
            status: item.status,
            address: nil,
            addressSummary: item.addressSummary
        )
    }

    private static func formatPhone10(_ digits: String) -> String {
        guard digits.isEmpty == false else { return "" }
        let raw = String(digits.prefix(10))
        if raw.count < 3 { return raw }
        if raw.count < 7 {
            return "(\(raw.prefix(2))) \(raw.dropFirst(2))"
        }

        let prefix = raw.prefix(2)
        let middle = raw.dropFirst(2).prefix(4)
        let suffix = raw.dropFirst(6)
        return "(\(prefix)) \(middle)-\(suffix)"
    }

    private static func formatPhone11(_ digits: String) -> String {
        guard digits.isEmpty == false else { return "" }
        let raw = String(digits.prefix(11))
        if raw.count < 3 { return raw }
        if raw.count < 8 {
            return "(\(raw.prefix(2))) \(raw.dropFirst(2))"
        }

        let prefix = raw.prefix(2)
        let middle = raw.dropFirst(2).prefix(5)
        let suffix = raw.dropFirst(7)
        return "(\(prefix)) \(middle)-\(suffix)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
