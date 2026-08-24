#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-example.com}"
SELECTOR="${2:-default}"
OUT_DIR="${3:-./dkim-out}"

mkdir -p "${OUT_DIR}/${DOMAIN}"
opendkim-genkey -D "${OUT_DIR}/${DOMAIN}" -d "${DOMAIN}" -s "${SELECTOR}"

echo "DKIM private key: ${OUT_DIR}/${DOMAIN}/${SELECTOR}.private"
echo "DKIM DNS record:"
tr -d '\n' < "${OUT_DIR}/${DOMAIN}/${SELECTOR}.txt"
echo
