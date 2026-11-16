#!/usr/bin/env bash
# FORMA WEB: simple, non-destructive Self-SNI website setup for 3x-ui / REALITY.
# Never edits Xray, 3x-ui, SSH, panel ports or other sites. May open TCP/80 in an active firewall with consent.
set -Eeuo pipefail

readonly BLUE='\033[1;34m' GREEN='\033[1;32m' YELLOW='\033[1;33m' RED='\033[1;31m' RESET='\033[0m'
info() { printf '\n%b%s%b\n' "$BLUE" "==> $*" "$RESET"; }
pass() { printf '%b%s%b\n' "$GREEN" "[OK] $*" "$RESET"; }
warn() { printf '%b%s%b\n' "$YELLOW" "[!] $*" "$RESET" >&2; }
die() { printf '%b%s%b\n' "$RED" "[ОШИБКА] $*" "$RESET" >&2; exit 1; }
help_text() {
cat <<'USAGE'
FORMA WEB / Self-SNI: установка настоящего сайта на свободный локальный HTTPS-порт

Использование:
  sudo bash install.sh
  sudo bash install.sh --domain site.example.com --email me@example.com
  sudo bash install.sh --domain site.example.com --email me@example.com --contact-email contact@example.com
  sudo bash install.sh --target-port 9443 --firewall allow --firewall-443 allow

Флаги: --target-port PORT (по умолчанию выбрать свободный автоматически)
       --firewall ask|allow|skip (доступ к TCP/80 для Let's Encrypt)
       --firewall-443 ask|allow|skip (отдельное разрешение TCP/443 для REALITY)
После установки программа покажет настройки для существующего REALITY inbound.
Xray и 3x-ui НЕ изменяются автоматически.
USAGE
}

DOMAIN='' EMAIL='' CONTACT_EMAIL='' CONTACT_ASK=1 TARGET_PORT='' FIREWALL_MODE='ask' FIREWALL_443_MODE='ask'
while (($#)); do
  case "$1" in
    --domain) (($#>=2)) || die 'Пропущен домен после --domain'; DOMAIN="$2"; shift 2;;
    --email) (($#>=2)) || die 'Пропущен email после --email'; EMAIL="$2"; shift 2;;
    --contact-email) (($#>=2)) || die 'Пропущен email после --contact-email'; CONTACT_EMAIL="$2"; CONTACT_ASK=0; shift 2;;
    --target-port) (($#>=2)) || die 'Пропущен порт после --target-port'; TARGET_PORT="$2"; shift 2;;
    --firewall) (($#>=2)) || die 'Пропущен режим после --firewall'; FIREWALL_MODE="$2"; shift 2;;
    --firewall-443) (($#>=2)) || die 'Пропущен режим после --firewall-443'; FIREWALL_443_MODE="$2"; shift 2;;
    --help|-h) help_text; exit 0;;
    *) die "Неизвестный аргумент: $1";;
  esac
done

[[ "$FIREWALL_MODE" == 'ask' || "$FIREWALL_MODE" == 'allow' || "$FIREWALL_MODE" == 'skip' ]] || die 'Для --firewall доступны ask, allow или skip.'
[[ "$FIREWALL_443_MODE" == 'ask' || "$FIREWALL_443_MODE" == 'allow' || "$FIREWALL_443_MODE" == 'skip' ]] || die 'Для --firewall-443 доступны ask, allow или skip.'
[[ -z "$TARGET_PORT" || ( "$TARGET_PORT" =~ ^[0-9]+$ && ${#TARGET_PORT} -le 5 ) ]] || die 'Для --target-port требуется число 1024–65535.'
if [[ -n "$TARGET_PORT" ]]; then
  ((10#$TARGET_PORT >= 1024 && 10#$TARGET_PORT <= 65535)) || die 'Для --target-port требуется число 1024–65535.'
  TARGET_PORT="$((10#$TARGET_PORT))"
fi
[[ $EUID -eq 0 ]] || die 'Запусти от root через sudo.'
[[ -f /etc/os-release ]] || die 'Не могу определить систему Linux.'
# shellcheck source=/dev/null
source /etc/os-release
case "${ID:-}" in ubuntu|debian) ;; *) die 'Поддерживаются только Ubuntu и Debian.';; esac
command -v systemctl >/dev/null || die 'Нужна система с systemd.'
pass "Обнаружена система: ${PRETTY_NAME:-${ID:-Linux}}"
if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "26.04" ]]; then
  pass 'Основная система: Ubuntu Server 26.04 LTS (Resolute), Nginx 1.28.x и Certbot 4.x из apt.'
elif [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]]; then
  pass 'Совместимый режим: Ubuntu 24.04 LTS, Nginx 1.24.x и Certbot из apt.'
elif [[ "${ID:-}" == "ubuntu" ]]; then
  warn "Ubuntu ${VERSION_ID:-неизвестная}: установка по общей схеме без отдельной проверки. Основная система — Ubuntu 26.04 LTS."
fi
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[[ -f "$HERE/site/index.html" && -f "$HERE/site/assets/style.css" ]] || die 'Файлы сайта отсутствуют рядом с install.sh.'

# Ask directly in the current shell. Command substitution ($(ask ...))
# starts another Bash process and can interfere with terminal input in curl|bash.
ask() {
  local __target="$1" __prompt="$2" __value
  [[ -r /dev/tty ]] || die 'Нет терминала для ввода. Передай --domain и --email.'
  printf '%s' "$__prompt" > /dev/tty
  IFS= read -r __value < /dev/tty || die 'Не удалось прочитать ввод из терминала.'
  printf -v "$__target" '%s' "$__value"
}

printf '\n%bFORMA WEB — мастер установки сайта для Self-SNI / Self-Steal%b\n' "$BLUE" "$RESET"
info 'План: домен и email -> HTTP/80 и сертификат -> внутренний HTTPS -> инструкция по Xray/REALITY'
warn 'Публичный https://ДОМЕН заработает только после настройки VLESS + REALITY на TCP/443 в 3x-ui.'
warn 'Для сайта Nginx слушает только 127.0.0.1:ВНУТРЕННИЙ_ПОРТ. Не открывай этот внутренний порт наружу.'
[[ -n "$DOMAIN" ]] || ask DOMAIN 'Домен сайта (например, site.example.com): '
DOMAIN="$(printf '%s' "$DOMAIN" | tr '[:upper:]' '[:lower:]')"
[[ ${#DOMAIN} -le 253 && "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || die 'Введи корректный домен без https://, пробелов и путей.'
[[ "$DOMAIN" != *.example && "$DOMAIN" != *.localhost && "$DOMAIN" != *.invalid ]] || die 'Нужен настоящий зарегистрированный домен.'
[[ -n "$EMAIL" ]] || ask EMAIL "Email для уведомлений Let's Encrypt: "
[[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || die 'Некорректный email.'
if ((CONTACT_ASK)); then
  ask reply 'Показывать этот email на сайте для связи? [д/Н]: '
  case "${reply,,}" in д|да|y|yes) CONTACT_EMAIL="$EMAIL";; *) CONTACT_EMAIL='';; esac
fi
if [[ -n "$CONTACT_EMAIL" && ! "$CONTACT_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  die 'Некорректный контактный email.'
fi

WEBROOT="/var/www/forma-selfsteal/$DOMAIN"
CONF="/etc/nginx/conf.d/forma-selfsteal-${DOMAIN}.conf"
HOOK='/etc/letsencrypt/renewal-hooks/deploy/80-forma-selfsteal-nginx-reload.sh'
[[ ! -e "$CONF" ]] || die "Сайт $DOMAIN уже имеет конфигурацию $CONF. Не запускай установку повторно — проверь через: sudo forma-web-check $DOMAIN"
[[ ! -e "$WEBROOT" ]] || die "Папка $WEBROOT уже существует. Не перезаписываем файлы. Проверь через: sudo forma-web-check $DOMAIN"

info 'Проверяем занятые порты'
command -v ss >/dev/null || die 'Нужна утилита ss. Установи пакет iproute2 и повтори.'
port_busy() { ss -H -ltn "( sport = :$1 )" | grep -q .; }
if [[ -n "$TARGET_PORT" ]]; then
  port_busy "$TARGET_PORT" && die "Локальный HTTPS-порт $TARGET_PORT уже занят. Выбери другой --target-port."
else
  for candidate in 8443 9443 10443 11443 18443; do
    if port_busy "$candidate"; then
      warn "Внутренний порт $candidate уже занят. Ищем следующий свободный порт."
      ss -H -ltnp "( sport = :$candidate )" >&2 || true
    else
      TARGET_PORT="$candidate"
      break
    fi
  done
  [[ -n "$TARGET_PORT" ]] || die 'Все внутренние HTTPS-порты заняты: 8443, 9443, 10443, 11443, 18443.'
fi
pass "Выбран свободный локальный HTTPS-порт: ${TARGET_PORT}"
if command -v ss >/dev/null; then
  if ss -H -ltn '( sport = :80 )' | grep -q .; then
    if ! systemctl is-active --quiet nginx 2>/dev/null; then
      die 'Порт 80 занят не Nginx. Не будем останавливать существующие службы.'
    fi
    warn 'Порт 80 обслуживает Nginx: добавим отдельный серверный блок для нового домена.'
  fi
fi

info 'Проверяем DNS и публичный IP'
if ! command -v curl >/dev/null; then
  warn 'curl отсутствует: сначала установим его.'
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates
fi
PUBLIC_IP="$(curl -4fsS --connect-timeout 7 --max-time 15 https://api.ipify.org || true)"
[[ "$PUBLIC_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die 'Не удалось определить публичный IPv4 сервера.'
# DuckDNS and some VPS resolvers may stall; do not appear frozen forever.
mapfile -t DNS_IPS < <(timeout 12 getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u)
if ((${#DNS_IPS[@]}!=1)) || [[ "${DNS_IPS[0]:-}" != "$PUBLIC_IP" ]]; then
  printf 'IPv4 сервера: %s\nA-запись домена: %s\n' "$PUBLIC_IP" "${DNS_IPS[*]:-(не найдена)}" >&2
  die "Настрой DNS A: ${DOMAIN} -> ${PUBLIC_IP}. Для DuckDNS проверь IPv4 в панели. Дождись обновления DNS и повтори установку."
fi
pass "DNS A: $DOMAIN -> $PUBLIC_IP"

info 'Устанавливаем Nginx и Certbot из официальных репозиториев apt'
apt-get update -qq
# Certbot is packaged in Ubuntu's "universe" component, including 26.04 LTS.
# Never change apt sources automatically: they may be managed by the VPS provider.
if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "26.04" ]] && ! apt-cache show certbot >/dev/null 2>&1; then
  die 'На Ubuntu 26.04 пакет certbot не найден. Проверь доступность репозитория universe (sudo add-apt-repository universe; sudo apt update) и повтори установку.'
fi
if ! DEBIAN_FRONTEND=noninteractive apt-get install -y nginx certbot ca-certificates; then
  die 'Не удалось установить nginx/certbot. Проверь интернет, apt и репозиторий universe (для Ubuntu 26.04/24.04).'
fi
command -v nginx >/dev/null || die 'Nginx не установлен.'
command -v certbot >/dev/null || die 'Certbot не установлен.'
pass "Nginx: $(nginx -v 2>&1)"
pass "Certbot: $(certbot --version 2>&1)"

# Reject existing configuration for this exact hostname, including sites-enabled.
if { grep -RFl --include='*.conf' --include='default' "server_name $DOMAIN" /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null || true; } | grep -q .; then
  die "Nginx уже содержит server_name ${DOMAIN}. Исправь конфликт вручную."
fi
if command -v ss >/dev/null && ss -H -ltn '( sport = :80 )' | grep -q . && ! systemctl is-active --quiet nginx; then
  die 'TCP/80 занят другим сервисом.'
fi

# On any failure, remove only files created by this installer. All pre-existing services remain untouched.
OWN_CONF=0
OWN_SITE=0
on_exit() {
  local exitcode=$?
  if ((exitcode != 0)); then
    if ((OWN_CONF)); then
      rm -f -- "$CONF"
      nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
    fi
    if ((OWN_SITE)); then
      rm -rf -- "$WEBROOT"
    fi
    warn "Установка прервана (код ${exitcode}). Созданные файлы сайта удалены, Xray не изменялся."
  fi
}
trap on_exit EXIT

info 'Копируем готовый сайт FORMA WEB'
install -d -m 0755 "$WEBROOT"
OWN_SITE=1
cp -a "$HERE/site/." "$WEBROOT/"
cat > "$WEBROOT/assets/site-config.js" <<EOF_CONF
// Email виден посетителям, если задан; на сайте нет вымышленных контактов.
window.FORMA_CONFIG = {
  contactEmail: "${CONTACT_EMAIL}",
  portfolioUrl: ""
};
EOF_CONF
chmod -R a+rX "$WEBROOT"

cat > "$CONF" <<EOF_HTTP
# FORMA SELFSTEAL MANAGED: $DOMAIN
# FORMA SELFSTEAL TARGET_PORT: $TARGET_PORT
# Public HTTP is used for Let's Encrypt HTTP-01 renewal.
server {
    listen 80;
    server_name $DOMAIN;
    root $WEBROOT;
    index index.html;
    location ^~ /.well-known/acme-challenge/ { try_files \$uri =404; }
    location / { try_files \$uri \$uri/ =404; }
    error_page 404 /404.html;
}
EOF_HTTP
OWN_CONF=1
nginx -t
systemctl enable --now nginx
systemctl reload nginx

# HTTP-01 requires inbound TCP/80. Change only this rule (with consent) in an active firewall.
# Never enable a disabled firewall, never alter SSH/Xray/panel ports, never open the internal TLS port.
info 'Проверяем firewall для получения и продления сертификата'
choose_http_access() {
  case "$FIREWALL_MODE" in
    allow) return 0;;
    skip) return 1;;
    ask)
      local answer
      ask answer 'Разрешить входящий TCP/80 для проверки сертификата (не затрагивая другие порты)? [Д/н]: '
      case "${answer,,}" in ''|д|да|y|yes) return 0;; *) return 1;; esac
      ;;
  esac
}
if command -v ufw >/dev/null && LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then
  info 'Обнаружен активный UFW'
  if LC_ALL=C ufw status | awk '$1 ~ /^80(\/tcp)?$/ && $2=="ALLOW" && $0 !~ /\(v6\)/ {ok=1} END {exit !ok}'; then
    pass 'В UFW уже есть разрешающее правило TCP/80.'
  elif choose_http_access; then
    ufw allow 80/tcp comment 'FORMA WEB ACME HTTP-01'
    pass 'UFW: открыт только TCP/80; настройки SSH, VPN и панели не изменены.'
  else
    if [[ "$FIREWALL_MODE" == 'skip' ]]; then
      warn 'Не меняем UFW по запросу; Certbot может не пройти проверку, если порт 80 закрыт.'
    else
      die 'UFW активен и доступность TCP/80 не подтверждена. Разреши порт в UFW или запусти с --firewall allow.'
    fi
  fi
elif command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
  info 'Обнаружен активный firewalld'
  if firewall-cmd --quiet --query-service=http; then
    pass 'В firewalld HTTP уже разрешён.'
  elif choose_http_access; then
    firewall-cmd --add-service=http
    firewall-cmd --permanent --add-service=http
    pass 'firewalld: открыт только HTTP/TCP 80 (runtime + permanent).'
  else
    if [[ "$FIREWALL_MODE" == 'skip' ]]; then
      warn 'Не меняем firewalld по запросу; Certbot может не пройти проверку, если порт 80 закрыт.'
    else
      die 'firewalld активен и HTTP/80 не разрешён. Разреши HTTP или запусти с --firewall allow.'
    fi
  fi
else
  warn 'UFW/firewalld не обнаружены или не активны. Другие firewall и правила провайдера скрипт не изменяет.'
fi
warn 'Если порт 80 заблокирован в панели хостинга или внешним firewall, открой его там вручную.'

info 'Проверяем HTTP-подключение к домену'
mkdir -p "$WEBROOT/.well-known/acme-challenge"
TOKEN="forma-selfsteal-$(date +%s)-$$"
printf '%s' "$TOKEN" > "$WEBROOT/.well-known/acme-challenge/$TOKEN"
HTTP_RESULT="$(curl --noproxy '*' -4fsS --max-time 12 "http://$DOMAIN/.well-known/acme-challenge/$TOKEN" || true)"
rm -f -- "$WEBROOT/.well-known/acme-challenge/$TOKEN"
[[ "$HTTP_RESULT" == "$TOKEN" ]] || die 'HTTP-проверка не прошла. Проверь порт 80, хостинговый firewall, DNS и проксирование CDN.'
pass 'HTTP-проверка с самого VPS пройдена. Внешний доступ подтвердит проверка сертификата.'

info "Получаем сертификат Let's Encrypt для $DOMAIN"
certbot certonly --non-interactive --agree-tos --email "$EMAIL" \
  --webroot -w "$WEBROOT" --cert-name "$DOMAIN" -d "$DOMAIN" --keep-until-expiring
[[ -s "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]] || die 'Сертификат не появился.'

info 'Настраиваем локальный HTTPS-сервер для REALITY'
NGX_VER="$(nginx -v 2>&1 | sed -n 's#.*nginx/\([0-9][0-9.]*\).*#\1#p')"
if [[ -n "$NGX_VER" ]] && dpkg --compare-versions "$NGX_VER" ge 1.25.1; then
  info "Nginx $NGX_VER: HTTP/2 через http2 on; (Ubuntu 26.04 / Nginx 1.28.x)."
  HTTP2_LISTEN="listen 127.0.0.1:${TARGET_PORT} ssl;"
  HTTP2_ON='http2 on;'
else
  # Ubuntu 24.04 from apt ships Nginx 1.24.x. The 'http2 on;' directive
  # was introduced in Nginx 1.25.1, so older versions need listen ... http2.
  info "Nginx ${NGX_VER:-неизвестная версия}: синтаксис HTTP/2 для версий до 1.25.1 (listen ... ssl http2)."
  HTTP2_LISTEN="listen 127.0.0.1:${TARGET_PORT} ssl http2;"
  HTTP2_ON=''
fi
cat >> "$CONF" <<EOF_HTTPS

# Private listener. The public port 443 remains owned by Xray/REALITY.
server {
    $HTTP2_LISTEN
    $HTTP2_ON
    server_name $DOMAIN;
    root $WEBROOT;
    index index.html;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    location / { try_files \$uri \$uri/ =404; }
    error_page 404 /404.html;
}
EOF_HTTPS
nginx -t
systemctl reload nginx

info 'Проверяем TLS 1.3, HTTP/2 и правильный сертификат'
# curl --resolve connects to loopback, while verifying the real domain in SNI and certificate.
RESPONSE="$(curl --noproxy '*' -fsS --tlsv1.3 --http2 --max-time 20 \
  --resolve "${DOMAIN}:${TARGET_PORT}:127.0.0.1" -o /dev/null \
  -w '%{http_code} %{http_version}' "https://${DOMAIN}:${TARGET_PORT}/")"
[[ "$RESPONSE" == '200 2' ]] || die "Проверка HTTPS не прошла: ${RESPONSE:-нет ответа}."
pass 'Локальный HTTPS работает: 200 OK, HTTP/2.'

info 'Настраиваем автоматическое продление SSL-сертификата'
# Certbot renew reuses the existing webroot authenticator and validation path.
# The deploy hook is invoked only after a certificate has been renewed successfully.
# Do not overwrite hooks created by other applications.
install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
if [[ -e "$HOOK" ]] && ! grep -q 'FORMA SELFSTEAL MANAGED' "$HOOK"; then
  FALLBACK_HOOK='/etc/letsencrypt/renewal-hooks/deploy/81-forma-selfsteal-nginx-reload.sh'
  if [[ -e "$FALLBACK_HOOK" ]] && ! grep -q 'FORMA SELFSTEAL MANAGED' "$FALLBACK_HOOK"; then
    die 'Имена обработчиков Certbot заняты чужими скриптами. Настрой перезагрузку Nginx вручную.'
  fi
  HOOK="$FALLBACK_HOOK"
fi
cat > "$HOOK" <<'EOF_HOOK'
#!/bin/sh
# FORMA SELFSTEAL MANAGED
# Certbot calls deploy hooks only after successful issue/renewal.
# Reload, do not restart: existing HTTPS connections remain active.
set -eu
/usr/sbin/nginx -t && /usr/bin/systemctl reload nginx
EOF_HOOK
chmod 0755 "$HOOK"
sh -n "$HOOK" || die 'Ошибка синтаксиса обработчика Certbot.'
pass "Обработчик успешного продления: $HOOK"

# Most Debian/Ubuntu packages already schedule Certbot renew. Reuse the native
# timer whenever available; add a separate fallback timer only when necessary.
CERTBOT_TIMER='certbot.timer'
if systemctl list-unit-files --type=timer --no-legend 2>/dev/null | grep -Eq '^[[:space:]]*certbot\.timer[[:space:]]'; then
  if systemctl enable --now certbot.timer && systemctl is-active --quiet certbot.timer; then
    pass 'Штатный Certbot systemd timer включён и активен.'
  else
    warn 'Не удалось включить штатный certbot.timer. Создаём резервное расписание.'
    CERTBOT_TIMER='forma-selfsteal-certbot-renew.timer'
  fi
else
  CERTBOT_TIMER='forma-selfsteal-certbot-renew.timer'
fi
if [[ "$CERTBOT_TIMER" == 'forma-selfsteal-certbot-renew.timer' ]]; then
  # Never replace unrelated pre-existing systemd units.
  RENEW_SERVICE='/etc/systemd/system/forma-selfsteal-certbot-renew.service'
  RENEW_TIMER='/etc/systemd/system/forma-selfsteal-certbot-renew.timer'
  for f in "$RENEW_SERVICE" "$RENEW_TIMER"; do
    if [[ -e "$f" ]] && ! grep -q 'FORMA SELFSTEAL MANAGED' "$f"; then
      die "Файл $f уже существует и не принадлежит установщику. Не перезаписываем."
    fi
  done
  cat > "$RENEW_SERVICE" <<'EOF_RENEW_SERVICE'
# FORMA SELFSTEAL MANAGED
[Unit]
Description=Certbot renew SSL certificates for FORMA WEB (fallback)
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --non-interactive --quiet
EOF_RENEW_SERVICE
  cat > "$RENEW_TIMER" <<'EOF_RENEW_TIMER'
# FORMA SELFSTEAL MANAGED
[Unit]
Description=Daily fallback Certbot SSL auto-renewal check for FORMA WEB
[Timer]
OnCalendar=*-*-* 04:15:00
RandomizedDelaySec=1h
Persistent=true
Unit=forma-selfsteal-certbot-renew.service
[Install]
WantedBy=timers.target
EOF_RENEW_TIMER
  systemctl daemon-reload
  systemctl enable --now "$CERTBOT_TIMER" || die "Не удалось включить таймер $CERTBOT_TIMER."
  systemctl is-active --quiet "$CERTBOT_TIMER" || die "Таймер $CERTBOT_TIMER не запущен."
  pass "Создан резервный таймер ежедневной проверки: $CERTBOT_TIMER"
fi

# The staging renewal verifies the webroot and public TCP/80 without
# renewing the production certificate or changing the Xray configuration.
info "Тестируем продление сертификата через тестовый сервер Let's Encrypt"
if certbot renew --cert-name "$DOMAIN" --dry-run --non-interactive --no-random-sleep-on-renew; then
  pass 'Пробное продление SSL-сертификата прошло успешно.'
else
  warn 'Пробное продление не прошло. SSL сейчас установлен, но автоматическое продление нужно проверить.'
  warn "Повтори после исправления DNS/портов: sudo certbot renew --cert-name '$DOMAIN' --dry-run"
fi
if systemctl is-active --quiet "$CERTBOT_TIMER"; then
  pass "Автоматическая проверка сертификатов активна: $CERTBOT_TIMER"
else
  warn "Таймер $CERTBOT_TIMER не активен — проверь расписание Certbot вручную."
fi
# TCP/443 is served by Xray, not Nginx. Check both listeners and firewall.
# Do not touch SSH or existing Xray inbound. A 443 rule is created only with consent.
info 'Финальная проверка: Xray REALITY и публичный TCP/443'
if ss -H -ltn '( sport = :443 )' | grep -q .; then
  pass 'На TCP/443 уже есть слушающая служба (проверь в 3x-ui, что это нужный Xray inbound).'
else
  warn 'Порт TCP/443 пока никто не слушает. Создай или настрой VLESS + REALITY inbound на порту 443 в 3x-ui.'
  warn 'Обычный HTTPS-сайт может не открываться, пока Xray не запущен на 443.'
fi

# A missing explicit allow is not proof of a block (UFW can have broader rules).
ufw_tcp_explicit_allow() {
  local port="$1"
  LC_ALL=C ufw status 2>/dev/null |
    awk -v p="$port" '($1==p"/tcp" || $1==p) && $2=="ALLOW" {yes=1} END{exit !yes}'
}
choose_https_access() {
  case "$FIREWALL_443_MODE" in
    allow) return 0;;
    skip) return 1;;
    ask)
      local reply443
      ask reply443 'Добавить в активный firewall разрешение TCP/443 для HTTPS/REALITY? [д/Н]: '
      case "${reply443,,}" in д|да|y|yes) return 0;; *) return 1;; esac
      ;;
  esac
}
if command -v ufw >/dev/null && LC_ALL=C ufw status 2>/dev/null | grep -q '^Status: active'; then
  info 'UFW активен: проверяем TCP/443 и доступ SSH'
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    SSH_PORT="${SSH_CONNECTION##* }"
    if [[ "$SSH_PORT" =~ ^[0-9]+$ ]]; then
      if ! ufw_tcp_explicit_allow "$SSH_PORT"; then
        warn "Для текущего порта SSH ($SSH_PORT/tcp) нет отдельного разрешения в UFW."
        warn "НЕ закрывай SSH-сессию, пока не убедишься в доступе с нового подключения."
        warn "Если доступ должен быть открыт всем: ufw allow ${SSH_PORT}/tcp (лучше ограничить по своему IP)."
      fi
    fi
  else
    warn 'Порт SSH определить не удалось. Проверь SSH-доступ в UFW до выхода из терминала.'
  fi
  if ufw_tcp_explicit_allow 443; then
    pass 'В UFW найдено явное разрешение TCP/443.'
  else
    warn 'В UFW нет отдельного ALLOW для TCP/443 — сайт может не открываться извне.'
    if choose_https_access; then
      ufw allow 443/tcp comment 'FORMA WEB Xray REALITY HTTPS'
      pass 'В UFW добавлено разрешение TCP/443 (остальные правила не изменены).'
    else
      warn 'Правило TCP/443 не добавлено. Если HTTPS недоступен: ufw allow 443/tcp'
    fi
  fi
elif command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
  info 'Проверяем TCP/443 в активном firewalld'
  if firewall-cmd --quiet --query-service=https || firewall-cmd --quiet --query-port=443/tcp; then
    pass 'В firewalld явно разрешён HTTPS/TCP 443.'
  elif choose_https_access; then
    firewall-cmd --add-service=https
    firewall-cmd --permanent --add-service=https
    pass 'В firewalld добавлено разрешение HTTPS/TCP 443.'
  else
    warn 'TCP/443 не добавлен в firewalld; если сайт недоступен, разреши HTTPS/TCP 443.'
  fi
  warn 'Перед закрытием SSH обязательно проверь, что входящий SSH разрешён в firewalld.'
else
  warn 'Активный UFW/firewalld не найден. Проверь разрешение TCP/443 в панели VPS-хостинга и иных firewall.'
fi
warn 'Даже при разрешённом UFW TCP/443 может быть закрыт firewall провайдера VPS.'
warn "После настройки REALITY открой в браузере https://$DOMAIN"
warn "Если сайт не открылся: ss -ltnp | grep ':443' ; ufw status ; curl -I http://$DOMAIN"
warn "Диагностика: curl -I --resolve ${DOMAIN}:443:127.0.0.1 https://${DOMAIN}/"
warn 'Для VPN-клиента адрес сервера — публичный домен/IP, а НЕ 127.0.0.1.'

# Keep the read-only diagnostic available after bootstrap removes its temp directory.
# Never overwrite an unrelated script.
if [[ -f "$HERE/check.sh" ]]; then
  CHECK_BIN='/usr/local/bin/forma-web-check'
  if [[ ! -e "$CHECK_BIN" ]] || grep -q 'FORMA WEB CHECK MANAGED' "$CHECK_BIN" 2>/dev/null; then
    if install -m 0755 "$HERE/check.sh" "$CHECK_BIN"; then
      pass "Диагностика установлена: sudo forma-web-check $DOMAIN"
    else
      warn "Не удалось установить диагностику в $CHECK_BIN. Скачай check.sh из GitHub."
    fi
  else
    warn "Файл $CHECK_BIN принадлежит другой программе; не перезаписываем."
  fi
fi

cat <<EOF_DONE

===============================================================
  ГОТОВО: FORMA WEB УСТАНОВЛЕН
===============================================================
  Сайт:      $DOMAIN
  IPv4:      $PUBLIC_IP
  Каталог:   $WEBROOT
  HTTPS:     127.0.0.1:$TARGET_PORT (доступен только из VPS)
  Версия ОС: ${PRETTY_NAME:-${ID:-Linux}}
  Nginx:     ${NGX_VER:-неизвестно}
  SSL:       автоматическое продление через $CERTBOT_TIMER
  Проверка:  sudo certbot renew --cert-name $DOMAIN --dry-run
  Диагностика: sudo forma-web-check $DOMAIN (если установлен)

  Важно: установка сайта НЕ включает публичный HTTPS автоматически!
  ШАГ 1. 3x-ui -> Inbounds -> VLESS + REALITY:
    Port:               443/TCP (RAW)
    Target / Dest:      127.0.0.1:$TARGET_PORT
    SNI / Server Names: $DOMAIN
    Xver:               0
    Flow для Vision:    xtls-rprx-vision

  ШАГ 2. Разреши входящие 443/TCP в firewall VPS и у хостинг-провайдера.
         Если UFW активен и нет разрешения: ufw allow 443/tcp
  ШАГ 3. Сохрани inbound; убедись, что Xray слушает :443.
         Проверка: ss -ltnp | grep ':443'
  ШАГ 4. Открой https://$DOMAIN с другого устройства/сети.

  НЕ меняй существующие REALITY-ключи, UUID и Short ID.
  Обнови SNI в VPN-клиентах после сохранения inbound.
  Если сайт работает на HTTP, но не на HTTPS, проверь шаги 1-3.

  ВАЖНО: сохраняй резервную копию конфигурации 3x-ui.
  Xray, 3x-ui и SSH не изменялись. Правила TCP/80 и TCP/443 могли добавиться только с согласия.
  HTTPS-сайт не скрывает объём VPN-трафика.
===============================================================
EOF_DONE
