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

# @description Download archive
# @param $1 string Output filepath
function _bx_download_distro() {
  # shellcheck disable=SC2155
  local basename=$(basename "$1")
  if [[ -f "$1" ]]; then
    # shellcheck disable=SC2086
    echo "🐞 Local file '$basename' already exists. Skipping..."
    return
  fi

  # Define remote URL
  local extension=${basename#*.}
  local download_url
  if [[ $BITRIX_DISTRO_TYPE == portal ]]; then
    download_url="https://www.1c-bitrix.ru/download/portal/${BITRIX_DISTRO_CODE}_encode.$extension"
  else
    download_url="https://www.1c-bitrix.ru/download/${BITRIX_DISTRO_CODE}_encode.$extension"
  fi

  # Execute
  echo "⬇️ Downloading archive ($download_url)..."
  curl -SL "$download_url" -o "$1"
}

# @description Extract file meta (tar)
# @param $1 string Input distro archive
# @param $2 string Output manifest.json
function _bx_extract_distro_meta() {
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

# @description Extract all module versions
# @param $1 string Input distro.zip
# @param $2 string Output module_versions.json
function _bx_extract_zip_module_versions() {
  # shellcheck disable=SC2155
  local basename=$(basename "$1")
  echo "ℹ️ Extracting module versions from '$basename'"
  if [[ ! -f "$1" ]]; then
    echo "⚠️ Input file '$basename' not found. Skipping..."
    return
  fi

  # shellcheck disable=SC2155
  local file_list=$(unzip -l "$1" 'bitrix/modules/*/install/version.php' | awk '/bitrix\/modules/ {print $4}')
  local tmp_file=$(mktemp)

  for file in $file_list; do
    module_id=$(echo "$file" | cut -d'/' -f3)
    content=$(unzip -p "$1" "$file")
    # Parse & validate 'VERSION'
    version=$(echo "$content" | grep -Ei "['\"]VERSION['\"]\s*=>\s*['\"]" | sed -E "s/.*['\"]VERSION['\"]\s*=>\s*['\"]([^'\"]+)['\"].*/\1/")
    if [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "- Extract '$module_id' version: $version"
    else
      echo "- Warning: Module '$module_id' doesn't contain valid 'version.php'."
      version=null
    fi

    # Parse & validate 'VERSION_DATE'
    version_date=$(echo "$content" | grep -Ei "['\"]VERSION_DATE['\"]\s*=>\s*['\"]" | sed -E "s/.*['\"]VERSION_DATE['\"]\s*=>\s*['\"]([^'\"]+)['\"].*/\1/")
    if date -d "$version_date" >/dev/null 2>&1; then
      version_date=$(date -d "$version_date" --iso-8601=seconds)
      echo "- Extract '$module_id' version date: $version_date"
    else
      version_date=null
      echo "- Warning: Module '$module_id' doesn't contain valid 'version.php'."
    fi

    # Append data
    jq --arg id "$module_id" \
      --arg ver "$version" \
      --arg date "$version_date" \
      '.bitrix.modules[$id] = {"id": $id, "version": $ver, "version_date": (if $date == "" then null else $date end)}' \
      "$2" > "$tmp_file" && mv "$tmp_file" "$2"
  done
}

# @description Extract kernel version & date
# @param $1 string Input distro.zip
function _bx_extract_zip_sm_version() {
  if [[ ! -f "$1" ]]; then
    echo "⚠️ Input file '$1' not found. Skipping."
    return
  fi

  # shellcheck disable=SC2155
  local php_content=$(unzip -p "$1" 'bitrix/modules/main/classes/general/version.php')
  if [[ -z "$php_content" ]]; then
    echo "⚠️ Failed to extract 'version.php' from '$1'"
    return
  fi

  # shellcheck disable=SC2155
  local sm_version=$(echo "$php_content" | grep -w 'SM_VERSION' | awk -F "['\"]" '{print $4}')
  if [[ $sm_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    BITRIX_SM_VERSION="$sm_version"
    echo "🏷️ Main version: $BITRIX_SM_VERSION"
  else
    echo "⚠️ Failed to parse 'SM_VERSION'. Skipping..."
    return
  fi

  # shellcheck disable=SC2155
  local sm_version_date=$(echo "$php_content" | grep -w "SM_VERSION_DATE" | awk -F "['\"]" '{print $4}')
  if date -d "$sm_version_date" >/dev/null 2>&1; then
    sm_version_date=$(date -d "$sm_version_date" --iso-8601=seconds)
    BITRIX_SM_VERSION_DATE="$sm_version_date"
    echo "📅 Main version date: $BITRIX_SM_VERSION_DATE"
  fi
}

# ----------------------------------------------------------------
# Commands
# ----------------------------------------------------------------

function _cmd_run() {
  if [[ -z "$BITRIX_OUTPUT_DIR" ]]; then
    BITRIX_OUTPUT_DIR="$S_ROOT_DIR/dist/$BITRIX_DISTRO_TYPE/$BITRIX_DISTRO_CODE"
  fi

  # Step 0. Prepare
  mkdir -p "$BITRIX_OUTPUT_DIR"
  BITRIX_MANIFEST_PATH="$BITRIX_OUTPUT_DIR/manifest.json"

  # Step 1. Download zip archive
  BITRIX_ZIP_PATH="$BITRIX_OUTPUT_DIR/${BITRIX_DISTRO_CODE}_encode.zip"
  _bx_download_distro "$BITRIX_ZIP_PATH"

  # Step 2. Extract kernel meta
  _bx_extract_zip_sm_version "$BITRIX_ZIP_PATH" "$BITRIX_MANIFEST_PATH"

  # Step 3. Check kernel version
  if [[ -z "$BITRIX_SM_VERSION" || "$BITRIX_SM_VERSION" == 'null' ]]; then
    echo "❌ Failed to define kernel (main) version."
    echo "SKIP_PUBLISH=true" >> "$GITHUB_ENV"
    exit 1
  fi

  # Step 4. Check release duplicates
  BITRIX_RELEASE_TAG="${BITRIX_DISTRO_CODE}-${BITRIX_SM_VERSION}"
  _git_check_release_tag_exists "$BITRIX_RELEASE_TAG"

  # Step 5. Create manifest & dump zip meta
  _bx_create_initial_manifest "$BITRIX_MANIFEST_PATH"
  _bx_extract_distro_meta "$BITRIX_ZIP_PATH" "$BITRIX_MANIFEST_PATH"
  _bx_extract_zip_module_versions "$BITRIX_ZIP_PATH" "$BITRIX_MANIFEST_PATH"

  # Step 6. Download tar archive
  BITRIX_TAR_PATH="$BITRIX_OUTPUT_DIR/${BITRIX_DISTRO_CODE}_encode.tar.gz"
  _bx_download_distro "$BITRIX_TAR_PATH"

  # Step 7. Export tar meta
  _bx_extract_distro_meta "$BITRIX_TAR_PATH" "$BITRIX_MANIFEST_PATH"

  # Step 8. Export github variables
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
    echo "❌ Undefined distro - $1"
    exit 1
    ;;
esac

# Parse next options
for i in "$@"; do
  case "$i" in
    --env=*)
      # shellcheck disable=SC2046
      export $(grep -E '^#' "${i#*=}" | xargs)
      shift
      ;;
    --type=*)
      BITRIX_DISTRO_TYPE="${i#*=}"
      shift
      ;;
    --output=*)
      BITRIX_OUTPUT_DIR="${i#*=}"
      shift
      ;;
  esac
done

# Process
_cmd_run
