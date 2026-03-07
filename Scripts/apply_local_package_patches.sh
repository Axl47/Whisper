#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
PACKAGE_ROOT="${REPO_ROOT}/SourcePackages/checkouts/FluidAudio"
PATCH_FILE="${SCRIPT_DIR}/patches/fluidaudio-swift62-streaming-asr.patch"

if [[ ! -d "${PACKAGE_ROOT}/.git" ]]; then
    echo "FluidAudio checkout not found at ${PACKAGE_ROOT}"
    echo "Resolve packages with -clonedSourcePackagesDirPath SourcePackages before applying local patches."
    exit 1
fi

if git -C "${PACKAGE_ROOT}" apply --reverse --check "${PATCH_FILE}" >/dev/null 2>&1; then
    echo "FluidAudio Swift 6.2 patch already applied."
    exit 0
fi

git -C "${PACKAGE_ROOT}" apply "${PATCH_FILE}"
echo "Applied FluidAudio Swift 6.2 compatibility patch."
