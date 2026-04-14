# Nutriskin Val — Contexto do Projeto

Este arquivo é lido automaticamente por Claude Code toda sessão. Contém todo o contexto que você precisa pra trabalhar nesse projeto sem que o Pedro precise re-explicar.

---

## 1. O QUE É ESSE PROJETO

Sistema de agendamento via WhatsApp para a **Nutriskin**, clínica de nutrição de Porto Alegre da **nutricionista Renata R. Schwartz**. 

Desenvolvedor: **Pedro Magaldi** (P M Systems). Primeiro cliente pago do produto "Val" (nome interno, NÃO expor ao paciente). Pedro planeja produtizar e vender pra outras clínicas depois da Renata.

**Renata é perfeccionista.** Ela testa tudo. Qualquer desvio de tom, formatação ou fluxo ela aponta. No dia 08/04/2026 quase desistiu do projeto dizendo "estou achando que caí num golpe" — Pedro recuperou a confiança dela com posicionamento firme. **NÃO repetir esse risco.** Toda entrega passa por validação dela antes de ir pra paciente real.

**Status atual (14/04/2026):** em testes. Renata pausou testes dela. Pedro voltou a trabalhar hoje pra estabilizar o sistema.

---

## 2. ARQUITETURA

### Stack

- **n8n Cloud** (hospedado em `powerfultick-n8n.cloudfy.live`)
- **Evolution API** (WhatsApp), instância `WhatsApp Testes`, host `powerfultick-evolution.cloudfy.live`
- **Supabase/Postgres** (connection pooling via `aws-1-sa-east-1.pooler.supabase.com`, credencial n8n: `Z1EmglielD4NYxTR`)
- **Google Calendar** (credencial: `sizqRTusiuHppMO3`, calendário: `contato@nutriskin.com.br`)
- **Gemini 2.5 Flash** via OpenRouter (credencial: `qa2l3nOCmTmwbxll`, modelo: `google/gemini-2.5-flash`)
- **Google Sheets** (credencial: `J7m2gjjEyCq6U2vE`, spreadsheet ID `1OYuuhcHQ00_0GR-GLtOzsE8v33S7Qq5KyXhwsLWPIYA`)

### Workflows

- **Principal** — ID `E45e0ftLJNrE6UBl`, arquivo `workflows/val-principal.json`. Arquitetura de 4 cérebros (Cadastro, Agendamento, RAG/Conversacional) com estado em Postgres.
- **Follow-up 48h** — ID `K8SyR6SZD6RPKphh`, arquivo `workflows/follow-up-48h.json`. Cron que envia confirmação de consulta 48h antes.

### Fluxo principal (simplificado)

```
Webhook (Evolution) 
  → Buscar/Criar Usuário 
  → Acumular mensagens (Redis, 8s) 
  → Buscar Estado (Postgres) 
  → Classificar Intenção (Code) 
  → Switch Estado:
      ├─ coletando_dados → Cérebro 1 (Cadastro) → Extrair Dados → Atualizar Estado
      │                    → Se dados_ok: Preparar Cérebro 2
      ├─ dados_ok/agendando → Cérebro 2 (Agendamento) → Code → Detectar Agendamento
      │                       → Se agendado: Extrair Horário → Criar Evento Calendar
      │                       → Montar Confirmação (determinístico) → Enviar
      │                       → Switch Tipo Envio (4 branches: materiais por tipo)
      └─ novo/geral/agendado → Cérebro 4 (Conversacional) → FAQ/handoff
```

### Tabelas Postgres relevantes

- `dados_cliente` — estado da sessão por `session_id`
- `documents` — pgvector (RAG)
- `n8n_chat_histories` — memória dos agentes
- `handoff` — sinalização de handoff manual

### Campos de `dados_cliente`

`session_id, estado, tipo_consulta, modalidade, nome, email, cpf, data_nascimento, altura, endereco, cep, condicao_saude`

**Atenção:** `condicao_saude` foi adicionado no patch v2. Se a coluna não existir no Supabase da Renata, rodar:

```sql
ALTER TABLE dados_cliente ADD COLUMN IF NOT EXISTS condicao_saude TEXT DEFAULT '';
```

### Estados possíveis

- `novo` — recém-criado
- `coletando_dados` — cadastro em andamento (Cérebro 1)
- `dados_ok` — cadastro completo, pronto pra agendar
- `agendando` — agendamento em andamento (Cérebro 2)
- `agendado` — consulta criada no Calendar
- `geral` — conversa geral/FAQ (Cérebro 4)

---

## 3. HISTÓRICO DE PATCHES (IMPORTANTE)

### Estado no n8n Cloud hoje: v4 (atualizado 14/04/2026)

O workflow em produção é o **patch v4**, validado em 14/04/2026 às 20:38 no cenário 1ª presencial não-gestante (ponta a ponta). Inclui:

**v4 — Fallback determinístico (Extrair Dados):**
Adiciona detecção via regex na mensagem do paciente + output do LLM quando o Gemini Flash omite o bloco `[DADOS]`. Keywords:
- `tipo_consulta = 1a_consulta`: "primeira", "primeira vez", "nova", "nunca"
- `tipo_consulta = reconsulta`: "já sou", "já fui", "voltando", "reconsulta", "retorno"
- Reclassificação 12 meses: se já era `reconsulta` e disser "mais", "faz tempo", "mais de 12", "mais de um ano" → vira `1a_consulta`
- `modalidade = presencial`: "presencial", "consultório", "pessoalmente", "físico"
- `modalidade = online`: "online", "videochamada", "vídeo", "remoto"

**v4 — Fix conexão Switch Tipo Envio:**
Switch recebia input do "Enviar Confirmação" (HTTP Response sem campo `tipo`) em vez do "Montar Confirmação". Corrigido: Montar Confirmação agora sai em paralelo para Enviar Confirmação E Switch Tipo Envio.

**v4 — Prompt Cérebro 2 (3 melhorias):**
- Agenda cheia: formato BR obrigatório para [data] ("segunda-feira, dia 20 de abril", nunca ISO)
- Exemplos negativos de horário (9h errado, 9 horas certo, 9h30min certo)
- Passo 1.5: "qualquer dia/tanto faz" → 1 chamada buscar_eventos de 7 dias, sem repetir pergunta

**v4.1 — Fix IF "Não é gestante?":**
Condição buscava `$json.gestante` (vinha do Enviar Formulário, HTTP Response sem o campo). Corrigido para `$('Detectar Agendamento').first().json.gestante`.

### Testes de aceitação

Antes de declarar "pronto pra Renata":

1. ✅ **Reconsulta presencial** (validado v3, 08/04) — só confirmação, nada mais
2. ✅ **1ª presencial não-gestante** (validado v4, 14/04) — confirmação + apresentação + formulário + folha de preparo. 5/5 critérios: Switch roteando, formato data BR, formato horário, envio materiais completo, IF gestante
3. ⏳ **1ª presencial gestante** — confirmação + apresentação + formulário, SEM folha
4. ⏳ **1ª online** — confirmação + apresentação + formulário + orientações Body 3D
5. ⏳ **Reconsulta online** — confirmação + orientações Body 3D
6. ⏳ **Paciente antigo +12 meses** — reclassifica pra 1ª automaticamente

---

## 4. REGRAS DE NEGÓCIO (CHECKLIST DA RENATA — SPEC AUTORITATIVA)

Esse checklist é a **única fonte da verdade**. Qualquer divergência entre código e checklist → código está errado.

### Horários da agenda

| Dia | Janela | Última 1ª (60min) | Última reconsulta (30min) |
|---|---|---|---|
| Segunda | 9h às 17h (pode 18h30) | 16 horas | 17h30min |
| Terça | 9h às 16h30min | 15h30min | 16 horas |
| Quarta | 8h às 14h30min | 13h30min | 14 horas |
| Quinta | 9h às 16 horas | 15 horas | 15h30min |
| Sexta | 8h às 15 horas | 14 horas | 14h30min |
| Sáb/Dom | SEM ATENDIMENTO | — | — |

Durações: 1ª presencial = 60min | 1ª online = 30min | Reconsulta = 30min sempre.

### Valores (CORRETOS — verificar no prompt do Cérebro 4)

- 1ª presencial: **R$ 460,00**
- Reconsulta presencial: **R$ 380,00**
- 1ª online: **R$ 320,00**
- Reconsulta online: **R$ 280,00**

### Matriz de envio de materiais após confirmação

| Material | 1ª Presencial | 1ª Online | Reconsulta Presencial | Reconsulta Online |
|---|---|---|---|---|
| Apresentação Nutriskin (PDF) | ✅ | ✅ | ❌ | ❌ |
| Link pré-consulta (nutr.se/2d54f5) | ✅ | ✅ | ❌ | ❌ |
| Folha de preparo bioimpedância | ✅ (exceto gestante) | ❌ | ❌ | ❌ |
| Orientações + fotos | ❌ | ✅ | ❌ | ✅ |
| Info Body 3D | ❌ | ✅ | ❌ | ✅ |
| Link sessão online | ❌ | ⚠️ (enviado manual) | ❌ | ⚠️ (enviado manual) |

**Link da sessão online:** gerado manualmente pela secretária humana no WebDiet minutos antes do atendimento. A Val apenas avisa que "o link será enviado minutos antes do atendimento".

### URLs de arquivos

- Apresentação PDF: `https://drive.google.com/uc?export=download&id=11GhJ4PhO_qGzoRX0uszY5EnESJ5oad85`
- Folha de preparo (imagem): `https://drive.google.com/uc?export=download&id=1Bi_M9ZHlzaNfnpeEZ-ZR23p-e0mY-v8A`
- Formulário pré-consulta: `https://nutr.se/2d54f5`

### Regras de formatação (obrigatórias — Renata é cirúrgica com isso)

- Datas SEMPRE entre vírgulas: `segunda-feira, dia 14 de novembro,`
- Dias da semana SEMPRE com hífen: `segunda-feira`, `terça-feira`, etc.
- Horário cheio: `9 horas`, `14 horas` (NUNCA `9h` sozinho, NUNCA `9:00`)
- Horário quebrado: `9h30min`, `14h30min` (NUNCA `9:30`, NUNCA `9h30`)
- Tom profissional: usar `você`, `está`, `obrigada`. NUNCA `vc`, `tá`, `tbm`, `vlw`.
- **NUNCA emojis** — nem 😊, nem 🍊, nem nada. Zero emojis.
- **A secretária NÃO tem nome próprio.** Se apresenta como "secretária da nutricionista Renata, da Nutriskin".

### Coleta de dados (1 campo por mensagem — patch v3 em diante)

**1ª consulta** (presencial OU online): nome → data nascimento → CPF → altura → email → endereço → CEP → [só presencial: condição de saúde (pergunta neutra gestação/marca-passo/prótese)]

**Reconsulta** (presencial OU online): nome → CPF. Apenas isso.

### Handoff para Renata humana (Val NÃO responde)

- Dúvidas sobre dieta, alimentação, suplementação
- Resultado de exames
- Dúvidas médicas/nutricionais
- Pedidos de desconto
- Qualquer situação de dúvida

Mensagem padrão: "Recebi sua mensagem. Vou repassar à Renata e ela entrará em contato o mais breve possível."

### O que é RESPONSABILIDADE HUMANA (fora do escopo da Val)

- Postura na recepção (sorrir, olhar nos olhos, etc.)
- Limpeza da sala, café, água, nuts
- Anexar bios no WebDiet
- Imprimir folhas, organizar pastas
- Avisar nutricionista de intervalos
- Gerar e enviar link da sessão online no WebDiet
- Conferir agenda de manhã, lista de espera, boletos
- Conferir data da última consulta no WebDiet (Val pergunta ao paciente, não tem API)

---

## 5. BUGS CONHECIDOS E PADRÕES IMPORTANTES

### Gemini 2.5 Flash via OpenRouter tem 3 instabilidades conhecidas

1. **Omite o bloco `[DADOS]`** em respostas do Cérebro 1, às vezes totalmente, às vezes parcialmente. **Por isso TODO campo crítico tem fallback determinístico em `Extrair Dados`.** Nunca confiar 100% no LLM pra extração estruturada.
2. **SSE stream JSON errors** — reconexão resolve. Se persistir, é problema da OpenRouter.
3. **Timeouts longos** — retry quase sempre resolve. Se "canceled" aparecer, é concorrência (nova mensagem chegou antes da anterior terminar).

### Padrão: Deterministic > LLM para ações críticas

Qualquer ação irreversível (criar evento no Calendar, enviar mensagem crítica, atualizar estado no Postgres) DEVE ser feita em node determinístico, NÃO pelo LLM. O LLM gera texto conversacional; regex/code parseia e age.

Exemplos aplicados no workflow:
- `Extrair Dados` (Code) parseia `[DADOS]` + regex fallback
- `Detectar Agendamento` (Code) detecta confirmação por palavras-chave
- `Extrair Horário` (Code) parseia data/hora da mensagem, monta ISO datetime
- `Montar Confirmação` (Code) gera a mensagem final literal do checklist

### Timezone

- Workflow settings do n8n: `America/Sao_Paulo` (NÃO `America/New_York` — já deu bug disso uma vez, eventos saíam 1h adiantados)
- Google Calendar nodes (typeVersion 1.2) exigem ISO 8601 com offset explícito: `YYYY-MM-DDThh:mm:ss-03:00`

### Padrão `.first()` obrigatório

Em qualquer referência a nodes upstream dentro de HTTP Request nodes da Evolution (ou contextos multi-item), usar `.first()`, NUNCA `.item`. Senão dá "Multiple matching items".

Exemplo correto:
```javascript
$('Dados do Usuário').first().json.telefone
```

### Code nodes do n8n Cloud

- Timeout de sandbox: **60 segundos**
- **NUNCA usar `$('OutroNode').item` dentro de Code** — cross-reference é lento e pode causar timeout. Se precisar de dado de outro node, usar um node Postgres/Set antes do Code e ler via `$input.first().json`.

### Evolution API

- Endpoint: `https://powerfultick-evolution.cloudfy.live`
- Instância: `WhatsApp Testes` (case-sensitive, URL-encoded: `WhatsApp%20Testes`)
- Header obrigatório: `apikey: B142C6382DAA-412D-AF72-654DB3BC1864`
- Campo `number`: strip `@s.whatsapp.net` antes de enviar
- Google Drive URLs precisam ser formato `uc?export=download&id=FILE_ID`, não `file/d/.../view`

### Duplicate records no Supabase

Se deletar manualmente um registro de teste no meio de uma sessão ativa, o workflow pode criar múltiplos `session_id` diferentes pro mesmo telefone. Sempre usar `LIMIT 1` em queries de usuário. Se acontecer, limpar manualmente:
```sql
DELETE FROM dados_cliente WHERE session_id NOT IN (
  SELECT MIN(session_id) FROM dados_cliente GROUP BY telefone
);
```

---

## 6. FLUXO DE TRABALHO NESTE REPO

### Convenção de commits

```
feat: nova funcionalidade
fix: correção de bug  
chore: tarefas de infra/setup
docs: atualização de documentação
refactor: mudança de código sem mudar comportamento
```

### Padrão de branches

- `main` — estado sincronizado com n8n Cloud (o que está rodando)
- `patch/vN-descricao` — patches em desenvolvimento (ex: `patch/v4-tipo-consulta-fix`)
- Merge pra main SOMENTE depois de importar no n8n Cloud e validar com teste

### Workflow de alteração

1. Identificar qual node editar (ex: `Extrair Dados`)
2. Criar branch: `git checkout -b patch/vN-descricao`
3. Editar o node no JSON via `str_replace` (cirúrgico, não reescrever arquivo inteiro)
4. Validar JSON: `python -c "import json; json.load(open('workflows/val-principal.json'))"`
5. Commitar mudança
6. Pedro importa no n8n Cloud (Duplicate → Import from File, pra manter backup)
7. Pedro reconecta credenciais marcadas como missing
8. Pedro roda teste (1 cenário só por vez)
9. Se passar: `git checkout main && git merge patch/vN-descricao && git push`
10. Se falhar: Pedro manda execution ID, iteramos na branch

### Como debugar

Pedro me passa execution ID. Eu uso o MCP do n8n (`n8n:get_execution`) pra ler diretamente os outputs de cada node e diagnosticar sem screenshots.

Se MCP não funcionar, Pedro manda screenshot do execution + output do node problemático.

### Credenciais

**NUNCA** commitar credenciais em plaintext. API keys, tokens e senhas ficam:
- No n8n Cloud (credential IDs referenciados no JSON são ok — são só ponteiros)
- No arquivo local `.env` (adicionado ao `.gitignore`)
- No GitHub Secrets se for CI/CD

A `apikey` da Evolution está hardcoded em headers de HTTP Request nodes do workflow — isso é um débito técnico a resolver eventualmente, mas não é prioridade agora.

---

## 7. CONVENÇÕES DE COMUNICAÇÃO COM O PEDRO

Pedro já deixou claro nas preferências dele:
- Direto, estratégico, orientado a lucro
- Pensar como sócio de negócios experiente
- Priorizar faturamento, conversão, eficiência
- Soluções práticas, rápidas, aplicáveis
- Se houver erro ou ideia ruim, apontar sem rodeios
- Se houver oportunidade melhor, sugerir
- Objetivo, sem enrolação

Adicional do histórico:
- Ele prefere **diagnóstico cirúrgico** em vez de exploração. Se eu vou abrir 3 nodes pra entender algo, abrir 3 de uma vez, não 1 por vez.
- Ele fica frustrado quando o mesmo erro se repete. Preferir **correção na primeira tentativa**, mesmo que leve 2 minutos a mais pra pensar.
- Quando ele está cansado (trabalhando em várias frentes), eu devo **reduzir perguntas e tomar decisões com as informações que tenho**, explicando a decisão depois em 2 linhas.
- Ele trabalha **uma coisa de cada vez**. Propor mudanças arquiteturais antes de executar.
- Quando eu termino tarefa grande à noite, eu **sinalizo pra ele parar** e dou plano pro dia seguinte.

---

## 8. PRÓXIMAS TAREFAS EM ORDEM

1. ~~**[BLOQUEADOR]** Aplicar patch v4~~ — FEITO 14/04
2. ~~Importar no n8n Cloud e validar cenário 1ª presencial não-gestante~~ — FEITO 14/04
3. Gravar vídeo do teste aprovado pra mandar pra Renata
4. Validar os outros 4 cenários pendentes (1ª presencial gestante, 1ª online, reconsulta online, +12 meses)
5. Após Renata aprovar: migrar Evolution API `WhatsApp Testes` pro número real de produção
6. Adicionar coluna `condicao_saude` no Supabase da Renata (rodar ALTER TABLE)
7. Implementar alerta de 24h antes pra Renata gerar link da sessão online (quando ela voltar a testar e topar essa feature)
8. **[FUTURO]** Produtizar pra outros clientes: abstrair variáveis de configuração (valores, horários, URLs, nome da clínica) em tabela de config no Supabase

---

## 9. COMANDOS ÚTEIS

### Validar JSON de workflow
```powershell
python -c "import json; json.load(open('workflows/val-principal.json')); print('OK')"
```

### Ver diff das últimas mudanças num node específico
```powershell
# Por exemplo, ver o que mudou no jsCode de Extrair Dados
git log --all -p -- workflows/val-principal.json | Select-String -Context 0,30 '"name": "Extrair Dados"'
```

### Backup local antes de alteração arriscada
```powershell
Copy-Item workflows/val-principal.json workflows/backups/val-principal-$(Get-Date -Format 'yyyyMMdd-HHmmss').local.json
```

### Contar nodes no workflow
```powershell
python -c "import json; print(len(json.load(open('workflows/val-principal.json'))['nodes']))"
```
