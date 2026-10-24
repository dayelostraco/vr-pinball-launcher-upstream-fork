# Artwork and previews

## Table and Media Naming

Wheel art is matched to tables by filename. The launcher is tolerant of the
decoration that table files usually carry, but naming tables to the community
standard gives the most reliable results and keeps other pinball frontends
happy at the same time.

### The standard

Name every table, and its media, as:

```
Title (Manufacturer Year).ext
```

For example:

```
Attack from Mars (Bally 1995).vpx
Attack from Mars (Bally 1995).ini            <- VPX per-table settings
Media\Wheel\Attack from Mars (Bally 1995).png
```

This is the same convention used by PinballX, PinUP Popper and PinballY, and
by the community wheel packs, so a table named this way picks up its art
automatically everywhere.

Rules:

- **Title** as it appears on the playfield, no leading article juggling.
- **Manufacturer** and four-digit **Year** in a single parenthesised group.
- **Drop author, version and VR-room decoration** — no `VPW v1.0.1`, no
  `g5k VR 1.3.1`, no leading `VR ROOM`.
- Use **spaces, not underscores**.

### Renaming an existing table

Three things share a table's basename, and all must be renamed together:

| What | Example |
|---|---|
| The table | `Attack from Mars (Bally 1995).vpx` |
| VPX per-table settings | `Attack from Mars (Bally 1995).ini` |
| VPX texture cache | `Tables\cache\Attack from Mars (Bally 1995)\` |

Renaming the `.vpx` alone orphans the other two. The cache folder is
regenerated automatically, but the `.ini` holds your per-table settings and is
not.

High scores are safe either way: VPX stores them in `Tables\user\VPReg.stg`
keyed by the table's internal script name, not by its filename.

The trade-off is that the version is no longer visible in the filename. If you
track which build of a table you have, record it somewhere else — the per-table
`.ini` is a convenient place.

### How matching actually works

`WheelIndex` (used by `TableCatalog`) tries three tiers in order and stops at the
first hit, so a correctly named table matches on tier 1:

1. **exact** — basenames equal, ignoring case.
2. **normalized** — underscores become spaces, parentheses are dropped,
   whitespace is collapsed, and a leading `VR ROOM` is removed.
3. **title+year** — everything after the `(Manufacturer Year)` group is
   discarded. Where a name has no parentheses, the last four-digit year token
   is used as the cut point instead, so titles that *begin* with a year (such
   as `2001 (Gottlieb 1971)`) survive intact.

Where several images reduce to the same key, the least decorated filename
wins, so `Twilight Zone (Bally 1993).png` is preferred over
`Twilight Zone (Bally 1993) BW.png`.

Tiers 2 and 3 mean an unrenamed table still finds its art — a table called
`Star_Trek_The_Next_Generation_Williams_1993_VPW_Mod_v1.1.vpx` matches
`Star Trek The Next Generation (Williams 1993).png`. Renaming is a
convenience, not a requirement.

### When art doesn't appear

A table with no match falls back to a solid placeholder colour. Every miss is
logged with the keys that were tried, so check the player log:

```
%USERPROFILE%\AppData\LocalLow\DefaultCompany\vr-launch\Player.log
```

Look for `Matched wheel image for ...` on success, or
`No wheel image for '<table>' (tried exact, normalized '...', title+year '...')`
on failure. Compare the reported keys against your actual filenames.


## Fetching Table Media

`tools/fetch_media.py` downloads per-table wheel, playfield, backglass and
table video art from VPinMediaDB into `Media\Tables\<Table Name>\`, matching
each table to a VPS id from the Virtual Pinball Spreadsheet. Run it with:

```
uv run tools/fetch_media.py
```

By default it reads `tablesDirectory` from the installed launcher's
`launcher-config.json`; pass `--config` to point at another one. Other flags:

- `--dry-run`: report what would be fetched without downloading anything.
- `--force "<Table Name>"`: re-download that one table's media even if files
  already exist. Repeatable for more than one table.

For a table whose filename doesn't match a VPS entry, add it to
`tools/media-overrides.json` (`{"Table Name (Manufacturer Year)": "<VPS
id>"}`).

The script never overwrites an existing file unless `--force` names that
table, and it never downloads ROMs.

For missing table videos, use `tools/record_previews.py` to record silent VPX
attract previews for this launcher and ES-DE. See
[Recording previews](recording-previews.md) for setup and examples.


For recording missing previews, see [recording-previews.md](recording-previews.md).
