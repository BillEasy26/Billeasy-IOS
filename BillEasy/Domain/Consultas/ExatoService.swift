//
//  ExatoService.swift
//  BillEasy
//

import Foundation

struct ExatoAddress {
    let logradouro: String?
    let numero: String?
    let complemento: String?
    let bairro: String?
    let municipio: String?
    let uf: String?
    let cep: String?

    var primaryLine: String {
        [logradouro, numero, complemento]
            .compactMap { $0?.nilIfEmpty }
            .joined(separator: ", ")
    }

    var secondaryLine: String {
        var components: [String] = []

        if let bairro = bairro?.nilIfEmpty {
            components.append(bairro)
        }

        if let cityState = cityState {
            components.append(cityState)
        }

        if let formattedCEP = cep?.formattedCEP.nilIfEmpty {
            components.append("CEP: \(formattedCEP)")
        }

        return components.joined(separator: " — ")
    }

    var cityState: String? {
        let city = municipio?.nilIfEmpty
        let state = uf?.nilIfEmpty

        switch (city, state) {
        case let (.some(city), .some(state)):
            return "\(city)/\(state)"
        case let (.some(city), .none):
            return city
        case let (.none, .some(state)):
            return state
        default:
            return nil
        }
    }
}

struct ExatoPhone {
    let number: String
    let type: String?
}

struct ExatoPessoaFisicaResult {
    let cpf: String
    let nome: String
    let idade: String?
    let sexo: String?
    let dataNascimento: String?
    let nomeMae: String?
    let situacaoCadastralReceita: String?
    let obitoRegistrado: Bool
    let enderecos: [ExatoAddress]
    let celulares: [ExatoPhone]
}

struct ExatoCreditScore {
    let pontuacao: Int?
    let faixa: String?
    let riscoNivel: String?
    let riscoDescricao: String?
    let comprometimentoPagamento: String?
    let descricaoComprometimentoPagamento: String?
    let pontuacaoPerfil: String?
    let descricaoPontuacaoPerfil: String?
}

struct ExatoCompanyLink {
    let nomeEmpresa: String?
    let cnpj: String?
    let tipo: String?
    let percentualParticipacao: String?
    let statusCNPJ: String?
    let dataInicio: String?
}

struct ExatoProtest {
    let dataConsulta: String?
    let cartorio: String?
    let valor: String?
    let cidade: String?
    let uf: String?
}

struct ExatoAnaliseCreditoResult {
    let cpf: String
    let nome: String
    let statusCPF: String?
    let idade: String?
    let genero: String?
    let emailPrincipal: String?
    let score: ExatoCreditScore?
    let empresasVinculadas: [ExatoCompanyLink]
    let protestos: [ExatoProtest]
}

enum ExatoServiceError: LocalizedError {
    case integrationUnavailable
    case invalidCPF
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .integrationUnavailable:
            return "Consulta Exato disponível apenas no modo remoto autenticado."
        case .invalidCPF:
            return "Informe um CPF válido com 11 dígitos."
        case .emptyResult:
            return "Nenhum dado relevante foi retornado pela Exato."
        }
    }
}

final class ExatoService {
    private struct CPFRequest: Encodable {
        let cpf: String
    }

    private let apiClient: RemoteAPIClient
    private let mode: AppAuthMode

    init(
        apiClient: RemoteAPIClient = RemoteAPIClient(),
        mode: AppAuthMode = AppRuntimeConfiguration.authMode
    ) {
        self.apiClient = apiClient
        self.mode = mode
    }

    var isRemoteIntegrationEnabled: Bool {
        mode == .remote
    }

    func consultarPessoaFisica(cpf: String) async throws -> ExatoPessoaFisicaResult {
        guard isRemoteIntegrationEnabled else {
            throw ExatoServiceError.integrationUnavailable
        }

        let normalizedCPF = try normalizeCPF(cpf)
        let response: PessoaFisicaResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Exato.pessoaFisica,
            method: "POST",
            body: CPFRequest(cpf: normalizedCPF)
        )

        guard let pessoa = response.pessoa else {
            throw ExatoServiceError.emptyResult
        }

        let addresses = response.enderecos.compactMap { $0.asDomainAddress }
        let phones = response.celulares.compactMap { $0.asDomainPhone }

        return ExatoPessoaFisicaResult(
            cpf: pessoa.cpf ?? normalizedCPF,
            nome: pessoa.nome ?? "Pessoa consultada",
            idade: pessoa.idade,
            sexo: pessoa.sexo,
            dataNascimento: pessoa.nascimentoData?.asDisplayDate,
            nomeMae: pessoa.maeNome,
            situacaoCadastralReceita: pessoa.receitaSituacaoCadastral,
            obitoRegistrado: pessoa.obito ?? false,
            enderecos: addresses,
            celulares: phones
        )
    }

    func analisarCredito(cpf: String) async throws -> ExatoAnaliseCreditoResult {
        guard isRemoteIntegrationEnabled else {
            throw ExatoServiceError.integrationUnavailable
        }

        let normalizedCPF = try normalizeCPF(cpf)
        let response: AnaliseCreditoResponse = try await apiClient.request(
            target: .backend,
            path: APIRoutes.Exato.analiseCredito,
            method: "POST",
            body: CPFRequest(cpf: normalizedCPF)
        )

        guard let registro = response.registros?.registro.first else {
            throw ExatoServiceError.emptyResult
        }

        let melhoresInformacoes = registro.melhoresInformacoes
        let scorePayload = registro.pontuacaoCredito
        let riskPayload = scorePayload?.razaoPontuacao?.risco

        let score = ExatoCreditScore(
            pontuacao: scorePayload?.pontuacao,
            faixa: scorePayload?.razaoPontuacao?.faixa,
            riscoNivel: riskPayload?.nivel,
            riscoDescricao: riskPayload?.descricao,
            comprometimentoPagamento: scorePayload?.comprometimentoPagamento,
            descricaoComprometimentoPagamento: scorePayload?.descricaoComprometimentoPagamento,
            pontuacaoPerfil: scorePayload?.pontuacaoPerfil,
            descricaoPontuacaoPerfil: scorePayload?.descricaoPontuacaoPerfil
        )

        let empresas = registro.dadosEmpresa?.parcerias?.parceria.compactMap { partnership in
            ExatoCompanyLink(
                nomeEmpresa: partnership.nomeEmpresa,
                cnpj: partnership.cnpj,
                tipo: partnership.descricaoRelacionamento ?? partnership.tipoEntidade,
                percentualParticipacao: partnership.percentualParticipacao,
                statusCNPJ: partnership.statusCNPJ,
                dataInicio: partnership.dataInicioParceria?.displayValue
            )
        } ?? []

        let protests = registro.protestos?.protesto.compactMap { protest in
            ExatoProtest(
                dataConsulta: protest.dataConsulta?.nilIfEmpty,
                cartorio: protest.cartorio?.nilIfEmpty,
                valor: protest.valor?.nilIfEmpty,
                cidade: protest.cidade?.nilIfEmpty,
                uf: protest.uf?.nilIfEmpty
            )
        } ?? []

        return ExatoAnaliseCreditoResult(
            cpf: melhoresInformacoes?.cpf ?? normalizedCPF,
            nome: melhoresInformacoes?.nomeCompleto ?? "Pessoa consultada",
            statusCPF: melhoresInformacoes?.statusCPF,
            idade: melhoresInformacoes?.idade,
            genero: melhoresInformacoes?.genero,
            emailPrincipal: melhoresInformacoes?.emailPrincipal,
            score: score,
            empresasVinculadas: empresas,
            protestos: protests
        )
    }

    private func normalizeCPF(_ cpf: String) throws -> String {
        let digits = cpf.filter(\.isNumber)
        guard digits.count == 11 else {
            throw ExatoServiceError.invalidCPF
        }
        return digits
    }
}

// MARK: - Pessoa física

private struct PessoaFisicaResponse: Decodable {
    let pessoa: PessoaFisicaPayload?
    let enderecos: [PessoaEndereco]
    let celulares: [PessoaCelular]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pessoa = try container.decodeIfPresent(PessoaFisicaPayload.self, forKey: .pessoa)
        enderecos = try container.decodeIfPresent([PessoaEndereco].self, forKey: .enderecos) ?? []
        celulares = try container.decodeIfPresent([PessoaCelular].self, forKey: .celulares) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case pessoa
        case enderecos
        case celulares
    }
}

private struct PessoaFisicaPayload: Decodable {
    let cpf: String?
    let nome: String?
    let nascimentoData: String?
    let idade: String?
    let sexo: String?
    let maeNome: String?
    let obito: Bool?
    let receitaSituacaoCadastral: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpf = container.decodeFlexibleString(forKey: .cpf)
        nome = container.decodeFlexibleString(forKey: .nome)
        nascimentoData = container.decodeFlexibleString(forKey: .nascimentoData)
        idade = container.decodeFlexibleString(forKey: .idade)
        sexo = container.decodeFlexibleString(forKey: .sexo)
        maeNome = container.decodeFlexibleString(forKey: .maeNome)
        obito = container.decodeFlexibleBool(forKey: .obito)
        receitaSituacaoCadastral = container.decodeFlexibleString(forKey: .receitaSituacaoCadastral)
    }

    private enum CodingKeys: String, CodingKey {
        case cpf
        case nome
        case nascimentoData
        case idade
        case sexo
        case maeNome
        case obito
        case receitaSituacaoCadastral
    }
}

private struct PessoaEndereco: Decodable {
    let tipoLogradouro: String?
    let logradouro: String?
    let numero: String?
    let complemento: String?
    let bairro: String?
    let municipio: String?
    let uf: String?
    let cep: String?

    var asDomainAddress: ExatoAddress? {
        let address = ExatoAddress(
            logradouro: [tipoLogradouro, logradouro].compactMap { $0?.nilIfEmpty }.joined(separator: " ").nilIfEmpty,
            numero: numero?.nilIfEmpty,
            complemento: complemento?.nilIfEmpty,
            bairro: bairro?.nilIfEmpty,
            municipio: municipio?.nilIfEmpty,
            uf: uf?.nilIfEmpty,
            cep: cep?.nilIfEmpty
        )

        return address.primaryLine.isEmpty && address.secondaryLine.isEmpty ? nil : address
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tipoLogradouro = container.decodeFlexibleString(forKey: .tipoLogradouro)
        logradouro = container.decodeFlexibleString(forKey: .logradouro)
        numero = container.decodeFlexibleString(forKey: .numero)
        complemento = container.decodeFlexibleString(forKey: .complemento)
        bairro = container.decodeFlexibleString(forKey: .bairro)
        municipio = container.decodeFlexibleString(forKey: .municipio)
        uf = container.decodeFlexibleString(forKey: .uf)
        cep = container.decodeFlexibleString(forKey: .cep)
    }

    private enum CodingKeys: String, CodingKey {
        case tipoLogradouro
        case logradouro
        case numero
        case complemento
        case bairro
        case municipio
        case uf
        case cep
    }
}

private struct PessoaCelular: Decodable {
    let ddd: String?
    let numero: String?
    let telefoneTipoId: String?

    var asDomainPhone: ExatoPhone? {
        let digits = [ddd, numero].compactMap { $0?.nilIfEmpty }.joined()
        guard let value = digits.nilIfEmpty else { return nil }

        return ExatoPhone(
            number: value.formattedPhone,
            type: telefoneTipoId?.nilIfEmpty
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ddd = container.decodeFlexibleString(forKey: .ddd)
        numero = container.decodeFlexibleString(forKey: .numero)
        telefoneTipoId = container.decodeFlexibleString(forKey: .telefoneTipoId)
    }

    private enum CodingKeys: String, CodingKey {
        case ddd
        case numero
        case telefoneTipoId
    }
}

// MARK: - Análise de crédito

private struct AnaliseCreditoResponse: Decodable {
    let registros: AnaliseRegistros?
}

private struct AnaliseRegistros: Decodable {
    let registro: [AnaliseRegistro]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        registro = try container.decodeIfPresent([AnaliseRegistro].self, forKey: .registro) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case registro
    }
}

private struct AnaliseRegistro: Decodable {
    let melhoresInformacoes: AnaliseMelhoresInformacoes?
    let pontuacaoCredito: AnalisePontuacaoCredito?
    let dadosEmpresa: AnaliseDadosEmpresa?
    let protestos: AnaliseProtests?
}

private struct AnaliseMelhoresInformacoes: Decodable {
    let cpf: String?
    let statusCPF: String?
    let nomeCompleto: String?
    let idade: String?
    let genero: String?
    let emailPrincipal: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpf = container.decodeFlexibleString(forKey: .cpf)
        statusCPF = container.decodeFlexibleString(forKey: .statusCPF)
        idade = container.decodeFlexibleString(forKey: .idade)
        genero = container.decodeFlexibleString(forKey: .genero)
        emailPrincipal = try container.nestedStringValue(forKey: .email, nestedKeys: [AnyCodingKey("valorEmail")])
        nomeCompleto = try container.nestedStringValue(
            forKey: .nomePessoa,
            nestedKeys: [AnyCodingKey("nome"), AnyCodingKey("completo")]
        )
    }

    private enum CodingKeys: String, CodingKey {
        case cpf
        case statusCPF
        case nomePessoa
        case idade
        case genero
        case email
    }
}

private struct AnalisePontuacaoCredito: Decodable {
    let pontuacao: Int?
    let razaoPontuacao: AnaliseRazaoPontuacao?
    let comprometimentoPagamento: String?
    let descricaoComprometimentoPagamento: String?
    let pontuacaoPerfil: String?
    let descricaoPontuacaoPerfil: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pontuacao = container.decodeFlexibleInt(forKey: .pontuacao)
        razaoPontuacao = try container.decodeIfPresent(AnaliseRazaoPontuacao.self, forKey: .razaoPontuacao)
        comprometimentoPagamento = container.decodeFlexibleString(forKey: .comprometimentoPagamento)
        descricaoComprometimentoPagamento = container.decodeFlexibleString(forKey: .descricaoComprometimentoPagamento)
        pontuacaoPerfil = container.decodeFlexibleString(forKey: .pontuacaoPerfil)
        descricaoPontuacaoPerfil = container.decodeFlexibleString(forKey: .descricaoPontuacaoPerfil)
    }

    private enum CodingKeys: String, CodingKey {
        case pontuacao
        case razaoPontuacao
        case comprometimentoPagamento
        case descricaoComprometimentoPagamento
        case pontuacaoPerfil
        case descricaoPontuacaoPerfil
    }
}

private struct AnaliseRazaoPontuacao: Decodable {
    let faixa: String?
    let risco: AnaliseRisco?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        faixa = container.decodeFlexibleString(forKey: .faixa)
        risco = try container.decodeIfPresent(AnaliseRisco.self, forKey: .risco)
    }

    private enum CodingKeys: String, CodingKey {
        case faixa
        case risco
    }
}

private struct AnaliseRisco: Decodable {
    let nivel: String?
    let descricao: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nivel = container.decodeFlexibleString(forKey: .nivel)
        descricao = container.decodeFlexibleString(forKey: .descricao)
    }

    private enum CodingKeys: String, CodingKey {
        case nivel
        case descricao
    }
}

private struct AnaliseDadosEmpresa: Decodable {
    let parcerias: AnaliseParcerias?
}

private struct AnaliseParcerias: Decodable {
    let parceria: [AnaliseParceria]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        parceria = try container.decodeIfPresent([AnaliseParceria].self, forKey: .parceria) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case parceria
    }
}

private struct AnaliseParceria: Decodable {
    let tipoEntidade: String?
    let cnpj: String?
    let nomeEmpresa: String?
    let statusCNPJ: String?
    let percentualParticipacao: String?
    let valorParticipacao: String?
    let descricaoRelacionamento: String?
    let dataInicioParceria: AnaliseDateParts?
    let dataReferencia: AnaliseDateParts?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tipoEntidade = container.decodeFlexibleString(forKey: .tipoEntidade)
        cnpj = container.decodeFlexibleString(forKey: .cnpj)
        nomeEmpresa = container.decodeFlexibleString(forKey: .nomeEmpresa)
        statusCNPJ = container.decodeFlexibleString(forKey: .statusCNPJ)
        percentualParticipacao = container.decodeFlexibleString(forKey: .percentualParticipacao)
        valorParticipacao = container.decodeFlexibleString(forKey: .valorParticipacao)
        descricaoRelacionamento = container.decodeFlexibleString(forKey: .descricaoRelacionamento)
        dataInicioParceria = try container.decodeIfPresent(AnaliseDateParts.self, forKey: .dataInicioParceria)
        dataReferencia = try container.decodeIfPresent(AnaliseDateParts.self, forKey: .dataReferencia)
    }

    private enum CodingKeys: String, CodingKey {
        case tipoEntidade
        case cnpj
        case nomeEmpresa
        case statusCNPJ
        case percentualParticipacao
        case valorParticipacao
        case descricaoRelacionamento
        case dataInicioParceria
        case dataReferencia
    }
}

private struct AnaliseProtests: Decodable {
    let protesto: [AnaliseProtest]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protesto = try container.decodeIfPresent([AnaliseProtest].self, forKey: .protesto) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case protesto
    }
}

private struct AnaliseProtest: Decodable {
    let dataConsulta: String?
    let cartorio: String?
    let valor: String?
    let cidade: String?
    let uf: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dataConsulta = container.decodeFlexibleString(forKey: .dataConsulta)
            ?? container.decodeFlexibleString(forKey: .dataConsultaLegacy)
        cartorio = container.decodeFlexibleString(forKey: .cartorio)
        valor = container.decodeFlexibleString(forKey: .valor)
        cidade = container.decodeFlexibleString(forKey: .cidade)
        uf = container.decodeFlexibleString(forKey: .uf)
    }

    private enum CodingKeys: String, CodingKey {
        case dataConsulta
        case dataConsultaLegacy = "data_consulta"
        case cartorio
        case valor
        case cidade
        case uf
    }
}

private struct AnaliseDateParts: Decodable {
    let ano: String?
    let mes: String?
    let dia: String?

    var displayValue: String? {
        guard
            let day = dia?.nilIfEmpty,
            let month = mes?.nilIfEmpty,
            let year = ano?.nilIfEmpty
        else {
            return nil
        }

        let paddedDay = day.count == 1 ? "0\(day)" : day
        let paddedMonth = month.count == 1 ? "0\(month)" : month
        return "\(paddedDay)/\(paddedMonth)/\(year)"
    }
}

// MARK: - Helpers

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) {
            return value.nilIfEmpty
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeFlexibleBool(forKey key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "1", "sim":
                return true
            case "false", "0", "nao", "não":
                return false
            default:
                return nil
            }
        }
        if let value = try? decode(Int.self, forKey: key) {
            return value != 0
        }
        return nil
    }

    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func nestedStringValue(forKey key: Key, nestedKeys: [AnyCodingKey]) throws -> String? {
        guard contains(key) else { return nil }
        var container = try nestedContainer(keyedBy: AnyCodingKey.self, forKey: key)

        for nestedKey in nestedKeys.dropLast() {
            guard container.contains(nestedKey) else { return nil }
            container = try container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: nestedKey)
        }

        guard let lastKey = nestedKeys.last else { return nil }
        if let value = try? container.decode(String.self, forKey: lastKey) {
            return value.nilIfEmpty
        }
        if let value = try? container.decode(Int.self, forKey: lastKey) {
            return String(value)
        }
        if let value = try? container.decode(Int64.self, forKey: lastKey) {
            return String(value)
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var formattedCEP: String {
        let digits = filter(\.isNumber)
        guard digits.count == 8 else { return self }

        var formatted = ""
        for (index, char) in digits.enumerated() {
            if index == 5 { formatted.append("-") }
            formatted.append(char)
        }
        return formatted
    }

    var formattedPhone: String {
        let digits = filter(\.isNumber)
        guard !digits.isEmpty else { return self }

        var result = ""
        for (index, char) in digits.prefix(11).enumerated() {
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

    var asDisplayDate: String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: self) {
            return Formatters.shortDate.string(from: date)
        }
        return self
    }
}
