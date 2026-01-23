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
S_TMP_DIR="$S_ROOT_DIR/tmp"

# GitHub
GITHUB_REPO='crasivo/bitrix-archives'
GITHUB_ENV=${GITHUB_ENV:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
GITHUB_RELEASE_TAG=${GITHUB_RELEASE_TAG:-}

# Bitrix: Main
BITRIX_DISTRO_CODE=${BITRIX_DISTRO_CODE:-}
BITRIX_DISTRO_TYPE=${BITRIX_DISTRO_TYPE:-}
BITRIX_MAIN_VERSION=${BITRIX_MAIN_VERSION:-null}
BITRIX_MAIN_VERSION_DATE=${BITRIX_MAIN_VERSION_DATE:-null}

# Bitrix: Meta
BITRIX_META_TAR_FILEPATH=${BITRIX_META_TAR_FILEPATH:-null}
BITRIX_META_TAR_MD5=${BITRIX_META_TAR_MD5:-null}
BITRIX_META_TAR_SHA1=${BITRIX_META_TAR_SHA1:-null}
BITRIX_META_TAR_SHA256=${BITRIX_META_TAR_SHA256:-null}
BITRIX_META_TAR_SIZE=${BITRIX_META_TAR_SIZE:-null}
BITRIX_META_ZIP_FILEPATH=${BITRIX_META_ZIP_FILEPATH:-null}
BITRIX_META_ZIP_MD5=${BITRIX_META_ZIP_MD5:-null}
BITRIX_META_ZIP_SHA1=${BITRIX_META_ZIP_SHA1:-null}
BITRIX_META_ZIP_SHA256=${BITRIX_META_ZIP_SHA256:-null}
BITRIX_META_ZIP_SIZE=${BITRIX_META_ZIP_SIZE:-null}

# Bitrix: Manifest
BITRIX_MANIFEST_FILEPATH=${BITRIX_META_MANIFEST_FILEPATH:-}

# ----------------------------------------------------------------
# Functions
# ----------------------------------------------------------------

# @description Check release exists
# @param $1 string Tag
function _bx_check_release() {
    echo "[INFO] Check release '$1'"
    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/$GITHUB_REPO/releases/tags/$1")
    if [[ $http_status == 404 ]]; then
        echo "[INFO] Release '$1' not found. Continue..."
        return
    fi

    # Notify Github
    if [[ -n "$GITHUB_ENV" ]]; then
        echo "SKIP_PUBLISH=true" >> "$GITHUB_ENV"
    fi

    # Stop execute
    exit 0
}

# @description Создание финального manifest.json
function _bx_create_final_manifest() {
  jq -n \
      --arg distro_code "$BITRIX_DISTRO_CODE" \
      --arg distro_type "$BITRIX_DISTRO_TYPE" \
      --arg main_version  "$BITRIX_MAIN_VERSION" \
      --arg main_version_date "$BITRIX_MAIN_VERSION_DATE" \
      --arg zip_filepath  "$BITRIX_META_ZIP_FILEPATH" \
      --arg zip_md5  "$BITRIX_META_ZIP_MD5" \
      --arg zip_sha1 "$BITRIX_META_ZIP_SHA1" \
      --arg zip_sha256 "$BITRIX_META_ZIP_SHA256" \
      --arg zip_size "$BITRIX_META_ZIP_SIZE" \
      --arg tar_filepath  "$BITRIX_META_TAR_FILEPATH" \
      --arg tar_md5  "$BITRIX_META_TAR_MD5" \
      --arg tar_sha1 "$BITRIX_META_TAR_SHA1" \
      --arg tar_sha256 "$BITRIX_META_TAR_SHA256" \
      --arg tar_size "$BITRIX_META_TAR_SIZE" \
      '{
        bitrix: {
          distro_code: $distro_code,
          distro_type: $distro_type,
          main_version: (if $main_version == "null" or $main_version == "" then null else $main_version end),
          main_version_date: (if $main_version_date == "null" or $main_version_date == "" then null else $main_version_date end)
        },
        artifacts: [
          {
            filename: ($tar_filepath | split("/") | last),
            md5: $tar_md5,
            sha1: $tar_sha1,
            sha256: $tar_sha256,
            size: ($tar_size | tonumber)
          },
          {
            filename: ($zip_filepath | split("/") | last),
            md5: $zip_md5,
            sha1: $zip_sha1,
            sha256: $zip_sha256,
            size: ($zip_size | tonumber)
          }
        ],
        metadata: {
          source: "https://www.1c-bitrix.ru/download/cms.php",
          repository: "https://github.com/crasivo/bitrix-archives"
        }
      }' > "$1"
}

# @description Extract main version from zip archive
# @param $1 string Filepath (zip)
function _bx_extract_main_version() {
    # Extract PHP content
    local php_content
    php_content=$(unzip -p "$1" "bitrix/modules/main/classes/general/version.php")
    if [[ -z "$php_content" ]]; then
        echo "[WARN] Failed extract 'version.php' from '$1'"
        return
    fi

    # Parse SM_VERSION from PHP content
    local bx_version
    bx_version=$(echo "$php_content" | grep -w "SM_VERSION" | awk -F "['\"]" '{print $4}')
    if [[ $bx_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        BITRIX_MAIN_VERSION="$bx_version"
        echo "[INFO] Main version: $BITRIX_MAIN_VERSION"
    else
        BITRIX_MAIN_VERSION=null
        echo "[ERROR] Failed to parse 'SM_VERSION'."
        return
    fi

    # Parse SM_VERSION_DATE from PHP content
    local bx_date
    bx_date=$(echo "$php_content" | grep -w "SM_VERSION_DATE" | awk -F "['\"]" '{print $4}')
    if date -d "$bx_date" >/dev/null 2>&1; then
        BITRIX_MAIN_VERSION_DATE=$(date -d "$bx_date" --iso-8601=seconds)
        echo "[INFO] Main version date: $BITRIX_MAIN_VERSION_DATE"
    else
        BITRIX_MAIN_VERSION_DATE=null
        echo "[WARN] Failed to parse 'SM_VERSION_DATE'."
    fi
}

# @description Download archive
# @param $1 string Output filepath
# @param $2 string File extension
function _bx_download_distro() {
    if [[ -f $1 ]]; then
        echo "[DEBUG] Local file $1 already exists"
        return
    fi

    # Define remote URL
    local download_url
    if [[ $BITRIX_DISTRO_TYPE == portal ]]; then
        download_url="https://www.1c-bitrix.ru/download/portal/${BITRIX_DISTRO_CODE}_encode.$2"
    else
        download_url="https://www.1c-bitrix.ru/download/${BITRIX_DISTRO_CODE}_encode.$2"
    fi

    # Execute
    echo "[INFO] Download remote file: $download_url"
    curl -SL -# "$download_url" -o "$1"
    echo "[INFO] File was successfully downloaded: $1"
}

# @description Dump file meta (tar)
# @param $1 string Filepath
function _bx_dump_tar_meta() {
    echo "[INFO] Extract hashes - $1"
    BITRIX_META_TAR_SIZE=$(stat -c%s "$1")
    BITRIX_META_TAR_SIZE_MB=$(echo "scale=2; $BITRIX_META_TAR_SIZE / 1048576" | bc)
    BITRIX_META_TAR_MD5=$(md5sum "$1" | awk '{ print $1 }')
    BITRIX_META_TAR_SHA1=$(sha1sum "$1" | awk '{ print $1 }')
    BITRIX_META_TAR_SHA256=$(sha256sum "$1" | awk '{ print $1 }')
    # Dump
    echo "$BITRIX_META_TAR_SIZE" > "$1.size"
    echo "$BITRIX_META_TAR_MD5" > "$1.md5"
    echo "$BITRIX_META_TAR_SHA1" > "$1.sha1"
    echo "$BITRIX_META_TAR_SHA256" > "$1.sha256"
}

# @description Dump file meta (zip)
# @param $1 string Filepath
function _bx_dump_zip_meta() {
    echo "[INFO] Extract hashes - $1"
    BITRIX_META_ZIP_SIZE=$(stat -c%s "$1")
    BITRIX_META_ZIP_SIZE_MB=$(echo "scale=2; $BITRIX_META_ZIP_SIZE / 1048576" | bc)
    BITRIX_META_ZIP_MD5=$(md5sum "$1" | awk '{ print $1 }')
    BITRIX_META_ZIP_SHA1=$(sha1sum "$1" | awk '{ print $1 }')
    BITRIX_META_ZIP_SHA256=$(sha256sum "$1" | awk '{ print $1 }')
    # Dump
    echo "$BITRIX_META_ZIP_SIZE" > "$1.size"
    echo "$BITRIX_META_ZIP_MD5" > "$1.md5"
    echo "$BITRIX_META_ZIP_SHA1" > "$1.sha1"
    echo "$BITRIX_META_ZIP_SHA256" > "$1.sha256"
}

# @description Export variables (github action)
function _bx_export_github_variables() {
    if [[ -z "$GITHUB_ENV" ]]; then
        echo "[DEBUG] Skip export GitHub variables"
        return
    fi
    for var in $(compgen -v | grep '^BITRIX_'); do
        echo "$var=${!var}" >> "$GITHUB_ENV"
    done
}

# ----------------------------------------------------------------
# Functions
# ----------------------------------------------------------------

function _cmd_process() {
    local output_dir="$S_TMP_DIR/$BITRIX_DISTRO_TYPE/$BITRIX_DISTRO_CODE"
    mkdir -p "$output_dir"

    # Step 1: Process ZIP archive
    BITRIX_META_ZIP_FILEPATH="$output_dir/${BITRIX_DISTRO_CODE}_encode.zip"
    _bx_download_distro "$BITRIX_META_ZIP_FILEPATH" "zip"
    _bx_dump_zip_meta "$BITRIX_META_ZIP_FILEPATH"
    _bx_extract_main_version "$BITRIX_META_ZIP_FILEPATH"
    if [[ -z "$BITRIX_MAIN_VERSION" ]] || [[ $BITRIX_MAIN_VERSION == null ]]; then
        echo "[ERROR] Failed to extract main version"
        exit 1
    fi

    # Step 2: Check release
    if [[ -z "$GITHUB_RELEASE_TAG" ]]; then
        _bx_check_release "GITHUB_RELEASE_TAG"
    fi

    # Step 3: Process TAR archive
    BITRIX_META_TAR_FILEPATH="$output_dir/${BITRIX_DISTRO_CODE}_encode.tar.gz"
    _bx_download_distro "$BITRIX_META_TAR_FILEPATH" "tar.gz"
    _bx_dump_tar_meta "$BITRIX_META_TAR_FILEPATH"

    # Step 4: Create manifest
    BITRIX_MANIFEST_FILEPATH="$output_dir/manifest.json"
    _bx_create_final_manifest "$BITRIX_MANIFEST_FILEPATH"
}

# ----------------------------------------------------------------
# Runtime
# ----------------------------------------------------------------

# Check arguments
if [[ "$#" -lt 1 ]]; then
    echo "[ERROR] Illegal number of parameters"
    exit 1
fi

# Define distro
case "$1" in
    start|standard|business|small_business|business_cluster|business_cluster_postgresql)
        BITRIX_DISTRO_CODE=$1
        BITRIX_DISTRO_TYPE=web
        shift
        ;;
    bitrix24|bitrix24_shop|bitrix24_enterprise)
        BITRIX_DISTRO_CODE=$1
        BITRIX_DISTRO_TYPE=portal
        shift
        ;;
    *)
        echo "[ERROR] Undefined action ($1)"
        exit 1
        ;;
esac

# Parse options
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
    esac
done

# Process
_cmd_process

# Export GitHub variables
_bx_export_github_variables
