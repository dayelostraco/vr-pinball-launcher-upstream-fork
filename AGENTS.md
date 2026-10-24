# Agent notes

For VPX launcher media, read `docs/recording-previews.md`. Use
`tools/fetch_media.py` to fetch community artwork and videos, then
`tools/record_previews.py` for missing table videos. Preserve existing media
unless the user requests replacement. Never commit tables, ROMs, PuP packs,
generated capture frames, or generated videos.

The installed launcher's configuration is authoritative. The repository's
`launcher-config.json` may be stale; do not deploy it over the installed one.

Deploy the complete matching Unity player using `build.ps1 -Deploy` (with a
backup of the installed runtime). Never deploy only `Assembly-CSharp.dll`:
runtime code also lives in `VRLauncher.Arcade.dll` and `VRLauncher.Core.dll`.
Partial deployment causes startup MissingMethodException errors. After deployment,
verify installed assembly hashes and launch the installed player, then inspect
Player.log for startup exceptions. EditMode tests and editor previews do not
validate the installed runtime.
