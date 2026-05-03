# Apple Developer Setup — Sign in with Apple

## O que já está preparado no projeto

- **Arquivo de entitlements criado:** `BillEasy/BillEasy.entitlements`
  Contém a chave `com.apple.developer.applesignin` com valor `Default`, que é o requisito mínimo para Sign in with Apple.

- **Target principal configurado:** O target `BillEasy` aponta para esse arquivo via `CODE_SIGN_ENTITLEMENTS = BillEasy/BillEasy.entitlements` em ambas as configurações Debug e Release do `project.pbxproj`.

- **Fluxo de autenticação intacto:** Os arquivos `LoginViewController.swift` e `RegisterViewController.swift` já usam `ASAuthorizationAppleIDProvider` e não foram alterados.

- **Code signing automático mantido:** `CODE_SIGN_STYLE = Automatic` foi preservado; nenhum Team ID fixo, provisioning profile manual ou certificado foram definidos.

---

## O que ainda falta — passos futuros (requer conta Apple Developer ativa)

Estes passos só podem ser executados após a abertura da conta Apple Developer com o CNPJ da empresa.

### 1. Criar/validar o App Identifier

1. Acesse [developer.apple.com → Certificates, IDs & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list).
2. Crie (ou edite) o App ID com Bundle ID `br.com.BillEasy`.
3. Confirme que o Bundle ID é **Explicit** (não Wildcard).

### 2. Habilitar a capability "Sign in with Apple"

1. Na tela do App Identifier `br.com.BillEasy`, localize **Sign in with Apple**.
2. Ative a capability e salve.

### 3. Gerar provisioning profile compatível

1. Vá em **Profiles → Create a new profile**.
2. Selecione o tipo adequado (Development para testes, Distribution para App Store).
3. Escolha o App ID `br.com.BillEasy` (que agora tem Sign in with Apple ativo).
4. Baixe e instale o profile no Xcode ou no Keychain.

### 4. Definir o Team ID no projeto (quando a conta existir)

No Xcode, em **Signing & Capabilities**, selecione o Team correto. O Xcode preencherá `DEVELOPMENT_TEAM` automaticamente no modo Automatic signing.

### 5. Testar em dispositivo real

O Sign in with Apple **não funciona no Simulator** para fluxo completo. Teste obrigatório em iPhone/iPad físico conectado.

---

## Limitação esperada até a conta existir

Enquanto não houver conta Apple Developer ativa com o Bundle ID `br.com.BillEasy` registrado, o app **compilará localmente sem erros de código**, mas:

- O Xcode pode exibir aviso/erro de provisioning ao tentar instalar em dispositivo físico.
- O fluxo `ASAuthorizationAppleIDProvider` lançará erro em runtime no dispositivo (sem provisioning válido).
- Builds no Simulator continuam funcionando normalmente para os demais fluxos.

Isso é uma **limitação de infraestrutura**, não um erro de código.

---

## Referências

- [Sign in with Apple — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)
- [ASAuthorizationAppleIDProvider — Apple Developer Docs](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider)
- [Configuring Sign in with Apple — App Identifiers](https://developer.apple.com/documentation/sign_in_with_apple/configuring_your_environment_for_sign_in_with_apple)
