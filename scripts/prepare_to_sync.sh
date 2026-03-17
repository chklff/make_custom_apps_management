#!/usr/bin/env bash
# scripts/prepare_to_sync.sh  (Bash 3.2+ compatible)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$ROOT_DIR" || ! -d "$ROOT_DIR" ]]; then
  echo "Could not resolve ROOT_DIR (got: '$ROOT_DIR')" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage: bash scripts/prepare_to_sync.sh [--no-api]

Reads .env for:
  - destination_API_KEY
  - destination_Base_URL

Finds every makecomapp.json and appends/updates a destination entry in its "origins" array.

For each app:
  1. Skips if makecomapp.json already has an origin matching destination_Base_URL.
  2. Checks if any existing origin appId in the file already exists on destination → reuse.
  3. Checks if destination has an app whose label matches the folder name → reuse.
  4. Otherwise creates a new app (name capped at 30 chars).

Options:
  --no-api   Skip all API calls; write placeholder origin (appId="" and appVersion=1).
EOF
}

NO_API=0
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage; exit 0
fi
if [[ "${1:-}" == "--no-api" ]]; then
  NO_API=1; shift
fi
if [[ "${#}" -ne 0 ]]; then
  echo "Unexpected arguments: $*" >&2
  usage >&2; exit 2
fi

ENV_FILE="$ROOT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing .env at: $ENV_FILE" >&2; exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${destination_API_KEY:?destination_API_KEY is missing in .env}"
: "${destination_Base_URL:?destination_Base_URL is missing in .env}"

DEST_BASE_URL="${destination_Base_URL%/}"
if [[ "$DEST_BASE_URL" == */api ]]; then
  DEST_APPS_URL="$DEST_BASE_URL/v2/sdk/apps"
else
  DEST_APPS_URL="$DEST_BASE_URL/api/v2/sdk/apps"
fi

SECRETS_DIR="$ROOT_DIR/.secrets"
DEST_KEY_FILE="$SECRETS_DIR/destination_apikey"
mkdir -p "$SECRETS_DIR"
printf '%s\n' "$destination_API_KEY" > "$DEST_KEY_FILE"

# Cache format: <appId> TAB <label> TAB <version>
APPS_CACHE="$(mktemp)"
trap 'rm -f "$APPS_CACHE"' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

start_case() {
  local s="$1"
  printf '%s' "$s" \
    | tr '_-' '  ' \
    | awk '{ for (i=1;i<=NF;i++) { $i=toupper(substr($i,1,1)) substr($i,2) }; print }'
}

slugify() {
  local s="$1"
  s="${s// /-}"; s="${s//_/-}"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-')"
  s="${s#-}"; s="${s%-}"
  printf '%s' "$s"
}

dest_apikey_relpath() {
  local json_dir="$1"
  if [[ "$json_dir" == "$ROOT_DIR" ]]; then
    printf '%s' ".secrets/destination_apikey"; return 0
  fi
  local sub="${json_dir#$ROOT_DIR/}"
  if [[ "$sub" == "$json_dir" ]]; then
    printf '%s' "$DEST_KEY_FILE"; return 0
  fi
  local depth
  depth="$(printf '%s\n' "$sub" | awk -F'/' '{print NF}')"
  local prefix=""
  while [[ "$depth" -gt 0 ]]; do
    prefix="../$prefix"; depth=$((depth - 1))
  done
  printf '%s' "${prefix}.secrets/destination_apikey"
}

# Lookup by label (col 2) — case-insensitive
lookup_by_label() {
  local label="$1"
  grep -iF "$label" "$APPS_CACHE" | head -1 || true
}

# Lookup by exact appId (col 1)
lookup_by_id() {
  local id="$1"
  grep -F "$(printf '%s\t' "$id")" "$APPS_CACHE" | head -1 || true
}

# ---------------------------------------------------------------------------
# Step 1: Fetch ALL apps from destination (paginated)
# Cache line: appId TAB label TAB version
# ---------------------------------------------------------------------------
fetch_existing_apps() {
  local page_size=100
  local offset=0
  local page=1
  local total=0

  echo "Fetching existing apps from: $DEST_APPS_URL"

  while true; do
    local tmp; tmp="$(mktemp)"
    local http_code
    http_code="$(
      curl -sS -L \
        -o "$tmp" -w '%{http_code}' \
        --url "${DEST_APPS_URL}?pg%5Blimit%5D=${page_size}&pg%5Boffset%5D=${offset}" \
        --header "Authorization: Token ${destination_API_KEY}" \
        --header "Accept: application/json" || true
    )"

    if [[ "$http_code" != 2* ]]; then
      echo "Failed to fetch apps (HTTP $http_code) at offset $offset:" >&2
      cat "$tmp" >&2; rm -f "$tmp"; exit 1
    fi

    local count
    count="$(jq -r '.apps | length' <"$tmp")"

    if [[ "$count" -eq 0 ]]; then
      rm -f "$tmp"; break
    fi

    jq -r '.apps[] | [.name, .label, (.version|tostring)] | @tsv' <"$tmp" >> "$APPS_CACHE"
    rm -f "$tmp"

    total=$((total + count))
    echo "  Page $page: loaded $count apps (running total: $total)"
    page=$((page + 1))

    [[ "$count" -lt "$page_size" ]] && break
    offset=$((offset + page_size))
  done

  echo "Done. $total apps found on destination."
  echo
}

# ---------------------------------------------------------------------------
# Step 2: Create a new app via API
# ---------------------------------------------------------------------------
create_app() {
  local name="$1" label="$2" description="$3"

  local body
  body="$(jq -n \
    --arg name "$name" --arg label "$label" \
    --arg description "$description" --argjson version 1 \
    '{name:$name,label:$label,description:$description,version:$version}')"

  local tmp; tmp="$(mktemp)"
  local http_code
  http_code="$(
    curl -sS -L \
      -o "$tmp" -w '%{http_code}' \
      --request POST \
      --url "$DEST_APPS_URL" \
      --header "Authorization: Token $destination_API_KEY" \
      --header 'Content-Type: application/json' \
      --data "$body" || true
  )"

  if [[ -z "$http_code" || "$http_code" != 2* ]]; then
    echo "Create app failed (HTTP $http_code) at: $DEST_APPS_URL" >&2
    cat "$tmp" >&2; rm -f "$tmp"; return 1
  fi

  local app_id app_version
  app_id="$(jq -r '.app.name // empty' <"$tmp" 2>/dev/null || true)"
  app_version="$(jq -r '.app.version // empty' <"$tmp" 2>/dev/null || true)"
  rm -f "$tmp"

  if [[ -z "$app_id" || -z "$app_version" ]]; then
    echo "Create app succeeded but response missing .app.name/.app.version" >&2
    return 1
  fi

  printf '%s\t%s\n' "$app_id" "$app_version"
}

# ---------------------------------------------------------------------------
# Step 3: Patch makecomapp.json with resolved id + version
# ---------------------------------------------------------------------------
update_makecomapp_json() {
  local json_path="$1" label="$2" app_id="$3" app_version="$4" apikey_rel="$5"
  local tmp; tmp="$(mktemp)"

  jq --indent 4 \
    --arg destBaseUrl "$DEST_BASE_URL" \
    --arg destApikeyFile "$apikey_rel" \
    --arg label "$label" \
    --arg appId "$app_id" \
    --arg baseUrl "$DEST_BASE_URL" \
    --argjson appVersion "$app_version" \
    '
      .origins = (.origins // [])
      | .origins = (
          .origins
          | map(select((.baseUrl != $destBaseUrl) and (.apikeyFile != $destApikeyFile)))
        )
      | .origins += [{
          label: $label,
          appId: $appId,
          baseUrl: $baseUrl,
          appVersion: $appVersion,
          apikeyFile: $destApikeyFile
        }]
    ' "$json_path" >"$tmp"

  mv "$tmp" "$json_path"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

JSON_FILES=()
while IFS= read -r json_file; do
  [[ -z "$json_file" ]] && continue
  JSON_FILES+=("$json_file")
done < <(find "$ROOT_DIR" -name makecomapp.json -print)

if [[ "${#JSON_FILES[@]}" -eq 0 ]]; then
  echo "No makecomapp.json files found under: $ROOT_DIR" >&2; exit 0
fi

if [[ "$NO_API" -eq 0 ]]; then
  fetch_existing_apps
fi

errors=0
for json_path in "${JSON_FILES[@]}"; do
  json_dir="$(dirname "$json_path")"
  folder_name="$(basename "$json_dir")"
  label="$(start_case "$folder_name")"
  apikey_rel="$(dest_apikey_relpath "$json_dir")"

  # ✋ Skip if destination origin already present
  already_configured="$(jq -r \
    --arg url "$DEST_BASE_URL" \
    'any(.origins[]?; .baseUrl == $url) | tostring' \
    "$json_path" 2>/dev/null || echo "false")"

  if [[ "$already_configured" == "true" ]]; then
    echo "SKIP   already configured  →  $json_path"
    continue
  fi

  app_id=""
  app_version="1"

  if [[ "$NO_API" -eq 0 ]]; then
    cache_hit=""

    # ── Strategy 1: any appId already in this file's origins exists on destination? ──
    while IFS= read -r existing_id; do
      [[ -z "$existing_id" ]] && continue
      hit="$(lookup_by_id "$existing_id")"
      if [[ -n "$hit" ]]; then
        cache_hit="$hit"
        break
      fi
    done < <(jq -r '.origins[]?.appId // empty' "$json_path" 2>/dev/null || true)

    # ── Strategy 2: match by label (folder name → start_case) ──
    if [[ -z "$cache_hit" ]]; then
      cache_hit="$(lookup_by_label "$label")"
    fi

    if [[ -n "$cache_hit" ]]; then
      app_id="$(printf '%s' "$cache_hit" | cut -f1)"
      app_version="$(printf '%s' "$cache_hit" | cut -f3)"
      echo "REUSE  [$app_id]  v${app_version}  →  $json_path"
    else
      # ── Nothing found — create new app ──
      app_name="oemapp-$(slugify "$folder_name")"
      # Make API enforces 30 char max on name
      if [[ "${#app_name}" -gt 30 ]]; then
        app_name="${app_name:0:30}"
        app_name="${app_name%-}"
      fi
      if out="$(create_app "$app_name" "$label" "$label")"; then
        app_id="${out%%$'\t'*}"
        app_version="${out#*$'\t'}"
        echo "CREATE [$app_id]  v${app_version}  →  $json_path"
        # Add to cache so subsequent files in the same run can reuse it
        printf '%s\t%s\t%s\n' "$app_id" "$label" "$app_version" >> "$APPS_CACHE"
      else
        errors=1
        continue
      fi
    fi
  fi

  update_makecomapp_json "$json_path" "$label" "$app_id" "$app_version" "$apikey_rel"
  echo "Updated: $json_path"
  echo
done

exit "$errors"
