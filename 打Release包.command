#!/bin/bash
# macOS double-click entry point for the Release test APK.
set -u
set -o pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${PROJECT_DIR}" || exit 1

exec ./打包APK.command --release
