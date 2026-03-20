# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2026-03-20

- feat: add Developer Mode toggle to gate plugin development UI (#34)

## [0.4.2] - 2026-03-20

- fix: use posix_spawn with POSIX_SPAWN_SETSID for reliable app relaunch (#32)

## [0.4.1] - 2026-03-20

- fix: replace system alert with inline confirmation to fix border clipping (#30)
- fix: use IOBluetooth framework for Bluetooth device detection (#29)

## [0.4.0] - 2026-03-20

- feat: allow plugins to specify settings sheet size (#27)

## [0.3.5] - 2026-03-19

- Revert "chore: release v0.3.5" (#25)
- fix(ci): make update-homebrew idempotent on retry
- fix(ci): add --head flag to gh pr create in update-homebrew
- feat: hide status bar when fullscreen app is active (#23)
- ci: trigger Homebrew update on release PR merge instead of release job
- docs: add demo video to README

## [0.3.4] - 2026-03-19

- fix: app not relaunching after update (#21)
- ci: add reviewer to release PR

## [0.3.3] - 2026-03-19

- Bump github.com/jpsim/yams from 5.4.0 to 6.2.1 (#18)
- fix: prevent duplicate app instances on login (#13)
- fix: limit release notes to changes since previous tag
- Bump github.com/hytfjwr/statusbarkit from 1.0.0 to 1.0.1 (#19)
- Bump actions/checkout from 4 to 6 (#17)
- ci: add Dependabot configuration (#16)

## [0.3.2] - 2026-03-19

- fix: resolve awk newline-in-string error in CHANGELOG generation (#14)
- ci: populate CHANGELOG with commit messages during release (#12)
- feat: in-app update via Homebrew with progress UI (#11)

## [0.3.1] - 2026-03-18

## [0.3.0] - 2026-03-18
