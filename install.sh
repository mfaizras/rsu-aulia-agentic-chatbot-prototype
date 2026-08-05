#!/usr/bin/env bash
#
# Instaler RSU Aulia - Deployment Stack
# Untuk Linux (Ubuntu/Debian, dan distro lain dengan bash + docker).
#
# Stack:
#   - reverse-proxy/  : Traefik global (HTTPS Let's Encrypt, port 80/443)
#   - compose.yaml    : PostgreSQL+pgvector, web service, Telegram agent
#
# Repo aplikasi (submodule git):
#   - rsu-aulia-agentic
#   - rsu-aulia-web-service
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Warna & helper
# ---------------------------------------------------------------------------
C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'
C_CYAN=$'\033[1;36m'
C_RESET=$'\033[0m'

info()  { printf '%s[INFO]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok()    { printf '%s[OK]%s %s\n'   "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
fail()  { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# 1. Cek prasyarat
# ---------------------------------------------------------------------------
info "Memeriksa prasyarat..."

command -v docker >/dev/null 2>&1 || fail "Docker tidak ditemukan. Install dahulu: https://docs.docker.com/engine/install/"
command -v git    >/dev/null 2>&1 || fail "Git tidak ditemukan. Install dahulu: sudo apt install git"

if ! docker compose version >/dev/null 2>&1; then
  fail "Docker Compose v2 tidak ditemukan. Pastikan plugin compose terpasang."
fi

if ! docker info >/dev/null 2>&1; then
  fail "Docker daemon tidak berjalan. Jalankan service docker dahulu (sudo systemctl start docker)."
fi

ok "Prasyarat terpenuhi (docker $(docker --version | awk '{print $3}' | tr -d ','), $(docker compose version | head -1))."

# ---------------------------------------------------------------------------
# 2. Submodule aplikasi
# ---------------------------------------------------------------------------
if [ -n "${SKIP_SUBMODULES:-}" ]; then
  info "Melewati inisialisasi submodule (SKIP_SUBMODULES aktif)."
elif [ -d "rsu-aulia-agentic/.git" ] && [ -d "rsu-aulia-web-service/.git" ]; then
  info "Submodule aplikasi sudah ada, memperbarui..."
  git submodule update --init --recursive
else
  info "Menginisialisasi submodule aplikasi (rsu-aulia-agentic, rsu-aulia-web-service)..."
  git submodule update --init --recursive || fail "Gagal mengambil submodule. Periksa koneksi internet."
fi
ok "Submodule aplikasi siap."

# ---------------------------------------------------------------------------
# 3. Membuat / melengkapi file .env
# ---------------------------------------------------------------------------
set_env() {
  local key="$1" val="$2" file="$3"
  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}

read_env() {
  local key="$1" default="$2" file="$3"
  local current
  current="$(grep "^${key}=" "$file" | head -1 | cut -d'=' -f2- || true)"
  if [ -n "$current" ]; then
    printf '%s' "$current"
    return
  fi
  printf '%s' "$default"
}

prompt_env() {
  local key="$1" default="$2" file="$3" msg="$4"
  local current input
  current="$(read_env "$key" "$default" "$file")"
  printf '%s [%s]: ' "$msg" "$current"
  read -r input || true
  if [ -z "$input" ]; then input="$current"; fi
  set_env "$key" "$input" "$file"
}

if [ ! -f .env ]; then
  warn ".env belum ada, membuat dari .env.example..."
  cp .env.example .env
fi

RAND_PW="$(openssl rand -hex 24 2>/dev/null || echo "$(date +%s%N | sha256sum | head -c 32)")"

info "Konfigurasi aplikasi (.env):"
prompt_env "DOMAIN"          "$(read_env DOMAIN "contoh.domain.com" .env)" .env "Domain (tanpa http/https)"
prompt_env "POSTGRES_PASSWORD" "$RAND_PW" .env "Password database PostgreSQL"
prompt_env "SECRET_KEY"      "$RAND_PW" .env "Secret key aplikasi"
prompt_env "OPENAI_API_KEY"  "" .env "OpenAI API Key"
prompt_env "TELEGRAM_BOT_TOKEN" "" .env "Telegram bot token"
ok "File .env siap."

if [ ! -f reverse-proxy/.env ]; then
  warn "reverse-proxy/.env belum ada, membuat dari .env.example..."
  cp reverse-proxy/.env.example reverse-proxy/.env
fi

info "Konfigurasi reverse proxy (reverse-proxy/.env):"
prompt_env "ACME_EMAIL"      "$(read_env ACME_EMAIL "admin@domain-anda.com" reverse-proxy/.env)" reverse-proxy/.env "Email Let's Encrypt"
ok "File reverse-proxy/.env siap."

# ---------------------------------------------------------------------------
# 4. Jaringan proxy (dibuat otomatis oleh reverse-proxy compose)
# ---------------------------------------------------------------------------
if ! docker network inspect proxy >/dev/null 2>&1; then
  info "Shared network 'proxy' belum ada. Network akan dibuat oleh Traefik stack."
else
  ok "Shared network 'proxy' sudah ada."
fi

# ---------------------------------------------------------------------------
# 5. Menjalankan stack
# ---------------------------------------------------------------------------
info "Menjalankan reverse proxy (Traefik)..."
docker compose -f reverse-proxy/compose.yaml up -d

info "Menjalankan stack aplikasi (database + web + agent)..."
docker compose up -d --build

info "Menunggu service siap (maks 120 detik)..."
for i in $(seq 1 24); do
  sleep 5
  STATUS="$(docker compose ps --format '{{.Service}}={{.Health}}' 2>/dev/null || true)"
  if echo "$STATUS" | grep -q "healthy" && [ "$(echo "$STATUS" | grep -c "healthy")" -eq "$(echo "$STATUS" | wc -l)" ]; then
    ok "Semua service healthy."
    break
  fi
done

echo
docker compose ps

# ---------------------------------------------------------------------------
# 6. Membuat admin pertama
# ---------------------------------------------------------------------------
if [ -f rsu-aulia-web-service/scripts/create_admin.py ]; then
  echo
  info "Membuat user admin web service."
  read -r -p "Username admin [admin]: " ADMIN_USER || true
  ADMIN_USER="${ADMIN_USER:-admin}"
  while :; do
    read -r -s -p "Password admin (min 8 karakter): " ADMIN_PASS || true
    echo
    if [ -n "$ADMIN_PASS" ] && [ "${#ADMIN_PASS}" -ge 8 ]; then break; fi
    warn "Password terlalu pendek, ulangi."
  done
  docker compose exec -T web python scripts/create_admin.py "$ADMIN_USER" "$ADMIN_PASS" \
    || warn "Gagal membuat admin. Buat manual: docker compose exec web python scripts/create_admin.py <user> <pass>"
  ok "Admin '$ADMIN_USER' dibuat."
fi

# ---------------------------------------------------------------------------
# Ringkasan
# ---------------------------------------------------------------------------
DOMAIN_VAL="$(read_env DOMAIN "" .env)"
echo
ok "======================================================"
ok " Instalasi selesai!"
ok " Domain          : https://${DOMAIN_VAL}"
ok " Dashboard web   : https://${DOMAIN_VAL}/admin (jika tersedia)"
ok "======================================================"
info "Perintah berguna:"
info "  docker compose ps                  # status aplikasi"
info "  docker compose logs -f             # log aplikasi"
info "  docker compose -f reverse-proxy/compose.yaml ps   # status traefik"
info "  docker compose exec web python scripts/add_data.py  # import data opsional"
