# Configuração de ambiente

## Arquivos versionados

- `App.Shared.xcconfig`: defaults públicos do app.
- `App.Debug.xcconfig` e `App.Release.xcconfig`: incluem os defaults e, opcionalmente, o segredo local.
- `Secrets.example.xcconfig`: modelo para criar o arquivo secreto real.

## URLs em `.xcconfig`

- Em `.xcconfig`, `//` inicia comentário.
- Por isso URLs devem ser escritas como `https:/$()/api.exemplo.com`.
- No valor final do build, isso vira `https://api.exemplo.com`.

## Arquivo secreto local

1. Copie `Secrets.example.xcconfig` para `Secrets.xcconfig`.
2. Preencha `AI_SERVICE_TOKEN`.
3. Se for usar Google no iOS, preencha `GOOGLE_OAUTH_CLIENT_ID` com o client OAuth nativo do app.
4. Registre no Google Cloud o redirect `br.com.billeasy:/oauth2redirect/google`.
5. Não versione esse arquivo.

## Assinaturas via web

- O fluxo de contratacao do `Meu Plano` no iOS abre a versao web do BillEasy.
- O item `Meu Plano` nao aparece mais no menu lateral do app; o acesso comercial ficou fora da navegacao principal mobile.
- O atalho `Localizar Devedor` no app abre a versao web autenticada em `/localizar`.
- O app usa:
  - `FRONTEND_BASE_URL` para o CTA publico de "Comece gratis" via `GET /cadastro`
  - `API_BASE_URL` para o handoff autenticado do mobile:
    - `POST /api/auth/mobile-web-handoff`
    - resposta com `handoffUrl`
    - abertura de `GET /api/auth/mobile-handoff?token=...` no navegador
- O backend deve redirecionar o navegador ja autenticado para:
  - `/meu-plano`
  - `/localizar`
- `FRONTEND_BASE_URL` e `API_BASE_URL` precisam estar configurados no build de debug e release.

## CI

No CI, gere `BillEasy/Config/Secrets.xcconfig` antes do build. Exemplo:

```bash
cat > BillEasy/Config/Secrets.xcconfig <<'EOF'
AI_SERVICE_TOKEN = ${AI_SERVICE_TOKEN}
GOOGLE_OAUTH_CLIENT_ID = ${GOOGLE_OAUTH_CLIENT_ID}
FRONTEND_BASE_URL = ${FRONTEND_BASE_URL}
EOF
```

Assim o `Info.plist` recebe o valor por build setting, sem segredo hardcoded no projeto.
