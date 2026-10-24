# Testing and compatibility

Automated tests cover isolated behavior. Runtime smoke tests exercise the built
player and dummy processes. Physical headset/controller/gameplay tests remain
separate; a green CI result does not establish them.

## Automated checks

See [CONTRIBUTING](../CONTRIBUTING.md) for commands. Source checks parse every
tracked PowerShell script, validate JSON and local documentation links. Setup
tests use temporary directories, including failure/rollback cases. Contract
tests verify the same profile/path cases in PowerShell and C#. Python media
tests mock network responses and do not download artwork.

Unity EditMode tests run through `test.ps1`; results are `Logs/editmode-results.xml`
and `Logs/unity-tests.log`. These tests do not cover a real headset or VPX.

## Built-player smoke test

Build first with `build.ps1 -SkipInstaller`, close the installed launcher and
VPX, then run `tools/test-runtime.ps1` on an interactive Windows desktop.
It copies the complete runtime to a unique temporary directory, creates a dummy
table and program, and checks nonzero exit recovery, retry, process-start errors,
missing executable handling, launch-result persistence and unchanged play counts.
It also checks that F2 opens/closes desktop setup without changing configuration.

The player uses a shared persistent-data location, so the harness snapshots the
existing state, temporarily uses an isolated test state, closes its own player
and restores original bytes in `finally`. Do not launch another player during
the check. On interruption by machine shutdown, restore `state-before.json`
from the printed test directory to the player-state location below. If no
original existed, remove the test-created state instead. No real table or ROM
is launched; test artifacts remain available for diagnosis.

## Physical release checklist

- Existing install: export a backup, upgrade, verify paths/profiles/history.
- New install on another user account or PC: follow the quick start without
  relying on a maintainer's existing configuration.
- Headset: navigation, tracking, recentering, view changes, details, handoff to
  VPX, normal return and emergency recovery.
- Inputs: keyboard, physical cabinet controls and any enabled motion-controller
  bridge. Verify the focused window; physical PinOne buttons are distinct from
  the controller's X button and the keyboard X key.
- Gameplay: coins, start, flippers, plunger, scoring, comfortable audio and DMD
  artwork. A `Startup done` line is only initialization evidence.
- Restore: review a backup in a temporary installation before replacing live
  state; test a cross-PC path review.

## Compatibility evidence

| Environment | Evidence / limits |
|---|---|
| Windows 11 x64 development PC, Unity 6000.6.2f1 | Player builds, EditMode, setup/backup and copied-player recovery checks run here |
| VPX BGFX 10.8.1 rev 5436 | Existing-install field use; PinOne background-input/focus helper tested with Medieval Madness. Recheck each VPX update. |
| OpenXR headset/runtime | Required for VR. This PC has field use, but no comprehensive per-headset/runtime certification matrix; unattended smoke tests can run while the headset is unavailable. |
| Meta/Oculus Touch external bridge | Optional Oculus-runtime-specific bridge; upstream and local mappings documented. Not a generic bridge for every OpenXR controller. |
| Other Windows/VPX/headset combinations | Unverified until someone reports the exact versions and manual checks |
| Ally/Linux | VPX table installation work is separate; this Windows Unity launcher/setup release is not an Ally/Linux port |

The Windows version row records this development machine, not a promise that
all Windows 11 systems have been tested. Add reproducible reports to the matrix
as evidence arrives, rather than broadening support claims from automated counts.

## Logs and state

| File | Location |
|---|---|
| Launcher log | `%USERPROFILE%\AppData\LocalLow\DefaultCompany\vr-launch\Player.log` |
| Favorites/history/results | Same directory, `state.json` |
| Default monitored VPX log | `%APPDATA%\VPinballX\10.8\vpinball.log` |
| Optional focus helper log | `VpxBackgroundInput.log` beside that helper |
| Setup safety backups | `SetupBackups` beside `vr-launch.exe` |

Alternate VPX log locations remain unconfirmed by default monitoring. Include
version details, profile and log excerpts when reporting a failure; do not attach
ROMs, tables, credentials or personal backup archives to public issues.
