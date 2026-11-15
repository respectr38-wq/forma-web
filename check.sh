#!/usr/bin/env bash
# Read-only diagnostic for FORMA WEB Self-Steal website. Never changes a service.
set -Eeuo pipefail

DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then
  [[ -r /dev/tty ]] || { echo 'Укажи домен: bash check.sh site.example.com' >&2; exit 1; }
  printf 'Домен сайта: ' > /dev/tty
  IFS= read -r DOMAIN < /dev/tty
fi
DOMAIN="${DOMAIN,,}"
[[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || {
  echo 'Некорректный домен' >&2; exit 1;
}
CONF="/etc/nginx/conf.d/forma-selfsteal-${DOMAIN}.conf"
TARGET_PORT=8443
if [[ -r "$CONF" ]]; then
  detected="$(sed -n 's/^# FORMA SELFSTEAL TARGET_PORT: //p' "$CONF" | head -n 1)"
  [[ "$detected" =~ ^[0-9]{4,5}$ ]] && TARGET_PORT="$detected"
fi
printf '\nПроверка FORMA WEB: %s (внутренний HTTPS-порт %s)\n' "$DOMAIN" "$TARGET_PORT"
if [[ -f "$CONF" ]]; then
  echo '[OK] Конфигурация Nginx существует.'
else
  echo '[!] Конфигурация Nginx не найдена.'
fi
if command -v nginx >/dev/null && nginx -t >/dev/null 2>&1; then
  echo '[OK] Синтаксис конфигурации Nginx.'
else
  echo '[!] Ошибка Nginx или Nginx не установлен.'
fi
if systemctl is-active --quiet nginx; then
  echo '[OK] Nginx запущен.'
else
  echo '[!] Nginx не запущен.'
fi
if [[ -r "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
  echo '[OK] Сертификат существует.'
  openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -enddate || true
else
  echo '[!] Сертификат не найден или нет доступа. Запусти проверку с sudo.'
fi
if command -v curl >/dev/null; then
  response="$(curl -fsS --http2 --tlsv1.3 --max-time 12 \
    --resolve "${DOMAIN}:${TARGET_PORT}:127.0.0.1" \
    -o /dev/null -w '%{http_code} %{http_version}' "https://${DOMAIN}:${TARGET_PORT}/" || true)"
  if [[ "$response" == '200 2' ]]; then
    echo '[OK] Внутренний HTTPS: HTTP 200, HTTP/2.'
  else
    echo "[!] Внутренняя HTTPS-проверка не прошла: ${response:-нет ответа}."
  fi
  echo 'Внешний HTTPS через порт 443 проверяй только после настройки REALITY.'
fi
if command -v systemctl >/dev/null; then
  if systemctl is-active --quiet certbot.timer; then
    echo '[OK] Автоматическое продление: certbot.timer активен.'
  elif systemctl is-active --quiet forma-selfsteal-certbot-renew.timer; then
    echo '[OK] Автоматическое продление: резервный таймер FORMA активен.'
  else
    echo '[!] Не обнаружен активный systemd timer Certbot. Проверь планировщик/cron.'
  fi
fi
if [[ -x /etc/letsencrypt/renewal-hooks/deploy/80-forma-selfsteal-nginx-reload.sh || -x /etc/letsencrypt/renewal-hooks/deploy/81-forma-selfsteal-nginx-reload.sh ]]; then
  echo '[OK] Есть обработчик перезагрузки Nginx после обновления SSL.'
else
  echo '[!] Не найден обработчик обновления сертификата Nginx.'
fi
if command -v certbot >/dev/null; then
  printf '\nПроверка механизма продления (без выпуска реального сертификата):\n'
  printf '  sudo certbot renew --cert-name %s --dry-run\n' "$DOMAIN"
fi

printf '\nТребуемые поля REALITY:\n  SNI:    %s\n  Target: 127.0.0.1:%s\n  Xver:   0\n' "$DOMAIN" "$TARGET_PORT"
