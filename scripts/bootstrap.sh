#!/usr/bin/env bash
# Generates the Xcode project on a Mac and opens it.
# Usage:  ./scripts/bootstrap.sh [TEAM_ID]
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen not found, installing with Homebrew…"
  brew install xcodegen
fi

if [[ $# -ge 1 ]]; then
  # Set DEVELOPMENT_TEAM in project.yml
  sed -i '' -E "s/(DEVELOPMENT_TEAM: ).*/\1\"$1\"/" project.yml
  echo "DEVELOPMENT_TEAM = $1"
fi

xcodegen generate
open SesliYaz.xcodeproj
