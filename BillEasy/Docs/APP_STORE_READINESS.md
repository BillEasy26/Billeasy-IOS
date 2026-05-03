# App Store Readiness — BillEasy iOS

> Última atualização: 2026-04-24
> Estado: pronto para aguardar conta Apple Developer. Nenhum bloqueador técnico de código.

---

## Resumo executivo

| Área | Status |
|---|---|
| Privacy Manifest | ✅ Criado, empacotado no bundle (Debug e Release verificados) |
| Entitlements / Sign in with Apple | ✅ Arquivo criado, target configurado — validação final depende de conta Apple |
| Keychain (tokens seguros) | ✅ Access token e refresh token persistidos com `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| CTAs comerciais externos | ✅ Textos neutralizados — sem incentivo direto a compra fora do iOS |
| Localizar Devedor (web-only) | ✅ Tela nativa bloqueada em Release via `#if DEBUG`; handoff web ativo |
| `RouteListViewController` | ✅ Envolvida em `#if DEBUG` — não acessível em Release |
| Permissões (Info.plist) | ✅ Todas as 5 têm uso real confirmado no código |
| iPhone-only | ✅ `TARGETED_DEVICE_FAMILY = 1` em Debug e Release do target principal |
| Privacidade / LGPD / Exclusão de conta | ✅ `PrivacyViewController` funcional com API de anonimização |
| Build Debug | ✅ BUILD SUCCEEDED |
| Build Release (sem signing) | ✅ BUILD SUCCEEDED — falha esperada ao assinar sem conta Apple |
| Test build | ✅ TEST BUILD SUCCEEDED |

---

## Detalhes por área

### 1. Privacy Manifest

- **Arquivo:** `BillEasy/PrivacyInfo.xcprivacy`
- **Incluído no bundle:** confirmado via `find` no `.app` de Debug e Release
- **Não está nas exceções** do `PBXFileSystemSynchronizedRootGroup` — empacotado corretamente como recurso
- **Conteúdo:**
  - `NSPrivacyAccessedAPICategoryUserDefaults` → razão `CA92.1` (uso interno do app: tema, onboarding, preferências)
  - `NSPrivacyTracking = false`
  - Nenhum domínio de tracking declarado
  - `NSPrivacyCollectedDataTypes = []`
- **Pendência:** Se SDKs de terceiros forem adicionados (ex.: Firebase, Analytics), seus manifestos precisam ser verificados separadamente.

### 2. Entitlements e Sign in with Apple

- **Arquivo:** `BillEasy/BillEasy.entitlements` com `com.apple.developer.applesignin`
- **Build settings:** `CODE_SIGN_ENTITLEMENTS = BillEasy/BillEasy.entitlements` em Debug (linha 312) e Release (linha 346)
- **Team ID:** não hardcoded — `CODE_SIGN_STYLE = Automatic`
- **Fluxo implementado:** `ASAuthorizationAppleIDProvider` em `LoginViewController` e `RegisterViewController`
- **Pendência obrigatória:** habilitar capability "Sign in with Apple" no App Identifier `br.com.BillEasy` após criar conta Apple Developer

### 3. Keychain e sessão

- **`KeychainTokenStore`** em `Data/Stores/KeychainTokenStore.swift`
  - `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — tokens disponíveis após primeiro unlock, não sincronizados para outros dispositivos
  - `kSecAttrService = "billeasy"` — namespace próprio
- **Integração em `RemoteSecurityContext`:**
  - `init()` carrega `accessToken` e `refreshToken` do Keychain → sessão persiste ao reabrir o app
  - `captureSecurityState(from:)` salva tokens ao recebê-los do backend
  - `reset()` chama `KeychainTokenStore.shared.clear()` → logout limpa Keychain
- **Cookies CSRF** continuam no `HTTPCookieStorage` — não alterados
- **Handoff web** continua usando Bearer token via `applySecurityHeaders(to:)` → funcionamento mantido
- **UserDefaults** não guarda tokens sensíveis — apenas preferências de UI (tema, onboarding)

### 4. Localizar Devedor (web-only em Release)

Três camadas de proteção:

1. **`MainTabBarController.makeControllers()`** — `.localizar` não instancia `DebtorsViewController` (removido na sessão anterior)
2. **`MainTabBarController` tap handlers** — `bottomTapped` e `menuSectionTapped` chamam `openDebtorLocatorInBrowser()` para `.localizar`
3. **`RouteScreenFactory.makeScreen(for: .localizar, ...)`** — protegido com `#if DEBUG`; em Release retorna `RoutePlaceholderViewController`

`RouteListViewController` — envolvida em `#if DEBUG`; não compila em Release.

### 5. Auditoria de CTAs comerciais

Termos auditados: comprar, assinar, assinatura, upgrade, contratar, cobrança, cartão, créditos, add-on, addon, StoreKit.

**Legítimos — mantidos:**
- `"Assinar como Credor"`, `"Assinar como Devedor"`, `"Assinar gov.br"` → assinatura digital de contrato jurídico, não compra de plano
- `"assinatura"` em alertas de inadimplência e status de plano → informação de estado, não CTA de compra
- `"cobrança"` no Dashboard → contexto financeiro da funcionalidade principal do app
- `"add-ons"` em descrição de plano → informação de capacidades, não botão de compra
- `"cartão"` em `ContractAudioCaptureViewController` → campo de exemplo para método de pagamento de contrato

**Alterados na sessão anterior:**
- `"Upgrade para Standard"` → `"Plano Standard"`
- `"Comece grátis"` → `"Ver detalhes no portal"`
- `"Gerenciar créditos na web"` → `"Gerenciar no portal"`
- `"Abra o navegador para comprar..."` → `"Serviços adicionais são gerenciados no portal web."`
- `"Cobrança, mudança de plano..."` → `"Mudança de plano e cancelamento são gerenciados no portal."`

**Resultado:** nenhum CTA direciona explicitamente o usuário a comprar conteúdo digital fora do iOS.

### 6. Permissões (Info.plist)

| Permissão | Chave | Uso real confirmado |
|---|---|---|
| Câmera | `NSCameraUsageDescription` | `ContractFileUploadViewController` → `UIImagePickerController` com `.camera` |
| Microfone | `NSMicrophoneUsageDescription` | `ContractAudioCaptureViewController` → `AVAudioRecorder` |
| Fotos | `NSPhotoLibraryUsageDescription` | `ContractAIGeneratorViewController` → `PHPickerViewController` |
| Localização | `NSLocationWhenInUseUsageDescription` | `MainTabBarController` → `CLLocationManager.requestWhenInUseAuthorization()` |
| Face ID | `NSFaceIDUsageDescription` | `SecurityViewController` → `LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` |

Nenhuma permissão é solicitada na abertura do app. Todas são pedidas no momento de uso.

### 7. iPhone-only

- `TARGETED_DEVICE_FAMILY = 1` em Debug e Release do target `BillEasy`
- Targets de teste mantidos como `"1,2"` (sem impacto no app)
- `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` removido dos build settings

### 8. Arquivos internos e bundle

- `Docs/*.md` e `BillEasy.entitlements` nas exceções do sync group → não empacotados
- `PrivacyInfo.xcprivacy` não está nas exceções → empacotado no bundle ✅
- Confirmado via `find` no `.app` de ambas as configurações

### 9. Privacidade, LGPD e exclusão de conta

- `PrivacyViewController` com fluxo completo: visualização de dados, modal de confirmação por email, chamada a `/api/lgpd/anonimizar/{usuarioId}`
- Logout após anonimização bem-sucedida
- Não é placeholder — fluxo funcional com backend real

---

## Resultados de build e testes

| Comando | Resultado |
|---|---|
| `xcodebuild Debug Simulator` | ✅ BUILD SUCCEEDED |
| `xcodebuild Release iphoneos CODE_SIGNING_ALLOWED=NO` | ✅ BUILD SUCCEEDED |
| `xcodebuild build-for-testing x86_64 iphonesimulator` | ✅ TEST BUILD SUCCEEDED |
| Build Release com signing real | ⏳ Depende de conta Apple Developer |
| Testes em dispositivo físico | ⏳ Depende de conta Apple Developer |

---

## O que depende da conta Apple Developer (CNPJ pendente)

| Item | Ação |
|---|---|
| App ID `br.com.BillEasy` | Criar em developer.apple.com → Certificates, IDs & Profiles |
| Capability Sign in with Apple | Habilitar no App Identifier após criar a conta |
| Certificado de distribuição | Gerar via Xcode Automatic Signing |
| Provisioning profile | Gerado automaticamente pelo Xcode após Team ID configurado |
| Archive + upload | Xcode → Product → Archive → Distribute App |
| App Store Connect | Criar o app, preencher metadados, screenshots, descrição |
| App Privacy labels | Preencher no App Store Connect (dados coletados, uso, rastreamento) |
| Conta demo para reviewer | Criar login de teste para o revisor da Apple |
| TestFlight | Disponível após primeiro upload de build |
| Teste de Sign in with Apple | Obrigatório em dispositivo físico com conta Apple Developer ativa |

---

## Checklist final antes de submissão

### Técnico
- [ ] Conta Apple Developer ativa com CNPJ registrado
- [ ] App ID `br.com.BillEasy` criado
- [ ] Capability "Sign in with Apple" habilitada no App Identifier
- [ ] Build Archive sem warnings críticos (`Product → Archive`)
- [ ] `Validate App` sem erros no Organizer
- [ ] Testes unitários executados em simulador
- [ ] Sign in with Apple testado em iPhone físico
- [ ] Login com Google testado em iPhone físico
- [ ] Handoff web (autenticação no portal) testado em iPhone físico

### App Store Connect
- [ ] URL pública da Política de Privacidade
- [ ] URL pública dos Termos de Uso
- [ ] Screenshots obrigatórios: iPhone 6.5" (iPhone 14 Plus / 15 Plus) e 6.9" (iPhone 16 Pro Max)
- [ ] Descrição do app em português
- [ ] Palavras-chave definidas
- [ ] Categoria: Finanças
- [ ] Faixa etária: 4+
- [ ] Contato de suporte (email/URL)
- [ ] App Privacy labels preenchidos
- [ ] Declaração de criptografia (exportação — verificar se necessário)
- [ ] Opção de exclusão de conta declarada (fluxo nativo já existe)
- [ ] Conta demo para revisor Apple

### Revisão de conteúdo
- [x] CTAs não incentivam compra externa de conteúdo digital
- [x] Nenhuma tela debug/placeholder acessível em Release
- [x] App companion gratuito — nenhum IAP necessário
- [x] `RouteListViewController` isolada com `#if DEBUG`
- [x] `DebtorsViewController` não acessível via `RouteScreenFactory` em Release

---

## Observações importantes

**App companion gratuito.**
Não há In-App Purchase. Toda assinatura e cobrança ocorre no portal web. Isso é permitido pela App Store desde que o app não *direcione* o usuário a comprar fora do iOS de forma explícita — os textos foram ajustados para isso.

**"Assinar" = assinatura de contrato.**
Os botões "Assinar como Credor/Devedor" e "Assinar gov.br" referem-se à assinatura digital de contratos jurídicos, não a compra de assinatura (subscription). Esses CTAs são funcionalmente corretos e não violam as diretrizes da App Store.

**Sign in with Apple.**
Implementação técnica pronta. Validação completa só após conta Apple Developer ativa com Bundle ID `br.com.BillEasy` e capability habilitada.

**Tokens e segurança.**
Access token e refresh token persistem no Keychain do dispositivo. Cookies CSRF continuam no `HTTPCookieStorage` (requerido pelo backend). Nenhum token sensível em `UserDefaults`.
