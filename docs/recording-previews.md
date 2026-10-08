# Recording VPX menu previews

Use `tools/fetch_media.py` first. When community table videos are unavailable,
`tools/record_previews.py` records a silent attract-mode MP4 from an installed
table and can install it in VR Pinball Launcher and ES-DE.

Requirements: VPX with `-CaptureAttract`, Python 3, and FFmpeg with QOI decoding
and the libx264 encoder. No Pillow dependency. Run with VPX closed; tables must
already have working scripts, ROMs, PuP packs and display layouts.

PowerShell example on the PC:

```powershell
python tools/record_previews.py `
  'D:\Visual Pinball\Tables\Blood Machines (Original 2022).vpx' `
  --vpx-executable 'D:\Visual Pinball\VPinballX_BGFX64.exe' `
  --ini "$env:APPDATA\VPinballX\10.8\VPinballX.ini" `
  --work-dir 'D:\Visual Pinball\Staging\previews' `
  --launcher-media-root "$env:LOCALAPPDATA\Programs\VR Pinball Launcher\Media\Tables"
```

Pass several table paths to record sequentially. Defaults: 120 frames at 10 FPS,
12 seconds, 1280 pixels wide, H.264/yuv420p with fast-start metadata. Use
`--dry-run` to inspect paths; `--force` replaces only explicitly requested videos.
Existing media is preserved by default.

For ES-DE, `--esde-video-dir /path/to/downloaded_media/vpinball/videos` writes
`<table basename>.mp4`. You can also copy a PC-generated MP4 to the Ally's
`~/Games/VisualPinball/config/ES-DE/downloaded_media/vpinball/videos/` using SCP.
The same video is usable in both frontends. Restart ES-DE to refresh its media.

The script copies the supplied global INI into its work directory and sets
`[PlayerVR] AskToTurnOn = 2` for desktop capture. Live VR configuration stays
intact. VPX still loads each table's own INI. Capture frames remain in the table's
`Capture` directory; the script does not delete files there. Fresh frame checks
prevent reuse of an incomplete or stale capture. A timeout terminates only the
process launched by the recorder.

FFmpeg reads VPX's QOI frames directly. Converting 5120x2160 QOI captures through
Pillow and a PNG sequence is unnecessarily slow. Do not remove frame checks or
switch to PNG intermediates when extending the tool.

These are menu previews, not gameplay tests or headset layout verification.
Inspect VPX's runtime log and review the video before calling a table healthy.
The tool currently requires the sequential `Playfield_00001_tmp.qoi` capture
format used by VPX 10.8.1 rev5436; other formats need an explicit adaptation.
