#!/usr/bin/env bash
# Run iOS verification only on a real macOS runner. Windows uses static gates.
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
rm -f CI_REPORT.md
mkdir -p artifacts screenshots
RUN_DIR="${ROOT_DIR}/artifacts/run-$(date -u '+%Y%m%dT%H%M%SZ')-$$"
mkdir -p "${RUN_DIR}/DerivedData"

if [[ "$(uname -s)" != "Darwin" ]]; then
  cat > CI_REPORT.md <<'EOF'
# BPHealth CI 报告

- 结果：未执行 iOS 验证。
- 原因：`scripts/remote-verify.sh` 只允许在真实 macOS runner 上运行；Windows 结果不能替代 Xcode、XCTest、Simulator 或 Instruments。
EOF
  exit 2
fi

run_step() {
  local label="$1"; local logfile="$2"; shift 2
  echo "==> ${label}"
  "$@" >"${logfile}" 2>&1
  local status=$?
  if [[ ${status} -eq 0 ]]; then echo "PASS: ${label}"; else echo "FAIL: ${label} (exit ${status})"; fi
  return ${status}
}

DEVICE_UDID=""
if DEVICE_UDID="$(python3 - <<'PY'
import json, subprocess
payload = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
for name in ("iPhone 16", "iPhone 15", "iPhone 14"):
    for devices in payload.get("devices", {}).values():
        for device in devices:
            if device.get("name") == name and device.get("isAvailable"):
                print(device["udid"]); raise SystemExit
for devices in payload.get("devices", {}).values():
    for device in devices:
        if device.get("name", "").startswith("iPhone ") and device.get("isAvailable"):
            print(device["udid"]); raise SystemExit
raise SystemExit("No available iPhone simulator")
PY
)"; then :; else DEVICE_UDID=""; fi
if [[ -z "${DEVICE_UDID}" ]]; then
  cat > CI_REPORT.md <<EOF
# BPHealth CI 报告

- 结果：失败
- 原因：macOS runner 没有可用的 iPhone Simulator；未执行 build/test/analyze。
- 原始工件目录：${RUN_DIR}
EOF
  exit 1
fi

DESTINATION="platform=iOS Simulator,id=${DEVICE_UDID},arch=arm64"
BUNDLE_ID="$(xcodebuild -showBuildSettings -project BPHealth.xcodeproj -scheme BPHealth 2>/dev/null | awk -F'= ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / {print $2; exit}' | tr -d '[:space:]')"
# xcodebuild may emit an unresolved/non-reverse-DNS value when the setting is
# inherited from a generated test target. Never pass that value to simctl.
if [[ ! "${BUNDLE_ID}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$ ]]; then BUNDLE_ID="com.example.bphealth"; fi

run_step "Build" "${RUN_DIR}/build.log" xcodebuild build -project BPHealth.xcodeproj -scheme BPHealth -destination "${DESTINATION}" -derivedDataPath "${RUN_DIR}/DerivedData" -resultBundlePath "${RUN_DIR}/build.xcresult" CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
BUILD_EXIT=$?
run_step "XCTest and UI tests" "${RUN_DIR}/test.log" xcodebuild test -project BPHealth.xcodeproj -scheme BPHealth -destination "${DESTINATION}" -derivedDataPath "${RUN_DIR}/DerivedData" -resultBundlePath "${RUN_DIR}/test.xcresult" -enableCodeCoverage YES CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
TEST_EXIT=$?
run_step "Static analysis" "${RUN_DIR}/analyze.log" xcodebuild analyze -project BPHealth.xcodeproj -scheme BPHealth -destination "${DESTINATION}" CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
ANALYZE_EXIT=$?

run_step "Boot simulator" "${RUN_DIR}/simulator-boot.log" xcrun simctl boot "${DEVICE_UDID}"
xcrun simctl bootstatus "${DEVICE_UDID}" -b >"${RUN_DIR}/simulator.log" 2>&1
APP_PATH="${RUN_DIR}/DerivedData/Build/Products/Debug-iphonesimulator/BPHealth.app"
if [[ -d "${APP_PATH}" ]] && xcrun simctl install "${DEVICE_UDID}" "${APP_PATH}" >"${RUN_DIR}/simulator-install.log" 2>&1 && xcrun simctl launch "${DEVICE_UDID}" "${BUNDLE_ID}" >"${RUN_DIR}/simulator-launch.log" 2>&1; then LAUNCH_EXIT=0; else LAUNCH_EXIT=1; fi
if [[ ${LAUNCH_EXIT} -eq 0 ]] && xcrun simctl io "${DEVICE_UDID}" screenshot "${RUN_DIR}/dashboard.png" >"${RUN_DIR}/screenshot.log" 2>&1; then
  SCREENSHOT_EXIT=0; cp "${RUN_DIR}/dashboard.png" screenshots/dashboard.png
else
  SCREENSHOT_EXIT=1
fi

if [[ -f artifacts/swiftlint.exit ]]; then cp artifacts/swiftlint.exit "${RUN_DIR}/swiftlint.exit"; fi
if [[ -f artifacts/swiftlint.json ]]; then cp artifacts/swiftlint.json "${RUN_DIR}/swiftlint.json"; fi
python3 scripts/ci_report.py --run-dir "${RUN_DIR}" --device "${DEVICE_UDID}" --bundle-id "${BUNDLE_ID}" --build-exit "${BUILD_EXIT}" --test-exit "${TEST_EXIT}" --analyze-exit "${ANALYZE_EXIT}" --launch-exit "${LAUNCH_EXIT}" --screenshot-exit "${SCREENSHOT_EXIT}"
REPORT_EXIT=$?
cp CI_REPORT.md artifacts/CI_REPORT.md
exit ${REPORT_EXIT}
