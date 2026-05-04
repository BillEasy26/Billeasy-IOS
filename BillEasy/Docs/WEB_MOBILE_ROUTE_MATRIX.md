# BillEasy iOS - Matriz Web x Mobile

Este documento trava o alinhamento entre os botoes principais do app iOS e as rotas reais usadas pela versao web.

## Fonte de verdade

- Web frontend:
  - `/Users/samueljammes/Developer/BilleasyV2/billeasy-frontend/src/router.tsx`
  - `/Users/samueljammes/Developer/BilleasyV2/billeasy-frontend/src/app/routes/HandoffPage.tsx`
  - `/Users/samueljammes/Developer/BilleasyV2/billeasy-frontend/src/components/layout/Sidebar.tsx`
  - `/Users/samueljammes/Developer/BilleasyV2/billeasy-frontend/src/components/features/contratos/ContratoWizard.tsx`
- Backend:
  - `/Users/samueljammes/Developer/BilleasyV2/src/main/java/com/v2/billeasy/presentation/auth/AuthController.java`
  - `/Users/samueljammes/Developer/BilleasyV2/src/main/java/com/v2/billeasy/presentation/contrato/ContratoController.java`
  - `/Users/samueljammes/Developer/BilleasyV2/src/main/java/com/v2/billeasy/application/contrato/management/CriarContratoInput.java`

## Regra de integracao

- Fluxos de "Quero Receber", "Quero Pagar" e "Agenda" devem usar os feeds novos de dividas:
  - `GET /api/dividas/receber`
  - `GET /api/dividas/pagar`
  - `GET /api/dividas/{id}`
- A Agenda reaproveita `GET /api/dividas/receber` e so muda o mapeamento visual.
- Fluxos de IA usados pela UI do contrato devem passar pelo proxy autenticado do backend Java:
  - `/api/ia/extrair-de-imagem`
  - `/api/ia/extrair-texto`
- Upload/classificacao do novo contrato deve usar:
  - seletor de documento nativo do iOS
  - `POST /api/ia/extrair-de-imagem` para imagem ou PDF no fluxo de arquivo
  - `POST /api/contratos/fluxo-ia` como criacao remota principal do contrato
- A tela "Meu Plano" continua lendo o contexto remoto do backend:
  - `GET /api/planos`
  - `GET /api/planos/{id}`
  - `GET /api/assinaturas/minha`
  - `GET /api/assinaturas/minha/cotas`
- No iOS, o fluxo de contratacao do plano e dos creditos foi centralizado na web:
  - CTA publico abre `GET /cadastro`
  - CTAs autenticados do "Meu Plano" primeiro chamam `POST /auth/mobile-handoff`
  - o backend devolve `token`
  - o app abre `GET /handoff?token=...&next=/app/conta/plano` no navegador externo
  - a web troca o token em `POST /auth/handoff-exchange`, seta cookies web e redireciona direto para `/app/conta/plano`
- Em Debug, o app aponta `FRONTEND_BASE_URL` para `http://localhost:3000`, onde o frontend V2 local deve estar rodando.
- Em Release, `FRONTEND_BASE_URL` deve ser o deploy publico do frontend V2; o host V1 nao contem as rotas `/handoff` + `/app/localizar-devedor`.
- O menu lateral do iOS nao exibe mais "Meu Plano".
- Os atalhos de "Localizar Devedor" no iOS agora usam o mesmo handoff autenticado:
  - `POST /auth/mobile-handoff`
  - seguido da abertura de `/handoff?token=...&next=/app/localizar-devedor`
- O backend atual continua devolvendo `billingProvider` em `GET /api/assinaturas/minha`, mas o app iOS nao faz mais compra in-app.
- Download e assinatura devem usar:
  - `GET /api/contratos/{id}/documento.pdf`
  - `POST /api/contratos/{id}/assinar-credor`
  - `POST /api/contratos/{id}/assinar-devedor`
- O fluxo atual de `Novo Contrato` nao deve cair em `confirmDebt` como fallback de UI. Isso foge do padrao do web.

## Matriz de botoes

| Botao / acao no iOS | Tela iOS | Arquivo iOS | Rota web equivalente | Payload esperado |
|---|---|---|---|---|
| `contracts.method.file` | Escolha de metodo do novo contrato | `Features/Contracts/ContractsViewController.swift` | Seleciona `ARQUIVO`, igual ao app Kotlin | Sem payload HTTP. So abre o seletor de documento do iOS. |
| `documentPicker` + PDF/imagem | Novo contrato por arquivo | `Features/Contracts/ContractsViewController.swift` | `POST /api/ia/extrair-de-imagem` | `multipart/form-data` com `file`. O backend devolve `campos`, `textoExtraido`, `confiancaGeral` e `paginasProcessadas`, e o iOS preenche o formulario com a resposta estruturada. |
| carregar "Quero Receber" | Dashboard do credor | `Domain/Portal/PortalDataService.swift` | `GET /api/dividas/receber` | Query `page=<pagina>&size=<limite>`. O iOS acumula páginas via infinite scroll e deriva total em aberto, pagos e atrasados localmente. |
| carregar "Quero Pagar" | Dashboard do devedor | `Domain/Portal/PortalDataService.swift` | `GET /api/dividas/pagar` | Query `page=<pagina>&size=<limite>`. O iOS acumula páginas via infinite scroll e deriva total a pagar, pagos e atrasados localmente. |
| carregar "Agenda" | Agenda de recebimentos | `Domain/Portal/PortalDataService.swift` | `GET /api/dividas/receber` | Query `page=<pagina>&size=<limite>`. O iOS acumula páginas via infinite scroll e mapeia `descricao` para título e `contrato.titulo` para subtítulo. |
| enriquecer cards/listas em segundo plano | Quero Receber / Quero Pagar / Agenda | `Features/Dashboard/*ViewController.swift` | `GET /api/dividas/{id}` | Sem body. Depois do primeiro paint o iOS atualiza silenciosamente valor, vencimento, atraso e resumo de parcelamento quando o detalhe remoto trouxer esses campos. |
| abrir modal de contrato do credor | Quero Receber | `Features/Dashboard/DashboardViewController.swift` | `GET /api/dividas/{id}` seguido de `GET /api/contratos/{id}` quando existir | Sem body. Primeiro o iOS hidrata resumo e contrato fallback pela dívida; depois enriquece com o texto completo do contrato remoto. |
| abrir modal do Serasa | Quero Receber | `Features/Dashboard/DashboardViewController.swift` | `GET /api/dividas/{id}` | Sem body. Atualiza título, valor atualizado, documento e dias em atraso no popup. |
| abrir modal de pagamento | Quero Pagar | `Features/Dashboard/PaymentsViewController.swift` | `GET /api/dividas/{id}` | Sem body. Atualiza título e valor atualizado antes de confirmar o pagamento. |
| hidratar métodos do modal de pagamento | Quero Pagar | `Domain/Portal/PortalActionsService.swift` | `GET /api/formasDePagamentos` | Sem body. O iOS normaliza o catálogo remoto para `PIX`, `BOLETO`, `CARTAO_DE_CREDITO` e usa fallback local se a API não responder. |
| abrir modal de contrato do devedor | Quero Pagar | `Features/Dashboard/PaymentsViewController.swift` | `GET /api/dividas/{id}` seguido de `GET /api/contratos/{id}` quando existir | Sem body. Mesmo padrão do web: dívida real primeiro, contrato remoto depois. |
| `contracts.method.ai` | Escolha de metodo do novo contrato | `Features/Contracts/ContractsViewController.swift` | Seleciona `IA`, igual ao app Kotlin | Sem payload HTTP. So abre o pop-up de IA. |
| `contracts.aiGenerator.textMode` + `contracts.aiGenerator.generateButton` | Geracao por IA via texto | `Features/Contracts/ContractAIGeneratorViewController.swift` | `POST /api/ia/extrair-texto` | JSON `{ "texto": "<texto digitado>", "contexto": "<instrucao do app>" }` |
| `contracts.aiGenerator.documentButton` | Geracao por IA via imagem | `Features/Contracts/ContractAIGeneratorViewController.swift` | Abre seletor de imagem do iOS | Sem payload HTTP. |
| `contracts.aiGenerator.generateButton` no modo documento | Geracao por IA via imagem | `Domain/AI/AIExtractionService.swift` | `POST /api/ia/extrair-de-imagem` | `multipart/form-data` com `file`. O iOS reaproveita o mesmo fluxo estruturado do Kotlin/web e só cai em texto corrido quando a resposta vier pobre. |
| `contracts.creditor.cepLookupButton` | Endereço do credor em Novo Contrato | `Features/Contracts/ContractsViewController.swift` | `GET /api/enderecos/cep/{cep}` | Sem body. Preenche preview de logradouro, bairro, cidade e estado para manter o mesmo padrão do web no lado do credor. |
| `contracts.debtor.cepLookupButton` | Endereço do devedor em Novo Contrato | `Features/Contracts/ContractsViewController.swift` | `GET /api/enderecos/cep/{cep}` | Sem body. Preenche preview de logradouro, bairro, cidade e estado para manter o mesmo padrão do web no lado do devedor. |
| `contracts.submitButton` | Novo contrato no iOS atual | `Features/Contracts/ContractsViewController.swift` | `POST /api/contratos/fluxo-ia` | JSON alinhado ao app Kotlin: `empresaId`, `tipoNegocio`, `assunto`, `descricaoAcordo`, `frequenciaPagamento`, `dataPrimeiroVencimento`, `numeroParcelas`, `valorTotal`, `meiosPagamentoAceitos`, `credorNome`, `credorCpfCnpj`, `credorTelefone`, `credorTipoPessoa`, `credorChavePix`, `credorTipoChavePix`, `credorCep`, `credorNumero`, `credorComplemento?`, `devedorNome`, `devedorCpfCnpj`, `devedorTelefone`, `devedorEmail`, `devedorCep`, `devedorNumero`, `devedorComplemento?`. |
| `tab.locate` / `menu.locate` | Localizar Devedor | `Features/Dashboard/MainTabBarController.swift` | `POST /auth/mobile-handoff` -> `GET /handoff?token=...&next=/app/localizar-devedor` | Sem body. O backend cria um token efemero; a web troca por cookies e redireciona direto para a consulta. |
| `subscription.upgrade` | Meu Plano | `Features/Profile/MeuPlanoViewController.swift` | `POST /auth/mobile-handoff` -> `GET /handoff?token=...&next=/app/conta/plano` | Sem body. O app abre o site ja autenticado em `Meu Plano`. |
| `subscription.addAddon` | Meu Plano | `Features/Profile/MeuPlanoViewController.swift` | `POST /auth/mobile-handoff` -> `GET /handoff?token=...&next=/app/conta/plano` | Sem body. A compra de creditos extras foi centralizada na web com sessao reaproveitada. |
| `subscription.cancel` | Meu Plano | `Features/Profile/MeuPlanoViewController.swift` | `POST /auth/mobile-handoff` -> `GET /handoff?token=...&next=/app/conta/plano` | Sem body. Cancelamento e alteracoes de cobranca ficam no site, sem relogar no navegador. |
| abrir contrato remoto | Modais de contrato credor/devedor | `Domain/Portal/PortalActionsService.swift` | `GET /api/contratos/{id}/documento.pdf` | Sem body. O app obtém o arquivo `application/pdf` e abre a visualização interna do contrato. |
| assinar como credor | Modal do credor | `Domain/Portal/PortalActionsService.swift` | `POST /api/contratos/{id}/assinar-credor` | JSON de assinatura eletronica do app. |
| assinar como devedor | Modal do devedor | `Domain/Portal/PortalActionsService.swift` | `POST /api/contratos/{id}/assinar-devedor` | JSON de assinatura eletronica do app. |
| confirmar pagamento | Modal de pagamento | `Domain/Portal/PortalActionsService.swift` | `POST /api/dividas/{dividaId}/parcelas/{parcelaId}/pagamentos` | JSON `{ "metodo": "<PIX|BOLETO|CARTAO_DE_CREDITO|...>" }` |

## Payload do fluxo IA

O iOS deve seguir o mesmo contrato semantico do web para `POST /api/contratos/fluxo-ia`.

Campos usados hoje:

```json
{
  "empresaId": "uuid-da-empresa",
  "tipoNegocio": "OUTRO_ACORDO_GERAL",
  "assunto": "Venda de Equipamento",
  "descricaoAcordo": "Venda parcelada de equipamento industrial.",
  "frequenciaPagamento": "UNICO_A_VISTA",
  "dataPrimeiroVencimento": "2026-04-10",
  "numeroParcelas": 1,
  "valorTotal": 2500.00,
  "meiosPagamentoAceitos": ["PIX", "BOLETO"],
  "credorNome": "BillEasy Credora",
  "credorCpfCnpj": "12345678000190",
  "credorTelefone": "11988880000",
  "credorTipoPessoa": "PESSOA_JURIDICA",
  "credorChavePix": "12345678000190",
  "credorTipoChavePix": "CPF_CNPJ",
  "credorCep": "01310100",
  "credorNumero": "123",
  "credorComplemento": "Conjunto 7",
  "devedorNome": "Samuel Jammes",
  "devedorCpfCnpj": "06427166174",
  "devedorTelefone": "61993011072",
  "devedorEmail": "s.jammes3@gmail.com",
  "devedorCep": "01310100",
  "devedorNumero": "1578",
  "devedorComplemento": "Sala 12"
}
```

Observacoes importantes:

- O web atual envia `dataPrimeiroVencimento` no formato `yyyy-MM-dd`.
- O iOS segue esse mesmo formato simples para manter paridade com o fluxo ativo do web/Kotlin.
- O app Kotlin atual nao envia mais `texto` no submit; ele envia os campos estruturados do `FluxoIaInput`.
- O iOS segue essa mesma estrutura para `descricaoAcordo`, dados do credor, dados do devedor e `meiosPagamentoAceitos`.
- `credorChavePix` deve ser normalizado antes do payload: documento e telefone sem mascara, e-mail em minusculas.

## Arquivos iOS que implementam o fluxo

- Rotas:
  - `Core/Routing/APIRoutes.swift`
- Servico de IA:
  - `Domain/AI/AIExtractionService.swift`
- Tela principal do contrato:
  - `Features/Contracts/ContractsViewController.swift`
- Pop-up de IA:
  - `Features/Contracts/ContractAIGeneratorViewController.swift`
- Tela Meu Plano:
  - `Features/Profile/MeuPlanoViewController.swift`
- Servico de assinatura:
  - `Domain/Portal/PortalSubscriptionService.swift`
- Acoes remotas de PDF, assinatura e pagamento:
  - `Domain/Portal/PortalActionsService.swift`

## Checklist quando o web mudar

1. Conferir `src/services/api.ts`.
2. Conferir modais web de contrato e pagamento.
3. Confirmar se as rotas continuam passando por `/api/ia/*` e `/api/contratos/fluxo-ia`.
4. Confirmar se o fluxo de arquivo continua em `POST /api/ia/extrair-de-imagem`, sem OCR legado como caminho principal.
5. Validar se houve mudanca em nome de campo, formato de data, enum de pagamento ou payload de assinatura/plano.
6. Atualizar testes em:
   - `BillEasyTests.swift`
   - `AIExtractionServiceTests.swift`
   - `PortalActionsServiceTests.swift`
   - `PortalSubscriptionServiceTests.swift`
