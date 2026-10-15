#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "${1:?Pass the extracted source directory}" && pwd)"
mkdir -p "${2:?Pass an output directory}"
OUTPUT_ROOT="$(cd "$2" && pwd)"
BUILDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/f50-ios.XXXXXX")"

write_build_summary() {
  build_exit=$?
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo '## Build diagnostics'
      echo "Exit code: $build_exit"
      for log in "$OUTPUT_ROOT/toolchain.log" "$OUTPUT_ROOT/core-tests.log" "$OUTPUT_ROOT/xcodebuild.log"; do
        [[ -f "$log" ]] || continue
        echo "### $(basename "$log")"
        echo '```text'
        tail -n 120 "$log"
        echo '```'
      done
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}
trap write_build_summary EXIT

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This build requires macOS with Xcode and the iPhoneOS SDK.' >&2
  exit 1
fi
test -f "$SOURCE_ROOT/iOS/project.yml"
test -f "$SOURCE_ROOT/LICENSE"
command -v xcodegen >/dev/null
xcodebuild -version | tee "$OUTPUT_ROOT/toolchain.log"
xcodegen --version | tee -a "$OUTPUT_ROOT/toolchain.log"

swift test --package-path "$SOURCE_ROOT" \
  --scratch-path "$BUILD_ROOT/core-tests" \
  -Xswiftc -strict-concurrency=minimal \
  2>&1 | tee "$OUTPUT_ROOT/core-tests.log"

(
  cd "$SOURCE_ROOT/iOS"
  xcodegen generate
) 2>&1 | tee "$OUTPUT_ROOT/project-generation.log"

xcodebuild \
  -project "$SOURCE_ROOT/iOS/F50Monitor-iOS.xcodeproj" \
  -scheme F50Monitor-iOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -sdk iphoneos \
  -derivedDataPath "$BUILD_ROOT/derived-data" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_IDENTITY= \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "$OUTPUT_ROOT/xcodebuild.log"

APP_PATH="$BUILD_ROOT/derived-data/Build/Products/Release-iphoneos/F50Monitor-iOS.app"
test -f "$APP_PATH/Info.plist"
mkdir -p "$BUILD_ROOT/package/Payload"
ditto "$APP_PATH" "$BUILD_ROOT/package/Payload/F50Monitor-iOS.app"
(
  cd "$BUILD_ROOT/package"
  /usr/bin/zip -q -r "$OUTPUT_ROOT/f50-monitor-ios-2.5-unsigned.ipa" Payload
)

python3 "$BUILDER_ROOT/verify-ipa.py" \
  "$OUTPUT_ROOT/f50-monitor-ios-2.5-unsigned.ipa" \
  --report "$OUTPUT_ROOT/ipa-verification.json"
cp "$SOURCE_ROOT/LICENSE" "$OUTPUT_ROOT/UPSTREAM-LICENSE"
(
  cd "$OUTPUT_ROOT"
  shasum -a 256 f50-monitor-ios-2.5-unsigned.ipa > SHA256SUMS.txt
)
python3 - "$OUTPUT_ROOT/provenance.json" <<'PY'
import datetime
import json
import os
import pathlib
import subprocess
import sys

pathlib.Path(sys.argv[1]).write_text(json.dumps({
    "source_repository": "https://github.com/koldllc/f50-monitor",
    "source_commit": "741984b434f5ee93578bdcc34c32490e975f5595",
    "source_status": "last public iOS source before removal from main",
    "upstream_app_version": "2.5",
    "upstream_build_number": "9",
    "built_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    "workflow_repository": os.getenv("GITHUB_REPOSITORY"),
    "workflow_commit": os.getenv("GITHUB_SHA"),
    "workflow_run_id": os.getenv("GITHUB_RUN_ID"),
    "signing": "unsigned; requires the recipient's own signing identity and profile",
    "verification": "Swift core tests and iPhoneOS Release compilation; no real-device test"
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
echo "Verified unsigned IPA: $OUTPUT_ROOT/f50-monitor-ios-2.5-unsigned.ipa"

