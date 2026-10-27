#!/bin/bash
# Generates HealthDashboard.xcodeproj from project.yml and opens it.
set -e
cd "$(dirname "$0")"
if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Install Homebrew first (https://brew.sh), then run this again." >&2
    exit 1
  fi
  brew install xcodegen
fi
xcodegen generate
open HealthDashboard.xcodeproj
