#!/bin/sh

# ci_post_clone.sh
# Runs after Xcode Cloud clones the repository.
# Use this for any setup steps needed before building.

set -e

echo "--- Post Clone Script ---"
echo "Build number: $CI_BUILD_NUMBER"
echo "Branch: $CI_BRANCH"
echo "Commit: $CI_COMMIT"

# If using XcodeGen, generate the project file
if command -v xcodegen &> /dev/null; then
    echo "Running XcodeGen..."
    xcodegen generate
elif [ -f "project.yml" ]; then
    echo "project.yml found but XcodeGen not installed. Installing via Homebrew..."
    brew install xcodegen
    xcodegen generate
fi

echo "--- Post Clone Complete ---"
