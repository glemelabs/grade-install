# Instalador do GRADE Self-Hosted (Windows com Docker Desktop).
#
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# Feito para a escola instalar sozinha: instala o Docker Desktop se faltar,
# escolhe outras portas se as padrão estiverem ocupadas, sobe tudo e grava
# ACESSO.txt com o endereço e os comandos do dia a dia.
#
# Parâmetros opcionais: -Dir (padrão C:\GRADE), -Version (padrão 1), -Domain, -Email, -Source,
# -Registry (registro das imagens), -SkipPull (imagens já carregadas: pacote offline e testes),
# -NoDockerInstall (não instalar o Docker automaticamente), -HttpPort / -HttpsPort (portas fixas).
param(
  [string]$Dir = 'C:\GRADE',
  [string]$Version = '1',
  [string]$Domain = '',
  [string]$Email = '',
  [string]$Source = 'https://raw.githubusercontent.com/glemelabs/grade/main/infra/docker',
  [string]$Registry = 'ghcr.io/glemelabs',
  [switch]$SkipPull,
  [switch]$NoDockerInstall,
  [int]$HttpPort = 0,
  [int]$HttpsPort = 0,
  [int]$MinDiskGb = 10
)
$ErrorActionPreference = 'Stop'

function Say($message) { Write-Host "[grade] $message" -ForegroundColor Cyan }
function Warn($message) { Write-Host "[grade] $message" -ForegroundColor Yellow }
function Fail($message) { Write-Host "[grade] $message" -ForegroundColor Red; exit 1 }

# 1. Permissão de administrador
$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Fail 'Abra o PowerShell como administrador e rode de novo.' }

# 2. Docker Desktop (instala se faltar)
function Wait-DockerEngine($seconds) {
  for ($i = 0; $i -lt [int]($seconds / 5); $i++) {
    docker info 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return $true }
    Start-Sleep -Seconds 5
  }
  return $false
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  if ($NoDockerInstall) {
    Fail 'Docker não encontrado. Instale o Docker Desktop: https://www.docker.com/products/docker-desktop/'
  }
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail 'Docker não encontrado e o winget não está disponível. Instale o Docker Desktop: https://www.docker.com/products/docker-desktop/'
  }
  Say 'Docker Desktop não encontrado. Instalando (pode levar 10 minutos)...'
  winget install --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements --silent
  if ($LASTEXITCODE -ne 0) {
    Fail 'A instalação do Docker Desktop falhou. Instale manualmente: https://www.docker.com/products/docker-desktop/'
  }
  Say 'Docker Desktop instalado. Reinicie o computador e rode este instalador de novo.'
  Say '(o Windows precisa reiniciar para habilitar a virtualização usada pelo Docker)'
  exit 0
}

docker info 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  $exe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
  if (Test-Path $exe) {
    Say 'Iniciando o Docker Desktop...'
    Start-Process $exe | Out-Null
    if (-not (Wait-DockerEngine 180)) {
      Fail 'O Docker Desktop não ficou pronto. Abra-o, espere ficar verde ("Engine running") e rode de novo.'
    }
  } else {
    Fail 'O Docker Desktop não está em execução. Abra-o e tente novamente.'
  }
}
docker compose version | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'Docker Compose v2 não encontrado. Atualize o Docker Desktop.' }

# 3. Espaço em disco onde a instalação vai ficar
$drive = (Split-Path -Qualifier (Resolve-Path -LiteralPath (Split-Path -Parent $Dir) -ErrorAction SilentlyContinue).Path) `
  -replace ':', ''
if (-not $drive) { $drive = (Split-Path -Qualifier $Dir) -replace ':', '' }
$free = [math]::Floor(((Get-PSDrive -Name $drive -ErrorAction SilentlyContinue).Free) / 1GB)
if ($free -and $free -lt $MinDiskGb) {
  Fail "Espaco livre em ${drive}: ${free} GB (minimo $MinDiskGb GB, recomendado 20 GB). Libere espaco ou use -MinDiskGb."
}

# 4. Portas: usa 80/443 e, se estiverem ocupadas, cai para 8080/8443
function Test-PortBusy($port) {
  try { return [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) }
  catch { return $false }
}

if ($HttpPort -eq 0) {
  $HttpPort = 80
  if (Test-PortBusy 80) { $HttpPort = 8080; Warn "A porta 80 está ocupada; usando $HttpPort." }
}
if ($HttpsPort -eq 0) {
  $HttpsPort = 443
  if (Test-PortBusy 443) { $HttpsPort = 8443; Warn "A porta 443 está ocupada; usando $HttpsPort." }
}
if (Test-PortBusy $HttpPort) { Fail "A porta $HttpPort também está ocupada. Rode com -HttpPort <porta livre>." }
if (Test-PortBusy $HttpsPort) { Fail "A porta $HttpsPort também está ocupada. Rode com -HttpsPort <porta livre>." }

# 5. Arquivos
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Dir
foreach ($file in @('docker-compose.yml', 'Caddyfile')) {
  $local = Join-Path $here "..\docker\$file"
  if (Test-Path $local) { Copy-Item $local $file -Force }
  elseif (Test-Path (Join-Path $here $file)) { Copy-Item (Join-Path $here $file) $file -Force }
  else {
    Say "Baixando $file..."
    try { Invoke-WebRequest "$Source/$file" -OutFile $file -UseBasicParsing }
    catch { Fail "Não consegui baixar $file. Sem internet? Use o pacote offline." }
  }
}

# 6. Configuração
if (Test-Path '.env') {
  Say "Usando o .env existente em $Dir (senhas preservadas)."
} else {
  if (-not $Domain) {
    $default = $env:COMPUTERNAME.ToLower()
    $Domain = Read-Host "Endereço de acesso (domínio público ou nome/IP da rede local) [$default]"
    if (-not $Domain) { $Domain = $default }
  }
  $tls = 'internal'
  if ($Domain -match '\.' -and $Domain -notmatch '^[0-9.]+$') {
    if (-not $Email) { $Email = Read-Host "E-mail para o certificado Let's Encrypt (vazio = certificado interno)" }
    if ($Email) { $tls = $Email }
  }
  $online = Read-Host 'O servidor tem acesso à internet para ativar a licença? (s/n) [s]'
  $licenseOnline = if ($online -match '^[nN]') { '0' } else { '1' }
  $bytes = New-Object byte[] 30
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $password = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '')
  $appUrl = if ($HttpsPort -eq 443) { "https://$Domain" } else { "https://${Domain}:$HttpsPort" }
  @"
GRADE_VERSION=$Version
GRADE_REGISTRY=$Registry
DB_PASSWORD=$password
GRADE_DOMAIN=$Domain
GRADE_TLS=$tls
APP_URL=$appUrl
HTTP_PORT=$HttpPort
HTTPS_PORT=$HttpsPort
LICENSE_ONLINE=$licenseOnline
BACKUP_SCHEDULE=1
BACKUP_CRON=0 2 * * *
RETENTION_DAYS=30
SMTP_URL=
MAIL_FROM=GRADE <no-reply@$Domain>
"@ | Set-Content -Path '.env' -Encoding ascii
  Say "Configuração gravada em $Dir\.env (guarde uma cópia em local seguro)."
}

# 7. Subida
if ($SkipPull) {
  Say 'Usando as imagens já carregadas no Docker (-SkipPull).'
} else {
  Say 'Baixando o GRADE (pode levar alguns minutos)...'
  docker compose --env-file .env pull
  if ($LASTEXITCODE -ne 0) { Fail 'Não consegui baixar as imagens. Confira a internet ou use o pacote offline.' }
}
docker compose --env-file .env up -d
if ($LASTEXITCODE -ne 0) { Fail "Falha ao subir os containers. Veja: cd $Dir; docker compose logs" }

Say 'Aguardando a aplicação ficar pronta...'
$healthy = $false
for ($i = 0; $i -lt 90; $i++) {
  $id = docker compose ps -q web
  $status = docker inspect -f '{{.State.Health.Status}}' $id 2>$null
  if ($status -eq 'healthy') { $healthy = $true; break }
  Start-Sleep -Seconds 5
}
if (-not $healthy) { Fail "A aplicação não respondeu a tempo. Veja: cd $Dir; docker compose logs web" }

# 8. Comandos do dia a dia, gravados na própria pasta
$envDomain = ((Get-Content .env | Where-Object { $_ -like 'GRADE_DOMAIN=*' }) -replace 'GRADE_DOMAIN=', '')
$envTls = ((Get-Content .env | Where-Object { $_ -like 'GRADE_TLS=*' }) -replace 'GRADE_TLS=', '')
$url = if ($HttpsPort -eq 443) { "https://$envDomain" } else { "https://${envDomain}:$HttpsPort" }

@'
# Atualiza o GRADE para a versão mais recente da linha instalada.
Set-Location $PSScriptRoot
docker compose --env-file .env pull
docker compose --env-file .env up -d
Write-Host "GRADE atualizado."
'@ | Set-Content -Path 'atualizar.ps1' -Encoding utf8

@'
# Remove o GRADE. Os dados (banco e arquivos) são apagados: faça backup antes.
Set-Location $PSScriptRoot
$confirm = Read-Host "Apagar o GRADE e TODOS os dados desta instalacao? (digite APAGAR)"
if ($confirm -ne 'APAGAR') { Write-Host 'Cancelado.'; exit 1 }
docker compose --env-file .env down -v
Write-Host "GRADE removido. A pasta $PSScriptRoot pode ser apagada."
'@ | Set-Content -Path 'desinstalar.ps1' -Encoding utf8

$certNote = if ($envTls -eq 'internal') {
  "  O certificado e interno: o navegador pede para confirmar a excecao na primeira vez.`r`n"
} else { '' }
@"
GRADE - dados desta instalacao
Instalado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm')

Endereco:     $url
Pasta:        $Dir
Configuracao: $Dir\.env  (contem a senha do banco; guarde uma copia)

Primeiros passos
  1) Abra o endereco acima e crie o administrador e a escola.
  2) Em Configuracoes > Licenca, carregue o arquivo .lic recebido por e-mail.
$certNote
Dia a dia
  Atualizar:   powershell -ExecutionPolicy Bypass -File $Dir\atualizar.ps1
  Backup:      automatico todo dia as 2h (Configuracoes > Backup para baixar)
  Ver estado:  cd $Dir; docker compose ps
  Ver erros:   cd $Dir; docker compose logs web
  Desinstalar: powershell -ExecutionPolicy Bypass -File $Dir\desinstalar.ps1
"@ | Set-Content -Path 'ACESSO.txt' -Encoding utf8

Say "Pronto! Acesse $url"
Say '1) Crie o administrador e a instituição no assistente inicial.'
Say '2) Em Configurações > Licença, carregue o arquivo .lic e ative.'
if ($envTls -eq 'internal') { Say 'O certificado é interno: o navegador pedirá para confirmar a exceção na primeira vez.' }
Say "Resumo gravado em $Dir\ACESSO.txt"
