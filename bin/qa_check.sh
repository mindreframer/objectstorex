#!/bin/bash
set -e

# Change to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== QA Check Script ==="
echo "Running from: $PROJECT_ROOT"
echo ""

echo "Step 1: Running Elixir tests..."
mix test
echo "✓ Elixir tests passed"
echo ""

echo "Step 2: Running Rust tests..."
cd native/objectstorex
cargo test --quiet
cd "$PROJECT_ROOT"
echo "✓ Rust tests passed"
echo ""

echo "Step 3: Running cargo clippy..."
cd native/objectstorex
cargo clippy --quiet
cd "$PROJECT_ROOT"
echo "✓ Clippy passed"
echo ""

echo "Step 4: Checking for compilation warnings..."
mix compile --warnings-as-errors
echo "✓ No compilation warnings"
echo ""

echo "=== All QA checks passed! ==="
