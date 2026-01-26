#!/usr/bin/env bash

# shellcheck disable=SC2155

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

# Github
GITHUB_ENV=${GITHUB_ENV:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-}

# Bitrix
BITRIX_DISTRO_CODE=${BITRIX_DISTRO_CODE:-}
BITRIX_DISTRO_TYPE=${BITRIX_DISTRO_TYPE:-}
BITRIX_RELEASE_TAG=${BITRIX_RELEASE_TAG:-}
BITRIX_SM_VERSION=${BITRIX_SM_VERSION:-null}
BITRIX_SM_VERSION_DATE=${BITRIX_SM_VERSION_DATE:-null}
BITRIX_MANIFEST_PATH=${BITRIX_MANIFEST_PATH:-}
BITRIX_OUTPUT_DIR=${BITRIX_OUTPUT_DIR:-}
BITRIX_TAR_PATH=${BITRIX_TAR_PATH:-}
BITRIX_ZIP_PATH=${BITRIX_ZIP_PATH:-}

# ----------------------------------------------------------------
# Functions
# ----------------------------------------------------------------

# @description Check if the GitHub release tag already exists
# @param $1 string Tag name
function _git_check_release_tag_exists() {
  echo "🔎 Checking release status for tag: '$1'..."
  local http_status
  if [[ -n "$GITHUB_TOKEN" ]]; then
    http_status=$(curl -s -o /dev/null -I -w "%{http_code}" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/crasivo/bitrix-archives/releases/tags/$1")
  else
    http_status=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/crasivo/bitrix-archives/releases/tags/$1")
  fi
  # Check status
  if [[ "$http_status" == '404' ]]; then
    echo "➡️ Release '$1' not found. Continuing execution..."
    return
  fi
  echo "➡️ Release '$1' already exists. Skipping publish..."
  if [[ -n "$GITHUB_ENV" ]]; then
    echo "SKIP_PUBLISH=true" >> "$GITHUB_ENV"
  fi

  # Stop execute
  exit 0
}

# @description Export all BITRIX_* variables to GitHub Actions environment
function _git_export_bitrix_variables() {
  if [[ -z "$GITHUB_ENV" ]]; then
    echo "🐞 Skipping export: GITHUB_ENV is not defined."
    return
  fi
  echo "⬆️ Exporting BITRIX environment variables..."
  for var in $(compgen -v | grep '^BITRIX_'); do
    echo "$var=${!var}" >> "$GITHUB_ENV"
  done
}

# @description Initialize the manifest.json file with product details
# @param $1 string Target manifest filepath
function _bx_create_initial_manifest() {
  echo "🧾 Creating manifest.json..."
  jq -n \
    --arg distro_code "$BITRIX_DISTRO_CODE" \
    --arg distro_type "$BITRIX_DISTRO_TYPE" \
    --arg sm_version "$BITRIX_SM_VERSION" \
    --arg sm_version_date "$BITRIX_SM_VERSION_DATE" \
    --arg release_tag "$BITRIX_RELEASE_TAG" \
    '{
      release_tag: $release_tag,
      repository: "https://github.com/crasivo/bitrix-archives",
      bitrix: {
        distro_code: $distro_code,
        distro_type: $distro_type,
        modules: {
          main: {
            id: "main",
            version: $sm_version,
            version_date: $sm_version_date
          }
        },
      },
      assets: []
    }' > "$1"
}

# @description Download distro archive with resume support and integrity verification
# @param $1 string Output filepath
function _bx_download_distro() {
  local basename=$(basename "$1")
  local extension=${basename#*.}
  local download_url

  if [[ $BITRIX_DISTRO_TYPE == portal ]]; then
    download_url="https://www.1c-bitrix.ru/download/portal/${BITRIX_DISTRO_CODE}_encode.$extension"
  else
    download_url="https://www.1c-bitrix.ru/download/${BITRIX_DISTRO_CODE}_encode.$extension"
  fi

  echo "⬇️ Downloading archive: $download_url"

  # Added -C - for resume support and retry logic
  if ! curl -SL -C - \
    --connect-timeout 30 \
    --retry 10 \
    --retry-delay 5 \
    --retry-all-errors \
    "$download_url" -o "$1"; then
      echo "❌ Error: Failed to download $basename"
      return 1
  fi

  # Basic integrity check after download/resume
  echo "🛡️ Verifying $basename integrity..."
  if [[ "$extension" == "zip" ]]; then
    unzip -tq "$1" > /dev/null 2>&1 || { echo "❌ ZIP corrupted"; rm -f "$1"; return 1; }
  elif [[ "$extension" == "gz" ]]; then
    gzip -t "$1" > /dev/null 2>&1 || { echo "❌ TAR.GZ corrupted"; rm -f "$1"; return 1; }
  fi
}

# @description Extract file metadata (hashes, size) and update the manifest
# @param $1 string Archive filepath
# @param $2 string Manifest filepath
function _bx_extract_distro_meta() {
  local basename=$(basename "$1")
  local dirname=$(dirname "$1")
  echo "ℹ️ Extracting metadata for $basename"

  local size=$(stat -c%s "$1")
  local md5=$(md5sum "$1" | awk '{ print $1 }')
  local sha1=$(sha1sum "$1" | awk '{ print $1 }')
  local sha256=$(sha256sum "$1" | awk '{ print $1 }')

  # Generate standalone checksum files as per original logic
  echo "$md5" > "$1.md5"
  echo "$md5  $basename" >> "$dirname/checksums_md5.txt"
  echo "$sha1" > "$1.sha1"
  echo "$sha1  $basename" >> "$dirname/checksums_sha1.txt"
  echo "$sha256" > "$1.sha256"
  echo "$sha256  $basename" >> "$dirname/checksums_sha256.txt"

  # Update manifest assets array
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

# @description Extract all module versions from the ZIP archive
# @param $1 string ZIP archive path
# @param $2 string Manifest JSON path
function _bx_extract_zip_module_versions() {
  local basename=$(basename "$1")
  echo "ℹ️ Extracting module versions from '$basename'..."
  if [[ ! -f "$1" ]]; then
    echo "⚠️ Error: Input file '$1' not found."
    return
  fi

  local file_list=$(unzip -l "$1" 'bitrix/modules/*/install/version.php' 2>/dev/null | awk '/bitrix\/modules/ {print $4}') || true
  local tmp_file=$(mktemp)

  for file in $file_list; do
    local module_id=$(echo "$file" | cut -d'/' -f3)
    local content=$(unzip -p "$1" "$file")
    local version=$(echo "$content" | grep -Ei "['\"]VERSION['\"]\s*=>\s*['\"]" | sed -E "s/.*['\"]VERSION['\"]\s*=>\s*['\"]([^'\"]+)['\"].*/\1/")
    if [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "- Extract '$module_id' version: $version"
    else
      echo "- Warning: Module '$module_id' doesn't contain valid 'version.php'."
      version=null
    fi

    local version_date=$(echo "$content" | grep -Ei "['\"]VERSION_DATE['\"]\s*=>\s*['\"]" | sed -E "s/.*['\"]VERSION_DATE['\"]\s*=>\s*['\"]([^'\"]+)['\"].*/\1/")
    if date -d "$version_date" >/dev/null 2>&1; then
      version_date=$(date -d "$version_date" --iso-8601=seconds)
      echo "- Extract '$module_id' version date: $version_date"
    else
      version_date=null
      echo "- Warning: Module '$module_id' doesn't contain valid 'version.php'."
    fi

    # Appending manifest.json data
    jq --arg id "$module_id" \
      --arg ver "$version" \
      --arg date "$version_date" \
      '.bitrix.modules[$id] = {"id": $id, "version": $ver, "version_date": (if $date == "" then null else $date end)}' \
      "$2" > "$tmp_file" && mv "$tmp_file" "$2"
  done
}

# @description Extract kernel version and date from the main module
# @param $1 string ZIP archive path
function _bx_extract_zip_sm_version() {
  if [[ ! -f "$1" ]]; then
    echo "⚠️ Error: ZIP file not found for version extraction."
    return
  fi

  local php_content=$(unzip -p "$1" 'bitrix/modules/main/classes/general/version.php' 2>/dev/null || echo "")
  if [[ -z "$php_content" ]]; then
    echo "⚠️ Could not extract version.php"
    return
  fi

  local sm_version=$(echo "$php_content" | grep -w 'SM_VERSION' | awk -F "['\"]" '{print $4}')
  if [[ $sm_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    BITRIX_SM_VERSION="$sm_version"
    echo "🏷️ SM_VERSION: $BITRIX_SM_VERSION"
  else
    echo "⚠️ Failed to parse SM_VERSION"
    return
  fi

  local sm_version_date=$(echo "$php_content" | grep -w "SM_VERSION_DATE" | awk -F "['\"]" '{print $4}')
  if date -d "$sm_version_date" >/dev/null 2>&1; then
    BITRIX_SM_VERSION_DATE=$(date -d "$sm_version_date" --iso-8601=seconds)
    echo "📅 SM_VERSION_DATE: $BITRIX_SM_VERSION_DATE"
  fi
}

# ----------------------------------------------------------------
# Main logic
# ----------------------------------------------------------------

# @description Main workflow execution
function _cmd_run() {
  if [[ -z "$BITRIX_OUTPUT_DIR" ]]; then
    BITRIX_OUTPUT_DIR="$S_ROOT_DIR/dist/$BITRIX_DISTRO_TYPE/$BITRIX_DISTRO_CODE"
  fi

  # Step 0. Prepare
  mkdir -p "$BITRIX_OUTPUT_DIR"
  BITRIX_MANIFEST_PATH="$BITRIX_OUTPUT_DIR/manifest.json"

  # Step 1. Download ZIP
  BITRIX_ZIP_PATH="$BITRIX_OUTPUT_DIR/${BITRIX_DISTRO_CODE}_encode.zip"
  _bx_download_distro "$BITRIX_ZIP_PATH"

  # Step 2. Get kernel info
  _bx_extract_zip_sm_version "$BITRIX_ZIP_PATH"

  # Step 3. Validation
  if [[ -z "$BITRIX_SM_VERSION" || "$BITRIX_SM_VERSION" == 'null' ]]; then
    echo "❌ Error: Kernel (main) version is undefined."
    [[ -n "$GITHUB_ENV" ]] && echo "SKIP_PUBLISH=true" >> "$GITHUB_ENV"
    exit 1
  fi

  # Step 4. Release check
  BITRIX_RELEASE_TAG="${BITRIX_DISTRO_CODE}-${BITRIX_SM_VERSION}"
  _git_check_release_tag_exists "$BITRIX_RELEASE_TAG"

  # Step 5. Manifest & Zip Meta
  _bx_create_initial_manifest "$BITRIX_MANIFEST_PATH"
  _bx_extract_distro_meta "$BITRIX_ZIP_PATH" "$BITRIX_MANIFEST_PATH"
  _bx_extract_zip_module_versions "$BITRIX_ZIP_PATH" "$BITRIX_MANIFEST_PATH"

  # Step 6. Download TAR
  BITRIX_TAR_PATH="$BITRIX_OUTPUT_DIR/${BITRIX_DISTRO_CODE}_encode.tar.gz"
  _bx_download_distro "$BITRIX_TAR_PATH"

  # Step 7. Tar Meta
  _bx_extract_distro_meta "$BITRIX_TAR_PATH" "$BITRIX_MANIFEST_PATH"

  # Step 8. Export
  _git_export_bitrix_variables
  echo "🚀 Process complete for $BITRIX_RELEASE_TAG"
}

# ----------------------------------------------------------------
# Execution entry point
# ----------------------------------------------------------------

# Check arguments
if [[ "$#" -lt 1 ]]; then
  echo "❌ Error: Distro code argument required"
  exit 1
fi

# Define distro
case "$1" in
  start|standard|business|small_business|business_cluster|business_cluster_postgresql)
    BITRIX_DISTRO_CODE="$1"
    BITRIX_DISTRO_TYPE='web'
    shift
    ;;
  bitrix24|bitrix24_shop|bitrix24_enterprise)
    BITRIX_DISTRO_CODE="$1"
    BITRIX_DISTRO_TYPE='portal'
    shift
    ;;
  *)
    echo "❌ Error: Undefined distro - $1"
    exit 1
    ;;
esac

# Parse next options
for i in "$@"; do
  case "$i" in
    --env=*)
      # shellcheck disable=SC2046
      export $(grep -v '^#' "${i#*=}" | xargs)
      shift
      ;;
    --output=*)
      BITRIX_OUTPUT_DIR="${i#*=}"
      shift
      ;;
  esac
done

# RUN!
_cmd_run
