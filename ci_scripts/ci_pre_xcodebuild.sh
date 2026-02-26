#!/bin/sh

# ci_pre_xcodebuild.sh
# Runs before xcodebuild executes.
# Use this for build preparation steps.

set -e

echo "=== Pre-xcodebuild script started ==="
echo "CI_PRODUCT: $CI_PRODUCT"
echo "CI_XCODEBUILD_ACTION: $CI_XCODEBUILD_ACTION"

# Add any pre-build steps here (e.g., code generation, environment setup)

echo "=== Pre-xcodebuild script completed ==="
