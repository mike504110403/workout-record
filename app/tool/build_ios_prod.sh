#!/bin/bash
# iOS 打包(TestFlight / App Store):一律連 Supabase workout-prod。
# 連線資訊住 repo 根目錄的 .env.prod(不進 git);只把 URL 與公開 anon key
# 當 --dart-define 帶進去,DB 密碼不進產物。
# 用法:app/tool/build_ios_prod.sh [--upload] [其他 flutter build ipa 參數]
#   --upload:pubspec build 號 +1 後打包,產物閘通過就用 App Store Connect API
#             金鑰(~/mike/asc/asc.env,同記帳 app)上傳 TestFlight。
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE=../.env.prod
[ -f "$ENV_FILE" ] || { echo "找不到 $ENV_FILE" >&2; exit 1; }
PROD_URL=$(grep '^SUPABASE_URL=' "$ENV_FILE" | cut -d= -f2-)
PROD_ANON_KEY=$(grep '^SUPABASE_ANON_KEY=' "$ENV_FILE" | cut -d= -f2-)
PROD_REF=$(grep '^SUPABASE_PROJECT_REF=' "$ENV_FILE" | cut -d= -f2-)
[ -n "$PROD_URL" ] && [ -n "$PROD_ANON_KEY" ] && [ -n "$PROD_REF" ] \
  || { echo ".env.prod 缺 SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_PROJECT_REF" >&2; exit 1; }
case "$PROD_URL" in *"$PROD_REF"*) ;; *) echo "SUPABASE_URL 與 PROJECT_REF 不一致" >&2; exit 1;; esac

UPLOAD=0
if [ "${1:-}" = "--upload" ]; then UPLOAD=1; shift; fi
ASC_ENV=~/mike/asc/asc.env
if [ "$UPLOAD" = 1 ]; then
  [ -f "$ASC_ENV" ] || { echo "找不到 $ASC_ENV" >&2; exit 1; }
  # build 號 +1(App Store Connect 不收重複的 CFBundleVersion)。
  CUR=$(grep '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+).*/\1/')
  NEXT=$((CUR + 1))
  sed -i '' -E "s/^(version: [0-9.]+)\+[0-9]+/\1+$NEXT/" pubspec.yaml
  echo "build 號 $CUR → $NEXT"
fi

DEV_REF=imudkbxvkefzafptqhae
STAMP=$(date +%m%d-%H%M)

flutter build ipa --release \
  --dart-define=SUPABASE_URL="$PROD_URL" \
  --dart-define=SUPABASE_ANON_KEY="$PROD_ANON_KEY" \
  --dart-define=BUILD_STAMP="ios-$STAMP" \
  "$@"

# 產物閘:Generated.xcconfig 的 DART_DEFINES 必須帶 prod ref、不得出現 dev ref。
DEFINES=$(grep '^DART_DEFINES=' ios/Flutter/Generated.xcconfig | cut -d= -f2- | tr ',' '\n' \
  | while read -r d; do printf '%s' "$d" | base64 -D; echo; done)
echo "$DEFINES" | grep -q "$PROD_REF" || { echo "產物檢查失敗:DART_DEFINES 沒有 prod ref" >&2; exit 1; }
if echo "$DEFINES" | grep -q "$DEV_REF"; then echo "產物檢查失敗:DART_DEFINES 含 dev ref" >&2; exit 1; fi
echo "BUILD_STAMP=ios-$STAMP  連線目標:$PROD_REF (workout-prod)"

if [ "$UPLOAD" = 1 ]; then
  set -a; . "$ASC_ENV"; set +a
  IPA=$(ls build/ios/ipa/*.ipa | head -1)
  xcrun altool --upload-app --type ios -f "$IPA" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "已上傳 TestFlight:$(grep '^version:' pubspec.yaml | cut -d' ' -f2)(記得 commit pubspec.yaml 的 build 號)"
fi
