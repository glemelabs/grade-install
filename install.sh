#!/usr/bin/env bash
# Instalador do GRADE Self-Hosted (Linux).
#
#   curl -fsSL https://raw.githubusercontent.com/glemelabs/grade-install/main/install.sh -o install.sh && sudo bash install.sh
#   # ou, a partir do pacote baixado:  sudo ./install.sh
#
# Feito para a escola instalar sozinha: instala o Docker se faltar, escolhe
# outras portas se as padrão estiverem ocupadas, confere disco e memória, sobe
# tudo e grava ACESSO.txt com o endereço e os comandos do dia a dia.
#
# Variáveis opcionais: GRADE_DIR (padrão /opt/grade), GRADE_VERSION (padrão 1),
# GRADE_DOMAIN, GRADE_EMAIL (Let's Encrypt), GRADE_SOURCE (URL dos arquivos),
# GRADE_NONINTERACTIVE=1 (aceita os padrões sem perguntar),
# GRADE_REGISTRY (registro das imagens; padrão ghcr.io/glemelabs),
# GRADE_SKIP_PULL=1 (imagens já presentes: pacote offline e homologação no CI),
# GRADE_INSTALL_DOCKER=0 (não instalar o Docker automaticamente),
# GRADE_HTTP_PORT / GRADE_HTTPS_PORT (portas fixas, sem escolha automática),
# GRADE_MIN_DISK_GB (espaço livre mínimo; padrão 10).
set -euo pipefail

GRADE_DIR=${GRADE_DIR:-/opt/grade}
GRADE_VERSION=${GRADE_VERSION:-1}
GRADE_SOURCE=${GRADE_SOURCE:-https://raw.githubusercontent.com/glemelabs/grade-install/main}
GRADE_REGISTRY=${GRADE_REGISTRY:-ghcr.io/glemelabs}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo .)

say() { printf '\033[1;34m[grade]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[grade]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[grade] %s\033[0m\n' "$*" >&2; exit 1; }
ask() {
  local prompt=$1 default=$2 answer
  if [[ "${GRADE_NONINTERACTIVE:-0}" == "1" || ! -t 0 ]]; then echo "$default"; return; fi
  read -r -p "$prompt [$default]: " answer </dev/tty || true
  echo "${answer:-$default}"
}

# 1. Permissão
[[ "$(id -u)" == "0" ]] || fail "Rode como administrador: sudo bash $0"

# 2. Docker (instala se faltar)
install_docker() {
  [[ "${GRADE_INSTALL_DOCKER:-1}" == "1" ]] ||
    fail "Docker não encontrado e a instalação automática está desligada. Instale: https://docs.docker.com/engine/install/"
  say "Docker não encontrado. Instalando (alguns minutos)..."
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh ||
    fail "Não consegui baixar o instalador do Docker. Sem internet? Instale o Docker e rode de novo."
  sh /tmp/get-docker.sh || fail "A instalação do Docker falhou. Instale manualmente: https://docs.docker.com/engine/install/"
  rm -f /tmp/get-docker.sh
  systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
  command -v docker >/dev/null 2>&1 || fail "Docker instalado, mas não encontrado no PATH. Reinicie o servidor e rode de novo."
  say "Docker instalado."
}

command -v docker >/dev/null 2>&1 || install_docker
docker info >/dev/null 2>&1 || {
  say "Iniciando o Docker..."
  systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
  sleep 5
}
docker info >/dev/null 2>&1 || fail "O Docker não está em execução. Inicie com: systemctl start docker"
docker compose version >/dev/null 2>&1 ||
  fail "Docker Compose v2 não encontrado. Atualize o Docker: https://docs.docker.com/engine/install/"

# 3. Recursos da máquina (o disco é medido onde a instalação vai ficar)
mkdir -p "$GRADE_DIR"
MIN_DISK_GB=${GRADE_MIN_DISK_GB:-10}
CPUS=$(nproc 2>/dev/null || echo 2)
MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 4096)
DISK_GB=$(df -BG --output=avail "$GRADE_DIR" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 20)
(( CPUS >= 2 )) || warn "Recomendado 2 vCPU (encontrado: $CPUS). As gerações vão demorar mais."
(( MEM_MB >= 3500 )) || warn "Recomendado 4 GB de RAM (encontrado: ${MEM_MB} MB). As gerações podem falhar por memória."
(( DISK_GB >= MIN_DISK_GB )) || fail "Espaço livre em $GRADE_DIR: ${DISK_GB} GB (mínimo ${MIN_DISK_GB} GB, recomendado 20 GB). Libere espaço ou rode com GRADE_MIN_DISK_GB=<valor>."

# 4. Portas: usa 80/443 e, se estiverem ocupadas, cai para 8080/8443
port_busy() {
  local port=$1
  if command -v ss >/dev/null 2>&1; then
    ss -Hltn "sport = :$port" 2>/dev/null | grep -q . && return 0
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | grep -qE "[:.]${port}[[:space:]]" && return 0
  fi
  return 1
}

HTTP_PORT=${GRADE_HTTP_PORT:-80}
HTTPS_PORT=${GRADE_HTTPS_PORT:-443}
if [[ -z "${GRADE_HTTP_PORT:-}" ]] && port_busy 80; then
  HTTP_PORT=8080
  warn "A porta 80 está ocupada; usando $HTTP_PORT."
fi
if [[ -z "${GRADE_HTTPS_PORT:-}" ]] && port_busy 443; then
  HTTPS_PORT=8443
  warn "A porta 443 está ocupada; usando $HTTPS_PORT."
fi
port_busy "$HTTP_PORT" && fail "A porta $HTTP_PORT também está ocupada. Rode com GRADE_HTTP_PORT=<porta livre>."
port_busy "$HTTPS_PORT" && fail "A porta $HTTPS_PORT também está ocupada. Rode com GRADE_HTTPS_PORT=<porta livre>."

# 5. Arquivos
cd "$GRADE_DIR"
for file in docker-compose.yml Caddyfile; do
  if [[ -f "$SCRIPT_DIR/../docker/$file" ]]; then
    cp "$SCRIPT_DIR/../docker/$file" "$file"
  elif [[ -f "$SCRIPT_DIR/$file" ]]; then
    cp "$SCRIPT_DIR/$file" "$file"
  else
    say "Baixando $file..."
    curl -fsSL "$GRADE_SOURCE/$file" -o "$file" ||
      fail "Não consegui baixar $file de $GRADE_SOURCE. Sem internet? Use o pacote offline."
  fi
done

# 6. Configuração (.env) — preservada em reinstalações
if [[ -f .env ]]; then
  say "Usando o .env existente em $GRADE_DIR (senhas preservadas)."
else
  DEFAULT_HOST=$(hostname -I 2>/dev/null | awk '{print $1}')
  DOMAIN=${GRADE_DOMAIN:-$(ask "Endereço de acesso (domínio público ou IP/nome da rede local)" "${DEFAULT_HOST:-localhost}")}
  if [[ "$DOMAIN" =~ ^[0-9.]+$ || "$DOMAIN" == "localhost" || "$DOMAIN" != *.* ]]; then
    TLS=internal
  else
    EMAIL=${GRADE_EMAIL:-$(ask "E-mail para o certificado Let's Encrypt (vazio = certificado interno)" "")}
    TLS=${EMAIL:-internal}
  fi
  ONLINE=$(ask "O servidor tem acesso à internet para ativar a licença? (s/n)" "s")
  DB_PASSWORD=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40)
  umask 077
  cat > .env <<ENV
GRADE_VERSION=$GRADE_VERSION
GRADE_REGISTRY=$GRADE_REGISTRY
DB_PASSWORD=$DB_PASSWORD
GRADE_DOMAIN=$DOMAIN
GRADE_TLS=$TLS
APP_URL=https://$DOMAIN$([[ "$HTTPS_PORT" == "443" ]] || echo ":$HTTPS_PORT")
HTTP_PORT=$HTTP_PORT
HTTPS_PORT=$HTTPS_PORT
LICENSE_ONLINE=$([[ "$ONLINE" =~ ^[sSyY] ]] && echo 1 || echo 0)
BACKUP_SCHEDULE=1
BACKUP_CRON=0 2 * * *
RETENTION_DAYS=30
SMTP_URL=
MAIL_FROM=GRADE <no-reply@$DOMAIN>
ENV
  say "Configuração gravada em $GRADE_DIR/.env (guarde uma cópia em local seguro)."
fi

# 7. Subida
if [[ "${GRADE_SKIP_PULL:-0}" == "1" ]]; then
  say "Usando as imagens já carregadas no Docker (GRADE_SKIP_PULL=1)."
else
  say "Baixando o GRADE (pode levar alguns minutos)..."
  docker compose --env-file .env pull ||
    fail "Não consegui baixar as imagens. Confira a internet ou use o pacote offline."
fi
docker compose --env-file .env up -d ||
  fail "Falha ao subir os containers. Veja o que aconteceu com: cd $GRADE_DIR && docker compose logs"

say "Aguardando a aplicação ficar pronta..."
for _ in $(seq 1 90); do
  STATUS=$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q web)" 2>/dev/null || echo starting)
  [[ "$STATUS" == "healthy" ]] && break
  sleep 5
done
[[ "${STATUS:-}" == "healthy" ]] ||
  fail "A aplicação não respondeu a tempo. Veja: cd $GRADE_DIR && docker compose logs web"

# Lê só o que precisamos: `source .env` quebraria em linhas como
# BACKUP_CRON=0 2 * * * (o shell tentaria executá-las).
env_value() { sed -n "s/^$1=//p" .env | head -1; }
GRADE_DOMAIN=$(env_value GRADE_DOMAIN)
GRADE_TLS=$(env_value GRADE_TLS)
URL="https://$GRADE_DOMAIN"
[[ "$HTTPS_PORT" == "443" ]] || URL="$URL:$HTTPS_PORT"
curl -fsSk "$URL/api/health" >/dev/null 2>&1 ||
  warn "A aplicação subiu, mas não respondeu em $URL. Se houver firewall, libere as portas $HTTP_PORT e $HTTPS_PORT."

# 8. Comandos do dia a dia, gravados na própria pasta
cat > atualizar.sh <<'UPD'
#!/usr/bin/env bash
# Atualiza o GRADE para a versão mais recente da linha instalada.
set -euo pipefail
cd "$(dirname "$0")"
docker compose --env-file .env pull
docker compose --env-file .env up -d
echo "GRADE atualizado."
UPD
cat > desinstalar.sh <<'DEL'
#!/usr/bin/env bash
# Remove o GRADE. Os dados (banco e arquivos) são apagados: faça backup antes.
set -euo pipefail
cd "$(dirname "$0")"
read -r -p "Apagar o GRADE e TODOS os dados desta instalação? (digite APAGAR): " confirm
[[ "$confirm" == "APAGAR" ]] || { echo "Cancelado."; exit 1; }
docker compose --env-file .env down -v
echo "GRADE removido. A pasta $(pwd) pode ser apagada."
DEL
chmod +x atualizar.sh desinstalar.sh

cat > ACESSO.txt <<TXT
GRADE — dados desta instalação
Instalado em: $(date '+%d/%m/%Y %H:%M')

Endereço:     $URL
Pasta:        $GRADE_DIR
Configuração: $GRADE_DIR/.env  (contém a senha do banco; guarde uma cópia)

Primeiros passos
  1) Abra o endereço acima e crie o administrador e a escola.
  2) Em Configurações › Licença, carregue o arquivo .lic recebido por e-mail.
$([[ "$GRADE_TLS" == "internal" ]] && echo "  O certificado é interno: o navegador pede para confirmar a exceção na primeira vez.")

Dia a dia
  Atualizar:   sudo bash $GRADE_DIR/atualizar.sh
  Backup:      automático todo dia às 2h (Configurações › Backup para baixar)
  Ver estado:  cd $GRADE_DIR && docker compose ps
  Ver erros:   cd $GRADE_DIR && docker compose logs web
  Desinstalar: sudo bash $GRADE_DIR/desinstalar.sh
TXT
chmod 600 ACESSO.txt

say "Pronto! Acesse $URL"
say "1) Crie o administrador e a instituição no assistente inicial."
say "2) Em Configurações › Licença, carregue o arquivo .lic e ative."
[[ "$GRADE_TLS" == "internal" ]] && say "O certificado é interno: o navegador pedirá para confirmar a exceção na primeira vez."
say "Resumo gravado em $GRADE_DIR/ACESSO.txt"
