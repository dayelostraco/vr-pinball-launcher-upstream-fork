# Changelog

## 1.1.0 — 2026-10-24

First packaged release of this maintained fork. Includes work developed before
this release; earlier fork commits were distributed as local builds.

- Arcade-room selection with favorites, recent sessions, play counts, remembered
  browsing, letter jumps, Surprise Me and grouped control hints.
- Table details with launch-profile/file checks, detectable requirements and
  persisted launch results. Initialization remains distinct from gameplay checks.
- Desktop setup from F2 or Start menu: actual VPX/helper paths, health report,
  table tests, reviewed changes, safety backups and rollback.
- ZIP export/restore for settings and history, with integrity checks, destination
  review and an option to retain this PC's paths/profiles.
- Launch recovery, process-tree rescue and the optional background-input/focus
  helper. Existing installed configuration is preserved.
- Matching setup/runtime relative-path and ROM-library rules, checked against
  shared installation-contract cases. Unknown helpers remain unverified.
- Per-user installer, current OpenXR quick start, contributor/architecture/test
  guides, CI, portable runtime harness, license and dependency notices.

Known limits: Windows x64 release; no launcher port for Ally/Linux; embedded or
dynamic table-script requirements are not automatically scanned. Other headset,
runtime and VPX combinations need physical validation. Installer is unsigned.

## Earlier development

Original launcher by keithbphillips, starting in 2025. See Git history for the
original project and subsequent fork development.
