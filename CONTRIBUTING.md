# Contributing

Thanks for helping improve VR Pinball Launcher. This maintained fork accepts
issues and pull requests at [dayelostraco/vr-pinball-launcher](https://github.com/dayelostraco/vr-pinball-launcher).
Original upstream work is credited to keithbphillips; fixes for this fork should
be reported here so they match the current implementation.

## Get a working checkout

1. Fork and clone the repository on Windows x64. Use a branch for your change.
2. Install Unity Hub and the exact editor in `ProjectSettings/ProjectVersion.txt`
   (currently **6000.6.2f1**), including Windows build support. Activate your own
   Unity license through Hub. Open the project once to restore its pinned packages.
3. The project already configures OpenXR and input packages. Keep the checked-in
   XR settings; do not add the Oculus plugin or switch runtimes just to build.
4. The root `launcher-config.json` is a sample. Copy it to your own build and
   select your paths through setup. Never deploy it over an existing user's file.
5. Run checks below, then build with `build.ps1 -SkipInstaller`. Inno Setup 6 is
   required only when packaging an installer. Hardware is needed for gameplay
   validation, but not for the isolated tests.

## Checks

From Windows PowerShell 5.1 in the repository root, with the launcher/VPX closed:

```powershell
.\tools\check-source.ps1
.\tools\test-installation-contract.ps1
.\tools\test-setup.ps1
.\tools\test-backup.ps1
.\tools\test-setup-ui.ps1
.\test.ps1
python -m pip install -r requirements-dev.txt
python -m pytest tools/tests -q -p no:cacheprovider
```

`test.ps1 -Filter TableReadinessTests` runs a Unity subset. Core and backup tests
use temporary fixtures. The GUI test needs an interactive Windows desktop and
closes its own form. The optional real-player check, after building, is:

```powershell
.\tools\test-runtime.ps1
```

Read [the runtime test procedure](docs/testing.md) first: it launches a copied
player and a dummy process, temporarily isolates shared player history, and
restores it afterward. It never launches real tables. Headset/VPX tests remain a
separate manual step. See [architecture](docs/architecture.md) to find the right
component to change.

Hosted CI runs source checks, setup/backup/contract tests and Python tests. It
does not certify VR compatibility. Unity tests can be dispatched manually on a
trusted, licensed Windows runner labelled `unity`; this repository does not
automatically execute pull-request code on a maintainer's PC.

## Style and scope

- C#: four-space indentation, focused classes, descriptive names. Keep domain
  behavior in Core and Windows/Unity integration in the main assembly.
- PowerShell: Windows PowerShell 5.1 compatible; one operation per line in
  transaction and UI code. Backup, path, core setup and UI files have distinct
  responsibilities. Optional formatter: install PSScriptAnalyzer **1.25.0** and
  run `tools/format-setup.ps1`; `-Check` verifies formatting.
- If changing launch/path rules, update the shared contract fixture and test
  both implementations. Add tests for observable behavior and meaningful failure
  paths, rather than implementation details.
- Never commit tables, ROMs, personal configuration, backups, community media,
  generated capture frames/videos, credentials or Unity-generated build folders.
  Keep `.meta` files alongside Unity source/assets.
- Keep support docs and control hints current with behavior. Describe remaining
  manual checks honestly; initialization is not verified gameplay.

## Pull requests

The optional Mac/Linux `tools/remote.sh` helper needs `VRL_REMOTE_HOST`,
`VRL_REMOTE_REPO` (Windows path) and `VRL_REMOTE_SCP_REPO` (forward-slash path).
`VRL_REMOTE_GIT_URL` defaults to your checkout's origin. It synchronizes a branch
to your own trusted Windows SSH host; local Windows checks need none of these.

Explain the concrete problem, resulting behavior, and checks performed. Include
screenshots for visible changes and list hardware/runtime versions for physical
tests. Separate unrelated cleanup from behavioral changes where practical. You
do not need a headset to contribute parser, test, documentation or setup fixes.

For bugs, use the issue form and attach relevant log excerpts. Remove personal
paths if desired; never attach ROMs or commercial table content. Small fixes can
go straight to a pull request; discuss larger changes in an issue first.

Contributions are made under the project's [MIT license](LICENSE). Retain
existing copyright and third-party notices. See [release instructions](docs/releasing.md)
for packaging and validation; direct deployment is a maintainer operation.
