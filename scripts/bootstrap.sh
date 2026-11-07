#!/usr/bin/env bash
# Mac'te Xcode projesini üretir ve açar.
# Kullanım:  ./scripts/bootstrap.sh [TEAM_ID]
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen bulunamadı, Homebrew ile kuruluyor…"
  brew install xcodegen
fi

if [[ $# -ge 1 ]]; then
  # project.yml içindeki DEVELOPMENT_TEAM değerini ayarla
  sed -i '' -E "s/(DEVELOPMENT_TEAM: ).*/\1\"$1\"/" project.yml
  echo "DEVELOPMENT_TEAM = $1"
fi

xcodegen generate
open SesliYaz.xcodeproj
