#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

# Build MoonBit JS target
moon build --target js

# Copy the JS bundle to package dir
cp _build/js/debug/build/js/http/http.js js/pkg/mcpx.js

echo "✅ built js/pkg/mcpx.js"
