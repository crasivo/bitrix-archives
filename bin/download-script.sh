#!/usr/bin/env bash

set -o pipefail
set -o errtrace
set -o nounset
set -o errexit

# ----------------------------------------------------------------
# Environments
# ----------------------------------------------------------------

# Context (constant)
S_FILEPATH=$(realpath "$0")
S_CONTEXT_DIR=$(dirname "$S_FILEPATH")
S_ROOT_DIR=$(realpath "$S_CONTEXT_DIR/../")

# GitHub
GITHUB_ENV=${GITHUB_ENV:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-}

# Bitrix: General
BITRIX_SCRIPT_NAME=${BITRIX_SCRIPT_NAME:-}
BITRIX_SCRIPT_PATH=${BITRIX_SCRIPT_PATH:-}
BITRIX_MANIFEST_PATH=${BITRIX_MANIFEST_PATH:-}
BITRIX_OUTPUT_DIR=${BITRIX_OUTPUT_DIR:-}
BITRIX_RELEASE_TAG=${BITRIX_RELEASE_TAG:-}

# ----------------------------------------------------------------
# Functions
# ----------------------------------------------------------------

# @description Check release exists
# @param $1 string Tag
function _git_check_release_tag_exists() {
  echo "🔎 Check release '$1'"
  if [[ -n "$GITHUB_TOKEN" ]]; then
    # shellcheck disable=SC2155
    local http_status=$(curl -s -o /dev/null -I -w "%{http_code}" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/crasivo/bitrix-archives/releases/tags/$1")
  else
    # shellcheck disable=SC2155
    local http_status=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/crasivo/bitrix-archives/releases/tags/$1")
  fi
  if [[ "$http_status" == '404' ]]; then
    echo "➡️ Release '$1' not found. Continue..."
    return
  fi

  # Notify Github
  echo "➡️ Release '$1' already exists. Skipping..."
  if [[ -n "$GITHUB_ENV" ]]; then
    echo "SKIP_PUBLISH=true" >> "$GITHUB_ENV"
  fi

  # Stop execute
  exit 0
}

# @description Export BITRIX_* variables for Github Action
function _git_export_bitrix_variables() {
  if [[ -z "$GITHUB_ENV" ]]; then
    echo "🐞 Skipping export variables (GitHub Action)"
    return
  fi
  echo "⬆️ Export variables (GitHub Action)"
  for var in $(compgen -v | grep '^BITRIX_'); do
    echo "$var=${!var}" >> "$GITHUB_ENV"
  done
}

# @description Create initial manifest.json
# @param $1 string Output filepath
function _bx_create_initial_manifest() {
  echo "🧾 Create manifest.json"
  jq -n \
    --arg release_tag "$BITRIX_RELEASE_TAG" \
    '{
      release_tag: $release_tag,
      repository: "https://github.com/crasivo/bitrix-archives",
      assets: []
    }' > "$1"
}

# @description Download archive
# @param $1 string Output filepath
function _bx_download_script() {
  # shellcheck disable=SC2155
  local basename=$(basename "$1")
  if [[ -f "$1" ]]; then
    # shellcheck disable=SC2086
    echo "🐞 Local file '$basename' already exists. Skipping..."
    return
  fi

  local download_url="https://www.1c-bitrix.ru/download/scripts/${BITRIX_SCRIPT_NAME}"
  echo "⬇️ Downloading PHP script ($download_url)..."
  curl -SL "$download_url" -o "$1"
}

# @description Extract file meta (tar)
# @param $1 string Input script
# @param $2 string Output manifest.json
function _bx_extract_script_meta() {
  # shellcheck disable=SC2155
  local basename=$(basename "$1")
  # shellcheck disable=SC2155
  local dirname=$(dirname "$1")
  echo "ℹ️ Extracting meta for $basename"
  local size=$(stat -c%s "$1")
  local md5=$(md5sum "$1" | awk '{ print $1 }')
  local sha1=$(sha1sum "$1" | awk '{ print $1 }')
  local sha256=$(sha256sum "$1" | awk '{ print $1 }')

  # Dump file checksums
  if [[ -n "$md5" ]]; then
      echo "$md5" > "$1.md5"
      echo "$md5 $basename" >> "$dirname/checksums_md5.txt"
  fi
  if [[ -n "$sha1" ]]; then
      echo "$sha1" > "$1.sha1"
      echo "$sha1 $basename" >> "$dirname/checksums_sha1.txt"
  fi
  if [[ -n "$sha256" ]]; then
      echo "$sha256" > "$1.sha256"
      echo "$sha256 $basename" >> "$dirname/checksums_sha256.txt"
  fi

  # Dump manifest assets
  # shellcheck disable=SC2155
  local tmp_manifest=$(mktemp)
  jq --arg name "$basename" \
     --arg md5 "$md5" \
     --arg sha1 "$sha1" \
     --arg sha256 "$sha256" \
     --arg size "$size" \
     '.assets += [{
         "name": $name,
         "size": ($size | tonumber),
         "md5": $md5,
         "sha1": $sha1,
         "sha256": $sha256
     }]' "$2" > "$tmp_manifest" && mv -f "$tmp_manifest" "$2"
}

# ----------------------------------------------------------------
# Commands
# ----------------------------------------------------------------

# @description Run process
function _cmd_run() {
  if [[ -z "$BITRIX_OUTPUT_DIR" ]]; then
    BITRIX_OUTPUT_DIR="$S_ROOT_DIR/dist/$BITRIX_SCRIPT_NAME"
  fi

  # Step 0. Prepare
  mkdir -p "$BITRIX_OUTPUT_DIR"
  BITRIX_MANIFEST_PATH="$BITRIX_OUTPUT_DIR/manifest.json"

  # Step 1. Download script
  BITRIX_SCRIPT_PATH="$BITRIX_OUTPUT_DIR/$BITRIX_SCRIPT_NAME"
  _bx_download_script "$BITRIX_SCRIPT_PATH"

  # Step 2. Check release duplicates
  BITRIX_RELEASE_TAG="${BITRIX_SCRIPT_NAME}-$(date +'%Y%m%d')"
  _git_check_release_tag_exists "$BITRIX_RELEASE_TAG"

  # Step 2. Create manifest.json
  _bx_create_initial_manifest "$BITRIX_MANIFEST_PATH"

  # Step 3. Extract script meta
  _bx_extract_script_meta "$BITRIX_SCRIPT_PATH" "$BITRIX_MANIFEST_PATH"

  # Export variables (github)
  _git_export_bitrix_variables
}

# ----------------------------------------------------------------
# Runtime
# ----------------------------------------------------------------

# Check arguments
if [[ "$#" -lt 1 ]]; then
  echo "❌ Error: Illegal number of parameters"
  exit 1
fi

# Define script (action)
if [[ $1 = *.php ]]; then
  BITRIX_SCRIPT_NAME="$1"
  shift
else
  echo "❌ Error: Unknown action ($1)"
  exit 1
fi

# Parse options
for i in "$@"; do
  case "$i" in
    --env=*)
      # shellcheck disable=SC2046
      export $(grep -E '^#' "${i#*=}" | xargs)
      shift
      ;;
    --output=*)
      O_OUTPUT_DIR="${i#*=}"
      shift
      ;;
  esac
done

# Run process
_cmd_run
