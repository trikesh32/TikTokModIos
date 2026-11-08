#!/bin/bash
set -euo pipefail
task_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
task_sdk="${IOS_SDK_PATH:-$task_root/../tools/ios-sdks/iPhoneOS16.5.sdk}"
mkdir -p "$task_root/build"
region_flags=()
region_sources=()
region_frameworks=()
if [[ "${1:-}" == "--region" || "${1:-}" == "--region-diagnostics" || "${1:-}" == "--region-requests" || "${1:-}" == "--region-aggressive" ]]; then
  region_flags=(-DTT_REGION_COMPAT)
  region_sources=("$task_root/src/RegionCompatibility.m" "$task_root/src/RegionProfile.m" "$task_root/src/RegionSettings.m" "$task_root/src/RegionMenu.m")
  region_frameworks=(-framework UIKit -framework CoreGraphics)
  xcrun clang -DTAP_TESTING -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror \
    -I"$task_root/src" "$task_root/src/RegionCompatibility.m" "$task_root/src/RegionProfile.m" "$task_root/tests/RegionCompatibilityTests.m" \
    -framework Foundation -o "$task_root/build/region-compatibility-tests"
  "$task_root/build/region-compatibility-tests"
  xcrun clang -DTAP_TESTING -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror \
    -I"$task_root/src" "$task_root/src/RegionMenu.m" "$task_root/tests/RegionMenuTests.m" \
    -framework Foundation -o "$task_root/build/region-menu-tests"
  "$task_root/build/region-menu-tests"
  if [[ "$1" == "--region-diagnostics" || "$1" == "--region-requests" || "$1" == "--region-aggressive" ]]; then
    region_flags+=(-DTT_REGION_DIAGNOSTICS)
    region_sources+=("$task_root/src/RegionObservation.m")
    xcrun clang -DTAP_TESTING -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror \
      -I"$task_root/src" "$task_root/src/RegionObservation.m" "$task_root/tests/RegionObservationTests.m" \
      -framework Foundation -o "$task_root/build/region-observation-tests"
    "$task_root/build/region-observation-tests"
  fi
  if [[ "$1" == "--region-aggressive" ]]; then
    region_flags+=(-DTT_REGION_AGGRESSIVE)
    region_sources+=("$task_root/src/RegionSources.m" "$task_root/src/RegionSignals.m" "$task_root/src/RegionEnvironment.m" "$task_root/src/RegionPNS.m")
    xcrun clang -DTAP_TESTING -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror \
      -I"$task_root/src" "$task_root/src/RegionSources.m" "$task_root/src/RegionSignals.m" "$task_root/src/RegionEnvironment.m" "$task_root/src/RegionCompatibility.m" "$task_root/src/RegionProfile.m" \
      "$task_root/tests/RegionSourcesTests.m" -framework Foundation -o "$task_root/build/region-source-tests"
    "$task_root/build/region-source-tests"
    xcrun clang -DTAP_TESTING -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror \
      -I"$task_root/src" "$task_root/src/RegionSources.m" "$task_root/src/RegionSignals.m" "$task_root/src/RegionEnvironment.m" "$task_root/src/RegionCompatibility.m" "$task_root/src/RegionProfile.m" \
      "$task_root/tests/RegionEnvironmentTests.m" -framework Foundation -o "$task_root/build/region-environment-tests"
    "$task_root/build/region-environment-tests"
    xcrun clang -DTAP_TESTING -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror \
      -I"$task_root/src" "$task_root/src/RegionSources.m" "$task_root/src/RegionSignals.m" "$task_root/src/RegionEnvironment.m" "$task_root/src/RegionCompatibility.m" "$task_root/src/RegionProfile.m" \
      "$task_root/src/RegionObservation.m" "$task_root/src/RegionPNS.m" "$task_root/tests/RegionPNSTests.m" \
      -framework Foundation -o "$task_root/build/region-pns-tests"
    "$task_root/build/region-pns-tests"
    xcrun clang -DTAP_TESTING -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror \
      -I"$task_root/src" "$task_root/src/RegionSources.m" "$task_root/src/RegionSignals.m" "$task_root/src/RegionEnvironment.m" "$task_root/src/RegionCompatibility.m" "$task_root/src/RegionProfile.m" \
      "$task_root/src/RegionObservation.m" "$task_root/src/RegionPNS.m" "$task_root/tests/RegionProfileTests.m" \
      -framework Foundation -o "$task_root/build/region-profile-tests"
    "$task_root/build/region-profile-tests"
  fi
  if [[ "$1" == "--region-requests" ]]; then
    region_flags+=(-DTT_REGION_REQUESTS)
    region_sources+=("$task_root/src/RegionRequest.m")
    xcrun clang -DTAP_TESTING -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror \
      -I"$task_root/src" "$task_root/src/RegionRequest.m" "$task_root/src/RegionObservation.m" \
      "$task_root/src/RegionCompatibility.m" "$task_root/src/RegionProfile.m" "$task_root/tests/RegionRequestTests.m" \
      -framework Foundation -o "$task_root/build/region-request-tests"
    "$task_root/build/region-request-tests"
  fi
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--region|--region-diagnostics|--region-requests|--region-aggressive]" >&2
  exit 2
fi
xcrun clang -DTT_COMPAT_RELEASE -DTAP_TESTING -fobjc-arc -fblocks -O2 \
  -Wall -Wextra -Werror -Wno-unused-parameter -I"$task_root/src" \
  "$task_root/src/KeychainProbe.m" "$task_root/src/BundleIdentity.m" "$task_root/src/ModCompatibility.m" "$task_root/src/SigningContext.m" \
  "$task_root/tests/ModCompatibilityTests.m" "$task_root/tests/CompatibilityReleaseTests.m" \
  -framework Foundation -framework Security -o "$task_root/build/compatibility-release-tests"
"$task_root/build/compatibility-release-tests"
xcrun clang -DTAP_TESTING -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror \
  -I"$task_root/src" "$task_root/src/SigningContext.m" "$task_root/tests/SigningContextTests.m" \
  -framework Foundation -framework Security -o "$task_root/build/signing-context-tests"
"$task_root/build/signing-context-tests"
xcrun clang -target arm64-apple-ios15.0 -isysroot "$task_sdk" -O2 \
  -c "$task_root/vendor/fishhook/fishhook.c" -o "$task_root/build/fishhook-release.o"
xcrun clang -target arm64-apple-ios15.0 -isysroot "$task_sdk" -DTT_COMPAT_RELEASE \
  "${region_flags[@]}" \
  -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -Wno-unused-parameter \
  -dynamiclib -I"$task_root/src" -I"$task_root/vendor/fishhook" \
  "$task_root/src/CompatibilityMain.m" "$task_root/src/KeychainProbe.m" \
  "$task_root/src/BundleIdentity.m" "$task_root/src/ModCompatibility.m" "$task_root/src/SigningContext.m" "$task_root/build/fishhook-release.o" \
  "${region_sources[@]}" "${region_frameworks[@]}" \
  -framework Foundation -framework Security -install_name @rpath/TikTokCompatibility.dylib \
  -o "$task_root/build/TikTokCompatibility-iOS.dylib"
codesign --force --sign - "$task_root/build/TikTokCompatibility-iOS.dylib"
codesign --verify --strict "$task_root/build/TikTokCompatibility-iOS.dylib"
python3 - "$task_root/build/TikTokCompatibility-iOS.dylib" <<'PY'
from pathlib import Path
import subprocess,sys
p=Path(sys.argv[1]);data=p.read_bytes()
for marker in (b'TikTokAuthProbe',b'account_response',b'compat_read',b'keychain_result',
               b'generateAssertion:clientDataHash:completionHandler:',b'google_phase'):
    if marker in data:
        raise SystemExit('Unexpected diagnostic marker in release: '+marker.decode())
symbols=subprocess.check_output(['xcrun','nm','-g',str(p)],text=True)
if '_TAPEmit' in symbols or '_TAPInstallAttestObserver' in symbols:
    raise SystemExit('Diagnostic symbol linked into release')
print('Release module verified: no AuthProbe/OAuth/App Attest observers or diagnostic file writer')
PY
