#!/bin/sh

# ci_post_xcodebuild.sh
# Runs after xcodebuild completes.
# Use this for post-build tasks like uploading dSYMs, notifying services, etc.

set -e

echo "=== Post-xcodebuild script started ==="
echo "CI_PRODUCT: $CI_PRODUCT"
echo "CI_XCODEBUILD_EXIT_CODE: $CI_XCODEBUILD_EXIT_CODE"
echo "CI_ARCHIVE_PATH: $CI_ARCHIVE_PATH"

if [ "$CI_XCODEBUILD_EXIT_CODE" -eq 0 ]; then
    echo "Build succeeded!"
else
    echo "Build failed with exit code: $CI_XCODEBUILD_EXIT_CODE"
fi

echo "=== Post-xcodebuild script completed ==="
