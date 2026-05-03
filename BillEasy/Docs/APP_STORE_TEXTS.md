# Textos para App Store Connect — BillEasy

> Última atualização: 2026-04-24
> Pronto para colar no App Store Connect assim que a conta Apple Developer estiver ativa.

---

## Nome do app
```
BillEasy
```
*(máx. 30 caracteres — 8 usados)*

---

## Subtítulo
```
Cobranças e contratos na palma da mão
```
*(máx. 30 caracteres — 38 caracteres: AJUSTAR para uma das opções abaixo)*

**Opção A (28 chars):**
```
Gestão de cobranças e contratos
```
**Opção B (26 chars):**
```
Cobrança inteligente e segura
```
**Opção C (24 chars):**
```
Contratos e cobranças fáceis
```

---

## Palavras-chave
```
cobrança,contratos,devedor,credor,gestão,financeiro,inadimplência,recebimento,agenda,pagamentos
```
*(98 caracteres — máx. 100. Não usar espaços, apenas vírgulas.)*

---

## Categoria
- **Primária:** Finance (Finanças)
- **Secundária:** Business (Negócios)

---

## Faixa etária
- **4+**

---

## Descrição completa
*(máx. 4.000 caracteres — usar abaixo)*

```
O BillEasy é o app companion da plataforma billeasy.com.br, feito para credores e devedores que precisam acompanhar contratos, cobranças e pagamentos de qualquer lugar, direto pelo iPhone.

Gerencie tudo que importa na sua operação de cobrança:

• Dashboard — visão geral das cobranças ativas, valores a receber e status de inadimplência em tempo real.

• Contratos — crie, revise e assine contratos digitalmente. Suporte a upload de documentos por câmera, galeria ou arquivo. Geração assistida por IA para preencher contratos automaticamente a partir de descrições em texto ou áudio.

• Agenda — acompanhe os vencimentos dos seus devedores com uma linha do tempo clara. Saiba quem está em dia, quem está atrasado e quem já pagou.

• Pagamentos — histórico completo de transações, com filtros por status, data e valor.

• Empresas — gerencie as empresas credoras vinculadas à sua conta em um só lugar.

• Diretório de Devedores — acesse o cadastro de devedores com informações de contato e histórico de contratos.

• Perfil e Segurança — autenticação por Face ID, Touch ID ou senha. Sessão protegida com tokens no Keychain do dispositivo.

• Privacidade — visualize seus dados cadastrados e solicite a exclusão da sua conta a qualquer momento, em conformidade com a LGPD.

• Auditoria — registro completo de ações para conformidade e rastreabilidade (disponível para administradores).

Login com e-mail, Google ou Apple. Sessão persiste ao fechar o app — sem precisar entrar de novo.

O BillEasy é um app companion gratuito. Planos, assinatura e contratação de serviços adicionais são gerenciados no portal web em billeasy.com.br.
```

*(Contagem: ~1.450 caracteres. Sobram ~2.550 para expandir se necessário.)*

---

## Notas de versão (primeira versão)
```
Primeira versão do BillEasy para iPhone.

Gerencie contratos, cobranças e pagamentos direto pelo celular. Login com e-mail, Google ou Apple. Assinatura digital de contratos, agenda de vencimentos e dashboard de cobranças em tempo real.
```

---

## Informações de contato e suporte

| Campo | Valor |
|---|---|
| URL de suporte | https://billeasy.com.br/suporte (criar página) |
| URL de privacidade | https://billeasy.com.br/privacidade (criar página) |
| E-mail de contato | administrativo@billeasy.com.br |
| Copyright | © 2026 BillEasy |

---

## Declaração de privacidade (App Privacy labels no App Store Connect)

### Dados coletados e vinculados à identidade do usuário:
| Tipo | Dado | Uso |
|---|---|---|
| Dados de contato | Nome, e-mail, telefone | Autenticação e identificação da conta |
| Identificadores | ID do usuário | Funcionamento do app |
| Conteúdo do usuário | Documentos, fotos, áudios de contratos | Funcionalidade principal do app |
| Dados financeiros | Valores de contratos e cobranças | Funcionalidade principal do app |

### Rastreamento: **Não** (o app não rastreia o usuário entre apps de terceiros)

### Dados NÃO coletados:
- Dados de localização (permissão solicitada mas não enviada ao servidor)
- Dados de saúde
- Histórico de navegação
- Dados de uso para publicidade

---

## Conta demo para revisor Apple

Criar antes da submissão no backend em api.billeasy.com.br:

| Campo | Valor sugerido |
|---|---|
| E-mail | reviewer@billeasy.com.br |
| Senha | (definir senha forte, 12+ chars) |
| Tipo | Credor |
| Dados mínimos | 1 empresa, 2 contratos, 1 devedor de exemplo |

**Nota para o revisor (preencher no campo "Review Notes" do App Store Connect):**
```
Use as credenciais abaixo para acessar o app:
E-mail: reviewer@billeasy.com.br
Senha: [PREENCHER]

O app é um companion do portal web billeasy.com.br.
Todas as funcionalidades estão disponíveis após o login.
Assinatura digital de contratos requer câmera ou galeria de fotos.
Localização é solicitada apenas ao acessar a funcionalidade de mapa — pode ser negada sem impacto.
```

---

## Checklist de conteúdo antes de colar no App Store Connect

- [ ] Escolher subtítulo definitivo (opções A, B ou C acima)
- [ ] Criar página https://billeasy.com.br/privacidade
- [ ] Criar página https://billeasy.com.br/termos
- [ ] Criar conta reviewer@billeasy.com.br com dados de teste no backend
- [ ] Tirar screenshots em iPhone 15 Plus (6.5") e iPhone 16 Pro Max (6.9") no simulador
- [ ] Preencher App Privacy labels com os dados da tabela acima
