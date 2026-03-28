# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.14.1] - 2026-03-28

- chore: add pre-commit hooks and unify SwiftLint to SPM plugin (#93)
- feat: replace system notifications with toast alerts (#92)
- feat: show toast notification on config reload (#91)

## [0.14.0] - 2026-03-28

- feat: toast notification system (#88)
- feat: smooth widget visibility transitions (#87)

## [0.13.1] - 2026-03-27

- feat: enrich EventBus with 23 events, wildcard subscriptions, and rate limiting (#85)

## [0.13.0] - 2026-03-27

- feat: next-event countdown and numeric text animation (#83)

## [0.12.0] - 2026-03-27

- refactor: migrate to string-based IPC event protocol (#81)

## [0.11.2] - 2026-03-27

- fix: preserve plugin order on update (#79)
- fix: preserve plugin order on update (#78)

## [0.11.1] - 2026-03-27

- feat: show update availability indicators in UI (#76)

## [0.11.0] - 2026-03-26

- feat: add trigger event support (sbar trigger) (#74)

## [0.10.0] - 2026-03-25

- feat: add IPC event subscription system (sbar subscribe) (#72)
- fix: handle expected read failure on sbar reload (#71)

## [0.9.0] - 2026-03-25

- fix: align CLI reload command with Apple Menu behavior (#69)

## [0.8.1] - 2026-03-24

- fix: resolve IPC server crash and sbar CLI SIGSEGV (#67)

## [0.8.0] - 2026-03-24

- feat: add IPC server and sbar CLI for runtime control (#65)

## [0.7.2] - 2026-03-24

- feat: improve error logging for plugin operations (#63)
- feat: improve brew update check logging (#61)

## [0.7.1] - 2026-03-24

- refactor: remove unnecessary swiftlint:disable comments (#59)
- feat: add in-app changelog viewer (#58)
- fix: kill running StatusBar process before launching new instance (#57)

## [0.7.0] - 2026-03-24

- fix: update popup tint when preferences change (#55)
- fix: build .app bundle for debug runs to avoid TCC privacy crash (#54)

## [0.6.1] - 2026-03-23

- fix: use Homebrew Cask commands for update detection and upgrade (#52)

## [0.6.0] - 2026-03-23

- feat: add menu bar auto-hide recommendation to onboarding (#46)
- feat: add display mode switching and threshold color coding for CPU/MEM widgets (#47)

## [0.5.6] - 2026-03-23

## [0.5.5] - 2026-03-23

- fix: migrate Homebrew distribution from Formula to Cask (#48)
- docs: restructure README for better readability (#45)

## [0.5.4] - 2026-03-23

- fix: use /Applications symlink for relaunch instead of Launch Services (#43)

## [0.5.3] - 2026-03-23

- refactor: check for updates via Homebrew instead of GitHub Releases API (#39)

## [0.5.2] - 2026-03-23

- fix: use bundle ID for relaunch to survive brew upgrade path changes (#40)

## [0.5.1] - 2026-03-23

- refactor: defer tag/release creation to after PR merge (#37)
- fix: harden plugin security and fix observer leak (#36)

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
