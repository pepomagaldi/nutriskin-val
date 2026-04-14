# ============================================================================
# Setup do repositório nutriskin-val
# Execute UMA VEZ a partir de D:\devnutriskin\
# ============================================================================

$ErrorActionPreference = "Stop"

# --- Verificações ---
Write-Host "=== Verificando ambiente ===" -ForegroundColor Cyan

try { node --version | Out-Null } catch { Write-Host "❌ Node.js não instalado" -ForegroundColor Red; exit 1 }
try { git --version  | Out-Null } catch { Write-Host "❌ Git não instalado" -ForegroundColor Red; exit 1 }

Write-Host "✅ Node e Git OK" -ForegroundColor Green

# --- Localização atual ---
$currentDir = Get-Location
Write-Host "Pasta atual: $currentDir" -ForegroundColor Yellow

if ($currentDir.Path -ne "D:\devnutriskin") {
  Write-Host "⚠️  Execute este script de dentro de D:\devnutriskin\" -ForegroundColor Red
  Write-Host "   cd D:\devnutriskin" -ForegroundColor Yellow
  exit 1
}

# --- Criar estrutura de pastas ---
Write-Host ""
Write-Host "=== Criando estrutura ===" -ForegroundColor Cyan

$folders = @("workflows", "workflows\backups", "sql", "docs", "scripts")
foreach ($f in $folders) {
  if (-not (Test-Path $f)) {
    New-Item -ItemType Directory -Path $f | Out-Null
    Write-Host "  📁 $f" -ForegroundColor Green
  } else {
    Write-Host "  📁 $f (já existe)" -ForegroundColor DarkGray
  }
}

# --- Mover JSONs existentes pra workflows/ ---
Write-Host ""
Write-Host "=== Organizando workflows ===" -ForegroundColor Cyan

$mainJson = Get-ChildItem -Filter "Nutriskin - Com checklist*.json" | Select-Object -First 1
$cronJson = Get-ChildItem -Filter "Nutriskin*Confirmação 48h*.json" | Select-Object -First 1

if ($mainJson) {
  Move-Item $mainJson.FullName "workflows\val-principal.json" -Force
  Write-Host "  ✅ val-principal.json" -ForegroundColor Green
} else {
  Write-Host "  ⚠️  Nutriskin - Com checklist.json NÃO encontrado — mova manualmente" -ForegroundColor Yellow
}

if ($cronJson) {
  Move-Item $cronJson.FullName "workflows\follow-up-48h.json" -Force
  Write-Host "  ✅ follow-up-48h.json" -ForegroundColor Green
} else {
  Write-Host "  ⚠️  Nutriskin — Confirmação 48h Consulta.json NÃO encontrado — mova manualmente" -ForegroundColor Yellow
}

# --- Criar .gitignore ---
Write-Host ""
Write-Host "=== Criando .gitignore ===" -ForegroundColor Cyan
@"
# Sensíveis
.env
.env.local
*.key
*.pem

# Node
node_modules/
npm-debug.log*

# OS
Thumbs.db
.DS_Store
desktop.ini

# IDE
.vscode/
.idea/

# Backups locais (workflows com credenciais plaintext)
workflows/backups/*.local.json

# Logs
*.log
"@ | Out-File -FilePath ".gitignore" -Encoding utf8
Write-Host "  ✅ .gitignore" -ForegroundColor Green

# --- Criar README.md placeholder ---
@"
# Nutriskin Val

Sistema de agendamento via WhatsApp para a clínica de nutrição Nutriskin (Porto Alegre).

Arquitetura: n8n Cloud + Evolution API + Supabase/Postgres + Google Calendar + Gemini 2.5 Flash (OpenRouter).

Ver ``CLAUDE.md`` para contexto completo do projeto.

## Estrutura

- ``workflows/`` — JSONs dos workflows n8n (fonte da verdade)
- ``sql/`` — scripts de schema Supabase/Postgres
- ``docs/`` — checklist da cliente, arquitetura, bugs conhecidos
- ``scripts/`` — helpers de sync entre local e n8n Cloud

## Workflows

- ``val-principal.json`` — workflow principal (ID n8n: E45e0ftLJNrE6UBl)
- ``follow-up-48h.json`` — cron de confirmação 48h antes (ID n8n: K8SyR6SZD6RPKphh)
"@ | Out-File -FilePath "README.md" -Encoding utf8
Write-Host "  ✅ README.md" -ForegroundColor Green

# --- Git init ---
Write-Host ""
Write-Host "=== Inicializando Git ===" -ForegroundColor Cyan

if (-not (Test-Path ".git")) {
  git init -b main | Out-Null
  Write-Host "  ✅ git init (branch: main)" -ForegroundColor Green
} else {
  Write-Host "  📦 Git já inicializado" -ForegroundColor DarkGray
}

# --- Primeiro commit ---
Write-Host ""
Write-Host "=== Primeiro commit ===" -ForegroundColor Cyan

git add . | Out-Null
$hasChanges = git diff --cached --name-only
if ($hasChanges) {
  git commit -m "chore: setup inicial do repositório nutriskin-val

Estado atual no n8n Cloud (ponto zero):
- val-principal.json = v3 (com bug do tipo_consulta vazio não corrigido)
- follow-up-48h.json = cron de confirmação 48h antes

Próximo passo: aplicar patch v4 (fix tipo_consulta + fallback modalidade)
e validar cenário 1ª presencial não-gestante." | Out-Null
  Write-Host "  ✅ Commit inicial criado" -ForegroundColor Green
} else {
  Write-Host "  ⏭️  Nada pra commitar" -ForegroundColor DarkGray
}

# --- Final ---
Write-Host ""
Write-Host "╔════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║       SETUP LOCAL CONCLUÍDO COM SUCESSO        ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "PRÓXIMOS PASSOS:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Criar repositório PRIVADO no GitHub:" -ForegroundColor White
Write-Host "   https://github.com/new" -ForegroundColor Yellow
Write-Host "   Nome: nutriskin-val" -ForegroundColor Yellow
Write-Host "   Privacidade: Private" -ForegroundColor Yellow
Write-Host "   NÃO inicialize com README/gitignore (já criamos)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "2. Conectar repo local ao GitHub (troca SEU_USUARIO):" -ForegroundColor White
Write-Host "   git remote add origin https://github.com/SEU_USUARIO/nutriskin-val.git" -ForegroundColor Yellow
Write-Host "   git push -u origin main" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. Instalar Claude Code globalmente:" -ForegroundColor White
Write-Host "   npm install -g @anthropic-ai/claude-code" -ForegroundColor Yellow
Write-Host ""
Write-Host "4. Rodar Claude Code dentro da pasta:" -ForegroundColor White
Write-Host "   claude" -ForegroundColor Yellow
Write-Host ""
Write-Host "Me avise quando chegar no passo 4 que a gente continua." -ForegroundColor Cyan
