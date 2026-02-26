#!/bin/sh

# ci_post_clone.sh
# Runs after Xcode Cloud clones the repository.
# Use this for any setup that needs to happen before the build.

set -e

echo "=== Post-clone script started ==="
echo "CI_WORKSPACE: $CI_WORKSPACE"
echo "CI_BRANCH: $CI_BRANCH"
echo "CI_BUILD_NUMBER: $CI_BUILD_NUMBER"

# If you add SPM dependencies in the future, they'll resolve automatically.
# Add any additional post-clone setup here if needed.

echo "=== Post-clone script completed ==="
