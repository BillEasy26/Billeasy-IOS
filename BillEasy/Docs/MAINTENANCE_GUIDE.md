# BillEasy iOS - Guia de Manutencao

Este documento define como o projeto esta organizado e qual padrao seguir para futuras evolucoes.

## Estrutura oficial

```
BillEasy/
  App/
    AppDelegate.swift
    SceneDelegate.swift
    AppCoordinator.swift
    AppRuntimeConfiguration.swift
  Core/
    Extensions/
      UIExtensions.swift
    Routing/
      APIRoutes.swift
      AppNavigationCatalog.swift
      RouteScreenFactory.swift
    Utilities/
      Formatters.swift
  Data/
    Stores/
      LocalAppDataStore.swift
      LocalAuthStore.swift
  Domain/
    Auth/
      AuthModels.swift
      AuthService.swift
  Features/
    Authentication/
      LoginViewController.swift
      RegisterViewController.swift
    Dashboard/
      MainTabBarController.swift
      DashboardViewController.swift
      PaymentsViewController.swift
      AgendaViewController.swift
      DebtorsViewController.swift
      PopupsViewControllers.swift
    Contracts/
      ContractsViewController.swift
    Profile/
      ProfileViewController.swift
    Routes/
      RouteListViewController.swift
      RoutePlaceholderViewController.swift
    Compliance/
      CompaniesViewController.swift
      AuditViewController.swift
      RbacViewController.swift
      PrivacyViewController.swift
      SecurityViewController.swift
  Base.lproj/
  Assets.xcassets/
  Info.plist
```

## Responsabilidade por camada

- `App`: bootstrap, ciclo de vida, coordenacao de navegacao principal.
- `Core`: regras transversais (rotas, utilitarios, extensoes de UI).
- `Data`: persistencia local e estado mock/local do app.
- `Domain`: modelos e servicos de negocio/autenticacao.
- `Features`: telas e fluxo de produto, separadas por modulo.

## Convencoes de nomenclatura

- View controllers: sempre `<Contexto>ViewController`.
- Stores locais: `<Contexto>Store`.
- Arquivos de rotas/catalogos: nomes explicitos (`APIRoutes`, `AppNavigationCatalog`).
- Evitar nomes genericos como `ViewController.swift`.

## Regras para novas telas

1. Criar a tela na pasta da feature correspondente em `Features/<Modulo>/`.
2. Nomear classe/arquivo de forma semantica (`PaymentDetailViewController`, por exemplo).
3. Registrar navegacao em um dos pontos:
   - `AppCoordinator` (fluxo publico/login/app shell)
   - `MainTabBarController` (secoes principais)
   - `RouteScreenFactory` (mapeamento de rotas catalogadas)
4. Manter tema via utilitarios de `UIExtensions.swift` e nao hardcodear estilos fora do padrao do modulo.

## Regras de dados locais

- Conta nova deve iniciar sem dados fixos de usuario.
- Persistencia de perfil e permissoes deve usar `UserDefaults`/stores locais existentes.
- Quando migrar para API real, manter interfaces para trocar implementacao sem alterar UI.

## Padrao de comentarios e refatoracao

- Comentario deve explicar intencao, regra de negocio, efeito colateral ou decisao de arquitetura.
- Evitar comentario obvio que so repete o nome da linha ou da funcao.
- Quando eu perceber repeticao de validacao, mapeamento ou configuracao visual, a prioridade e extrair helper com nome semantico.
- Funcoes pequenas e bem nomeadas valem mais do que blocos grandes com comentarios excessivos.
- Comentarios em primeira pessoa podem ser usados quando ajudarem a deixar claro o raciocinio do modulo, sem perder objetividade.

## Checklist antes de finalizar alteracoes

1. Build: `xcodebuild -project BillEasy.xcodeproj -scheme BillEasy -sdk iphonesimulator -configuration Debug build`
2. Validar fluxos criticos:
   - login/cadastro
   - troca de tema
   - navegacao lateral e bottom tabs
   - edicao e salvamento do perfil
3. Confirmar que os nomes de arquivo/classe continuam sem ambiguidades.

## Matriz de integracao Web x Mobile

- Sempre que houver alteracao no web ou no backend, revisar primeiro:
  - `Docs/WEB_MOBILE_ROUTE_MATRIX.md`
- Esse arquivo concentra:
  - botao da UI
  - tela responsavel
  - rota consumida
  - payload esperado
- Para fluxos de contrato com IA, PDF, assinatura e pagamento, ele passa a ser a referencia principal de manutencao.
