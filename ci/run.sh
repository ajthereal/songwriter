#!/bin/bash
# Builds the app, runs unit tests, and publishes logs to branch ci-results.
# Never fails the job itself; the verdict is in STATUS.
set -u -o pipefail

ROOT="$(pwd)"
SHA="$(git rev-parse HEAD)"
OUT="${RUNNER_TEMP:-/tmp}/ci-out"
rm -rf "$OUT"; mkdir -p "$OUT"
BUILD_LOG="$OUT/build.log"
TEST_LOG="$OUT/test.log"
: > "$BUILD_LOG"; : > "$TEST_LOG"

# Newest Xcode
XC="$(ls -d /Applications/Xcode_*.app 2>/dev/null | sort -V | tail -1)"
if [ -n "$XC" ]; then sudo xcode-select -s "$XC/Contents/Developer"; fi
{
  echo "== Xcode: ${XC:-default}"; xcodebuild -version; swift --version
  echo "== Branch: ${GITHUB_REF_NAME:-?}  SHA: $SHA"
} 2>&1 | tee -a "$BUILD_LOG"

BUILD_RC=0
TEST_RC=0

if [ -f "$ROOT/ci/extra.sh" ]; then bash "$ROOT/ci/extra.sh" 2>&1 | tee -a "$BUILD_LOG"; fi

# ---------- Build ----------
if [ -d "$ROOT/Songwriter.swiftpm" ]; then
  cd "$ROOT/Songwriter.swiftpm"
  echo "== xcodebuild -list" | tee -a "$BUILD_LOG"
  xcodebuild -list 2>&1 | tee -a "$BUILD_LOG" | tail -40
  LIST="$(xcodebuild -list 2>/dev/null)"
  SCHEME="Songwriter"
  if ! echo "$LIST" | grep -qx "[[:space:]]*Songwriter"; then
    SCHEME="$(echo "$LIST" | awk '/Schemes:/{f=1;next} f&&NF{gsub(/^[ \t]+/,"");print;exit}')"
  fi
  echo "== Using scheme: $SCHEME" | tee -a "$BUILD_LOG"
  xcodebuild -scheme "$SCHEME" -destination 'generic/platform=iOS Simulator' \
    -skipMacroValidation -skipPackagePluginValidation \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 | tee -a "$BUILD_LOG"
  BUILD_RC=${PIPESTATUS[0]}
  echo "== build exit code: $BUILD_RC" | tee -a "$BUILD_LOG"
  cd "$ROOT"
else
  echo "== No Songwriter.swiftpm yet; skipping build" | tee -a "$BUILD_LOG"
  BUILD_RC=0
fi

# ---------- Tests ----------
if [ -d "$ROOT/CoreTests" ] && [ -d "$ROOT/Songwriter.swiftpm" ]; then
  cd "$ROOT/CoreTests"
  rm -rf Sources/Core; mkdir -p Sources/Core
  APP="$ROOT/Songwriter.swiftpm"
  for d in Model Theory; do
    [ -d "$APP/$d" ] && cp -R "$APP/$d/." Sources/Core/
  done
  for f in Export/MIDIFileWriter.swift Export/SunoPack.swift Export/Loudness.swift Store/UndoStack.swift; do
    [ -f "$APP/$f" ] && cp "$APP/$f" Sources/Core/
  done
  ls -R Sources | tee -a "$TEST_LOG" >/dev/null
  swift test 2>&1 | tee -a "$TEST_LOG"
  TEST_RC=${PIPESTATUS[0]}
  echo "== test exit code: $TEST_RC" | tee -a "$TEST_LOG"
  cd "$ROOT"
else
  echo "== No CoreTests yet; skipping tests" | tee -a "$TEST_LOG"
fi

# ---------- Status ----------
{
  grep -E "error:" "$BUILD_LOG" | sed -E 's#^/Users/runner/work/[^/]+/[^/]+/##' | awk '!s[$0]++' | head -150 | sed 's/^/BUILD /'
  grep -E "error:|XCTAssert.*failed|Fatal error|failed \(" "$TEST_LOG" | sed -E 's#^/Users/runner/work/[^/]+/[^/]+/##' | awk '!s[$0]++' | head -100 | sed 's/^/TEST /'
} > "$OUT/errors.txt"

B=PASS; [ "$BUILD_RC" -ne 0 ] && B=FAIL
T=PASS; [ "$TEST_RC" -ne 0 ] && T=FAIL
V=PASS; { [ "$B" = FAIL ] || [ "$T" = FAIL ]; } && V=FAIL
{
  echo "$V"
  echo "build=$B tests=$T branch=${GITHUB_REF_NAME:-?}"
  head -25 "$OUT/errors.txt"
} > "$OUT/STATUS"
cat "$OUT/STATUS"

# ---------- Publish to ci-results ----------
REMOTE="https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
for attempt in 1 2 3 4 5 6 7 8; do
  PUB="${RUNNER_TEMP:-/tmp}/pub"
  rm -rf "$PUB"
  if git ls-remote --exit-code --heads "$REMOTE" ci-results >/dev/null 2>&1; then
    git clone --quiet --depth 1 --branch ci-results "$REMOTE" "$PUB"
  else
    mkdir -p "$PUB"; git -C "$PUB" init --quiet -b ci-results; git -C "$PUB" remote add origin "$REMOTE"
  fi
  cd "$PUB"
  git config user.name "ci"; git config user.email "ci@users.noreply.github.com"
  rm -rf "$SHA" latest
  mkdir -p "$SHA" latest
  cp "$OUT/build.log" "$OUT/test.log" "$OUT/STATUS" "$OUT/errors.txt" "$SHA/"
  cp "$OUT/build.log" "$OUT/test.log" "$OUT/STATUS" "$OUT/errors.txt" latest/
  echo "$SHA" > latest/SHA
  git add -A
  git commit --quiet -m "ci: $SHA $V" || true
  if git push --quiet origin ci-results; then echo "published (attempt $attempt)"; break; fi
  sleep $((RANDOM % 8 + 3))
  cd "$ROOT"
done
exit 0
