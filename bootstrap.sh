#!/usr/bin/env bash
# GitHub bootstrap: download a repository archive and execute its local installer.
# Usage: curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/bootstrap.sh | sudo bash -s -- OWNER/REPO
set -Eeuo pipefail

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  echo 'Использование: sudo bash bootstrap.sh OWNER/REPO [аргументы установщика]'
  exit 0
fi
[[ $EUID -eq 0 ]] || { echo 'Ошибка: нужны права root (sudo).' >&2; exit 1; }
REPO="${1:-}"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  echo 'Укажи GitHub-репозиторий в формате OWNER/REPO. Пример команды см. в README.' >&2
  exit 1
}
shift
command -v curl >/dev/null || { echo 'Сначала установи curl: sudo apt update && sudo apt install -y curl' >&2; exit 1; }
command -v tar >/dev/null || { echo 'Не найден tar.' >&2; exit 1; }
TMP="$(mktemp -d /tmp/forma-web.XXXXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
# main is the default branch used in the published setup instructions.
URL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/main"
echo "Скачиваем комплект ${REPO} с GitHub..."
curl -fL --retry 2 --connect-timeout 12 --max-time 120 "$URL" -o "$TMP/source.tar.gz"
mkdir -p "$TMP/source"
tar -xzf "$TMP/source.tar.gz" --strip-components=1 -C "$TMP/source"
[[ -f "$TMP/source/install.sh" && -f "$TMP/source/site/index.html" ]] || {
  echo 'В репозитории не найдены install.sh и site/index.html.' >&2
  exit 1
}
bash "$TMP/source/install.sh" "$@"
