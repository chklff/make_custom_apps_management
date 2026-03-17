#!/usr/bin/env bash
# scripts/list_destination_apps.sh
# Reads .env, paginates GET /api/v2/sdk/apps, counts and lists every app.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing .env at: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${destination_API_KEY:?destination_API_KEY is missing in .env}"
: "${destination_Base_URL:?destination_Base_URL is missing in .env}"

DEST_BASE_URL="${destination_Base_URL%/}"
if [[ "$DEST_BASE_URL" == */api ]]; then
  APPS_URL="$DEST_BASE_URL/v2/sdk/apps"
else
  APPS_URL="$DEST_BASE_URL/api/v2/sdk/apps"
fi

PAGE_SIZE=100   # Make API max is typically 100
offset=0
total=0
page=1

printf '%-40s %-30s %s\n' "NAME (appId)" "LABEL" "VERSION"
printf '%.0s-' {1..80}; echo

while true; do
  tmp="$(mktemp)"
  http_code="$(
    curl -sS -L \
      -o "$tmp" \
      -w '%{http_code}' \
      --url "${APPS_URL}?pg%5Blimit%5D=${PAGE_SIZE}&pg%5Boffset%5D=${offset}" \
      --header "Authorization: Token ${destination_API_KEY}" \
      --header "Accept: application/json" || true
  )"

  if [[ "$http_code" != 2* ]]; then
    echo "API error (HTTP $http_code) at offset $offset:" >&2
    cat "$tmp" >&2
    rm -f "$tmp"
    exit 1
  fi

  # Parse the page: print rows and count them
  count="$(jq -r '.apps | length' <"$tmp")"

  if [[ "$count" -eq 0 ]]; then
    rm -f "$tmp"
    break
  fi

  # Print each app on this page
  while IFS=$'\t' read -r name label version; do
    printf '%-40s %-30s %s\n' "$name" "$label" "$version"
  done < <(jq -r '.apps[] | [.name, .label, (.version|tostring)] | @tsv' <"$tmp")

  rm -f "$tmp"

  total=$((total + count))
  echo "  ... page $page: fetched $count apps (running total: $total)"
  page=$((page + 1))

  # Stop if we got fewer than a full page — last page reached
  if [[ "$count" -lt "$PAGE_SIZE" ]]; then
    break
  fi

  offset=$((offset + PAGE_SIZE))
done

printf '%.0s-' {1..80}; echo
echo "Total apps found on ${DEST_BASE_URL}: $total"
