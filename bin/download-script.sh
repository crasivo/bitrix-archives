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

# Options
O_OUTPUT_DIR="$S_ROOT_DIR/tmp"

# GitHub
GITHUB_REPO='crasivo/bitrix-archives'
GITHUB_ENV=${GITHUB_ENV:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
GITHUB_RELEASE_DATE=${GITHUB_RELEASE_DATE:-}
GITHUB_RELEASE_TAG=${GITHUB_RELEASE_TAG:-}

# Bitrix: General
BITRIX_SCRIPT_NAME=${BITRIX_SCRIPT_NAME:-}
BITRIX_MANIFEST_PATH=${BITRIX_MANIFEST_PATH:-}

# Bitrix: Meta
BITRIX_META_SCRIPT_PATH=${BITRIX_META_SCRIPT_PATH:-}
BITRIX_META_SCRIPT_SIZE=${BITRIX_META_SCRIPT_SIZE:-}
BITRIX_META_SCRIPT_MD5=${BITRIX_META_SCRIPT_MD5:-}
BITRIX_META_SCRIPT_SHA1=${BITRIX_META_SCRIPT_SHA1:-}
BITRIX_META_SCRIPT_SHA256=${BITRIX_META_SCRIPT_SHA256:-}

# ----------------------------------------------------------------
# Functions
# ----------------------------------------------------------------

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

# @description Download PHP script
# @param $1 string Output dir
# @param $2 string Filename
function _bx_download_script() {
  local download_url="https://www.1c-bitrix.ru/download/scripts/$2"
  echo "⬇️ Downloading PHP script ($download_url)..."
  if [[ -f "$1/$2" ]]; then
    echo "File $1 already exists. Skipping."
    return
  fi

  curl -sSL "$download_url" -o "$1/$2"
}

# @description Dump file meta (bitrixsetup.php)
# @param $1 string Filepath
function _bx_dump_script_meta() {
  echo "ℹ️ Extracting file meta"
  BITRIX_META_SCRIPT_SIZE=$(stat -c%s "$1")
  BITRIX_META_SCRIPT_SIZE_MB=$(echo "scale=2; $BITRIX_META_SCRIPT_SIZE / 1024" | bc)
  BITRIX_META_SCRIPT_MD5=$(md5sum "$1" | awk '{ print $1 }')
  BITRIX_META_SCRIPT_SHA1=$(sha1sum "$1" | awk '{ print $1 }')
  BITRIX_META_SCRIPT_SHA256=$(sha256sum "$1" | awk '{ print $1 }')
  # Dump
  echo "$BITRIX_META_SCRIPT_MD5" > "$1.md5"
  echo "$BITRIX_META_SCRIPT_SHA1" > "$1.sha1"
  echo "$BITRIX_META_SCRIPT_SHA256" > "$1.sha256"
}

# @description Export variables (github action)
function _bx_export_github_variables() {
  echo "⬆️ Export variables (GitHub Action)"
  if [[ -z "$GITHUB_ENV" ]]; then
    echo "Skipping..."
    return
  fi
  for var in $(compgen -v | grep '^BITRIX_'); do
    echo "$var=${!var}" >> "$GITHUB_ENV"
  done
}

# ----------------------------------------------------------------
# Commands
# ----------------------------------------------------------------

# @description Run process
function _cmd_run() {
  local output_dir="$O_OUTPUT_DIR/$BITRIX_SCRIPT_NAME"
  mkdir -p "$output_dir"

  # Step 1. Download script
  BITRIX_META_SCRIPT_PATH="$output_dir/$BITRIX_SCRIPT_NAME"
  _bx_download_script "$output_dir" "$BITRIX_SCRIPT_NAME"
  _bx_dump_script_meta "$BITRIX_META_SCRIPT_PATH"

  # Step 2. Create manifest.json
  BITRIX_MANIFEST_PATH="$output_dir/manifest.json"
  _bx_create_initial_manifest "$BITRIX_MANIFEST_PATH"
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

# Export variables (github)
_bx_export_github_variables
