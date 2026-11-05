# Releasing SweatKit

Run from any directory with `./release.sh` (using the script's path). This follows
the neighboring projects' package/archive/upload/tag workflow, using Simlock for
simulator ownership. There is no Flightdeck dependency.

## Setup

- Install Xcode, XcodeGen, Python 3 and Simlock; `simlock whoami` must succeed.
  Read `simlock instructions` and inspect `simlock catalog` before selecting a
  model. The smoke check uses the local Simlock service, with no runtime downloads.
- Create the SweatKit app in App Store Connect for
  `com.arjunakankipati.sweatkit`. Enable HealthKit for its App ID.
- Sign in to Xcode with the development team in `project.yml`, or copy
  `.release.env.example` to `.release.env` and configure an App Store Connect API
  key plus a local Apple Distribution certificate/private key. The profile helper
  inherited from Harbor installs an App Store profile for that certificate.
  `RELEASE_ENV_FILE` can select a shared env file; it is sourced as shell code.
- Commit the source to release. Change `MARKETING_VERSION` in `project.yml` when
  starting a new version. Build numbers default to UTC day/hour/minute components;
  use `--build` for another release in the same minute.

## Commands

```sh
./release.sh                         # package tests, smoke check, archive, upload, local tag
./release.sh --no-upload             # same checks, archive and export IPA, no upload/tag
./release.sh --build 42              # explicit build number
./release.sh --skip-tests            # skip both package tests and simulator smoke check
./release.sh --no-upload --allow-dirty # package current work without tagging
```

The checks run every package's existing Swift tests, build the Release app for a
generic iOS simulator, then install and launch it on a Simlock-leased phone. The
generic build works with Simlock's private device sets on older Xcode versions.
The background lease renews throughout device use and is released on success,
failure or interruption. A lost lease stops the smoke check. Existing leases are
never stolen or released; a conflicting lease causes the command to fail.

SweatKit has no app/UI test target yet. Install/launch success does not verify
Health permissions, device behavior, or UI acceptance. Run those checks separately.

Archives, dSYMs, export options, build logs and exported IPAs are kept under
`build/release/<version>-<build>/`. Existing output directories are rejected to
avoid overwriting evidence. A clean uploaded release gets a local
`ios/v<version>-<build>` tag; tags are never pushed automatically. Dirty releases
require `--allow-dirty` and never get tagged. `--no-upload` still performs signing
and may contact Apple's provisioning services.
