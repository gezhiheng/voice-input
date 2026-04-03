#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="${ROOT_DIR}/VERSION"

if [[ ! -f "${VERSION_FILE}" ]]; then
  echo "VERSION file not found at ${VERSION_FILE}" >&2
  exit 1
fi

VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
if [[ -z "${VERSION}" ]]; then
  echo "VERSION file is empty" >&2
  exit 1
fi

TAG="v${VERSION}"
APP_NAME="${APP_NAME:-VoiceInput}"
DIST_DIR="${ROOT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
ARCHIVE_PATH="${DIST_DIR}/${APP_NAME}-${TAG}.zip"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command git
require_command gh
require_command make

cd "${ROOT_DIR}"

LATEST_TAG="$(git tag --list 'v*' --sort=-version:refname | head -n 1 || true)"
if [[ "${LATEST_TAG}" == "${TAG}" ]]; then
  echo "Version ${TAG} is already the latest local tag."
fi

echo "Building ${APP_NAME} ${TAG}..."
make build

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "Expected app bundle at ${APP_BUNDLE}" >&2
  exit 1
fi

rm -f "${ARCHIVE_PATH}"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ARCHIVE_PATH}"

if ! git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  git tag "${TAG}"
fi

if ! git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  git push origin "${TAG}"
fi

if gh release view "${TAG}" >/dev/null 2>&1; then
  gh release upload "${TAG}" "${ARCHIVE_PATH}" --clobber
else
  gh release create "${TAG}" "${ARCHIVE_PATH}" \
    --title "${APP_NAME} ${TAG}" \
    --generate-notes
fi

echo "Created GitHub release ${TAG}"
