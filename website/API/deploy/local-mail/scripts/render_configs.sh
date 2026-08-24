#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-mail.env}"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${BASE_DIR}/out"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "missing env file: ${ENV_FILE}" >&2
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

mkdir -p "${OUT_DIR}/postfix" "${OUT_DIR}/dovecot" "${OUT_DIR}/opendkim"

render() {
  local in_file="$1"
  local out_file="$2"
  sed \
    -e "s|__MAIL_DOMAIN__|${MAIL_DOMAIN}|g" \
    -e "s|__MAIL_HOST__|${MAIL_HOST}|g" \
    -e "s|__SMTP_LOGIN__|${SMTP_LOGIN}|g" \
    -e "s|__TLS_CERT__|${TLS_CERT}|g" \
    -e "s|__TLS_KEY__|${TLS_KEY}|g" \
    -e "s|__DKIM_SELECTOR__|${DKIM_SELECTOR}|g" \
    -e "s|__VMAIL_UID__|${VMAIL_UID}|g" \
    -e "s|__VMAIL_GID__|${VMAIL_GID}|g" \
    "${in_file}" > "${out_file}"
}

render "${BASE_DIR}/postfix/main.cf.template" "${OUT_DIR}/postfix/main.cf"
render "${BASE_DIR}/postfix/master.cf.template" "${OUT_DIR}/postfix/master.cf"
render "${BASE_DIR}/dovecot/dovecot.conf.template" "${OUT_DIR}/dovecot/dovecot.conf"
render "${BASE_DIR}/opendkim/opendkim.conf.template" "${OUT_DIR}/opendkim/opendkim.conf"
render "${BASE_DIR}/opendkim/KeyTable.template" "${OUT_DIR}/opendkim/KeyTable"
render "${BASE_DIR}/opendkim/SigningTable.template" "${OUT_DIR}/opendkim/SigningTable"
cp "${BASE_DIR}/opendkim/TrustedHosts" "${OUT_DIR}/opendkim/TrustedHosts"
cp "${BASE_DIR}/dovecot/users.example" "${OUT_DIR}/dovecot/users"

echo "Rendered mail configs to ${OUT_DIR}"
