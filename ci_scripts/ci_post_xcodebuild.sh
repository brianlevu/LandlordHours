#!/bin/sh

# ci_post_xcodebuild.sh
# Runs after each xcodebuild action completes.
# Use this for post-build tasks like uploading symbols, notifications, etc.

set -e

echo "--- Post Xcodebuild Script ---"
echo "Xcode build exit code: $CI_XCODEBUILD_EXIT_CODE"

if [ "$CI_XCODEBUILD_EXIT_CODE" -eq 0 ]; then
    echo "Build succeeded!"
else
    echo "Build failed with exit code: $CI_XCODEBUILD_EXIT_CODE"
fi

echo "--- Post Xcodebuild Complete ---"
