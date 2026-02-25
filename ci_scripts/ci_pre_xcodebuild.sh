#!/bin/sh

# ci_pre_xcodebuild.sh
# Runs before each xcodebuild action (build, test, archive, etc.)

set -e

echo "--- Pre Xcodebuild Script ---"
echo "Xcode Cloud Workflow: $CI_WORKFLOW"
echo "Xcode Cloud Action: $CI_XCODEBUILD_ACTION"
echo "--- Pre Xcodebuild Complete ---"
