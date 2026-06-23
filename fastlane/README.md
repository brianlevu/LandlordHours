fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to App Store Connect (TestFlight)

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and upload to App Store Connect without submitting for review

### ios submit_review

```sh
[bundle exec] fastlane ios submit_review
```

Submit the prepared App Store version for review

### ios upload_binary_only

```sh
[bundle exec] fastlane ios upload_binary_only
```

Upload the latest exported IPA to App Store Connect without changing metadata or screenshots

### ios update_screenshots

```sh
[bundle exec] fastlane ios update_screenshots
```

Update App Store screenshots for the prepared version without uploading a binary

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
