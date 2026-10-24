# Existing-installation setup

Open **VR Pinball Launcher Setup** from the Start menu, or press **F2 on the PC
keyboard** while browsing the launcher. A short VR notice appears if the
configured launch program or tables folder is missing, or the config cannot
be read. Setup opens as a separate Windows desktop window.

You can also run it from the launcher folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\tools\setup.ps1
```

## Locations

Choose the **actual VPX executable** and **tables folder**. BGFX and GL builds
are detected in common installation locations, including C: and D:. The actual
VPX path is separate from the program used to launch it:

| Launch choice | Behavior |
|---|---|
| Keep current launch program | Preserves a verified helper and its target. Native VPX paths follow the selected executable. |
| Launch VPX directly | Changes only the default launch program to the selected VPX executable. |
| Use background-input helper | Compiles the bundled helper, writes its target sidecar, and sets the default launcher path to that helper. |

Helper configuration is read from `VpxBackgroundInput.vpx-path.txt`. For older
installed helpers, the adjacent source's hardcoded target can be detected;
that is evidence to review, not proof of what a binary will execute. Unknown
helpers need an explicit target or a deliberate Direct/Helper choice. Setup
does not guess a helper's root directory from the helper's own executable path.

Existing per-table profiles and assignments are preserved. They may use another
VPX version or a shutdown-cleanup host and override the default launch choice.
Media paths, controller bridge settings, and unknown JSON properties survive
setup saves. `realVpinballExecutable` records the actual target independently
of `vpinballExecutable`, which remains the launched program.

## Health

The report covers the launch program, actual VPX version, tables and artwork directories,
candidate/active INI, VR mode, ROM library, native PinMAME/Serum/ScoreView/
FlexDMD/PuP/B2S plugins, legacy VPinMAME/FlexDMD files, external DMD configuration,
and existing launch profiles.

- **Found** means a file or location was detected. It does not prove a table works.
- **Missing** identifies a required launch-program, VPX, or tables-location problem.
- **Needs testing** covers uncertain INI selection, optional components, and
  hardware or table behavior that cannot be inferred from files.

Native plugins and legacy COM add-ons are separate. An installed native FlexDMD
plugin does not establish that legacy FlexDMD COM registration works. ROM ZIP
contents, table requirements, missing fonts, and custom display wiring are not
automatically audited. Global plugin disable flags are shown; per-table INIs
may intentionally override them.

INI detection considers portable settings and both versioned
`%APPDATA%\VPinballX\10.8` and older settings locations. Only the latest VPX run
whose **application directory matches the selected executable** confirms an
active INI. An old log for a different install cannot authorize an INI repair.

**Save report** exports the current checks, selected-table test result, and
manual verification checkboxes as JSON. Reports contain local installation paths.
Unchecked manual items mean unverified, not necessarily broken. **Open
configuration** opens the existing JSON in Notepad for advanced troubleshooting.
Malformed configuration is never silently replaced by the setup window.

## Test a table

Close the launcher and other VPX sessions before testing, so the headset is
available. Browse to an existing `.vpx` file and start the test. It uses the
proposed locations and respects that table's existing executable/INI/working-
directory profile. Applying setup is separate; a helper must be installed
before it can be tested.

Fresh lines for the selected table in the default versioned VPX log can confirm
initialization or report a script error. Other log locations may remain
unconfirmed. Initialization does not prove the ROM finished booting, the DMD
uses the correct artwork, or the game can start. Verify controls, audio, scoring,
DMD artwork and VR view yourself, then record those checks. A real table test
can update its normal credits, settings, and NVRAM just like ordinary play.

**Close test table** asks only the test process and its descendants to close
normally; it does not forcibly kill them. A blocking VPX dialog may need manual
attention. Closing setup itself leaves a running table independent.

## Review, apply and undo

The last page lists the exact proposed changes. Apply is explicit and requires
the launcher and VPX to be closed. No downloads or repairs run on opening setup.

The optional **always-on VR** repair changes only `[PlayerVR] AskToTurnOn` in a
log-confirmed active INI. It is unchecked by default. It preserves INI encoding,
line endings, unrelated settings and input mappings. It will not create or guess
an active settings file when the runtime evidence is missing.

Original JSON/INI files and a change summary are saved under
`SetupBackups/<timestamp>` beside the launcher. Config replacement is atomic.
If a later step fails, original config/INI and existing helper files are
restored. Helper rebuilds additionally keep their own timestamped file backups.
If the config changes externally while the window is open, apply stops instead
of overwriting those edits; reopen setup to refresh it.

To undo, close the launcher and copy the original JSON/INI from the backup to
the paths listed in the change summary. If replacing a helper, restore its
matching executable and target sidecar together. Restart the launcher afterward.
No table scripts, ROMs, artwork, per-table overrides, play history or controller
firmware are rewritten by setup. Existing table-local VPX settings remain intact.

This first version focuses on connecting and diagnosing **existing Windows
installations**. It does not install every display system or automatically
reconfigure DMDs. Optional legacy emulator/GL/controller-bridge installation
tasks remain separate, unchecked options in the installer.

## Development checks

```powershell
.\tools\test-setup.ps1
.\tools\test-setup-ui.ps1
.\tools\setup.ps1 -LauncherDirectory "$env:LOCALAPPDATA\Programs\VR Pinball Launcher" -ReportOnly
.\tools\setup.ps1 -LauncherDirectory "$env:LOCALAPPDATA\Programs\VR Pinball Launcher" -PreviewDirectory .\Logs\setup-preview
```

The core tests use generated temporary files, exercise config preservation,
rollback, helper compilation and Windows argument round-trips. Close the
launcher/VPX first. The UI test uses a guarded dummy executable that exits 42;
it does not launch VPX, change live configuration or mark startup successful.
Preview mode renders all four pages and closes without applying changes or
running tables. Unity EditMode tests and complete-player startup checks remain
part of the normal deployment workflow.
