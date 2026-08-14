#!/bin/bash
# Generate dSYMs for Firebase/gRPC binary frameworks that Xcode re-links as
# dynamic libraries without DWARF. Matching UUID stubs satisfy App Store
# Connect "Upload Symbols Failed" checks for these vendor binaries.
#
# See: https://github.com/firebase/firebase-ios-sdk/issues/13764
#      https://developer.apple.com/forums/thread/761589

set -euo pipefail

if [ "${DEBUG_INFORMATION_FORMAT:-}" != "dwarf-with-dsym" ]; then
  echo "note: Skipping Firebase binary dSYM generation (DEBUG_INFORMATION_FORMAT=${DEBUG_INFORMATION_FORMAT:-unset})"
  exit 0
fi

FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
DSYM_FOLDER="${DWARF_DSYM_FOLDER_PATH:-}"

if [ ! -d "${FRAMEWORKS_DIR}" ]; then
  echo "note: No Frameworks directory at ${FRAMEWORKS_DIR}; skipping Firebase binary dSYM generation."
  exit 0
fi

if [ -z "${DSYM_FOLDER}" ]; then
  echo "note: DWARF_DSYM_FOLDER_PATH unset; skipping Firebase binary dSYM generation."
  exit 0
fi

mkdir -p "${DSYM_FOLDER}"

FRAMEWORKS=(
  FirebaseFirestoreInternal
  absl
  grpc
  grpcpp
  openssl_grpc
)

generated=0
for name in "${FRAMEWORKS[@]}"; do
  binary="${FRAMEWORKS_DIR}/${name}.framework/${name}"
  if [ ! -f "${binary}" ]; then
    echo "note: Skipping missing framework binary: ${name}"
    continue
  fi

  output="${DSYM_FOLDER}/${name}.framework.dSYM"
  rm -rf "${output}"
  echo "Generating dSYM for ${name}.framework"
  /usr/bin/dsymutil "${binary}" -o "${output}"
  generated=$((generated + 1))
done

echo "note: Firebase/gRPC binary dSYM generation complete (${generated} frameworks)."
