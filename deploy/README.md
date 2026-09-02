# Karaoke kiosk deployment

This machine has a dedicated `karaoke` Linux user account that runs a raw
build of this fork directly (not the flatpak), for kiosk-style use.

- `/home/karaoke/usdx-build/` holds a copy of this repo's `game/` output.
  It is *not* built there - it's synced in from this checkout.
- `/home/karaoke/.local/share/applications/ultrastar-karaoke.desktop` is
  the desktop shortcut that launches it, using the icon at
  `/home/karaoke/.local/share/icons/hicolor/256x256/apps/ultrastar-karaoke.png`.

Neither of those lives under git-tracked build output, and the shortcut's
original source files (previously staged in `/tmp`) were lost on reboot -
hence checking the source of truth into this `deploy/` folder instead.

## Redeploying after a build

After building this fork (so `game/` is current), run:

```
./deploy/deploy-karaoke.sh
```

This rsyncs `game/` into `/home/karaoke/usdx-build/` (leaving `karaoke`'s own
songs, config.ini, Ultrastar.db, avatars, covers, screenshots and playlists
untouched) and (re)installs the desktop shortcut and icon. Needs sudo.

## Launching automatically on login (kiosk autostart)

To have the game launch itself as soon as the `karaoke` user logs in (XDG
autostart - what GNOME's "Startup Applications" tool manages), run:

```
./deploy/deploy-karaoke.sh --autostart
```

This drops the same `ultrastar-karaoke.desktop` into
`/home/karaoke/.config/autostart/`. To turn it back off:

```
./deploy/deploy-karaoke.sh --no-autostart
```

Autostart isn't touched by a plain `./deploy-karaoke.sh` run - it's opt-in/out
explicitly so a routine redeploy never silently changes login behavior.

## Notes

- `ultrastar-karaoke.desktop` was verified word-for-word against the live
  deployed copy (`sudo cat /home/karaoke/.local/share/applications/ultrastar-karaoke.desktop`)
  as of commit `52d600f8` - treat this file as the source of truth going
  forward and keep it in sync if the live one is ever edited directly.
- `ultrastar-karaoke.png` here is a copy of `icons/ultrastardx-icon_256.png`
  from this repo, not verified against whatever icon is currently live on
  the machine (cosmetic only).
- One-time bootstrap steps that are *not* part of this script (already done,
  shouldn't need repeating unless `karaoke`'s config.ini is reset):
  `SongDir1=/home/karaoke/.var/app/eu.usdx.UltraStarDeluxe/.ultrastardx/songs`
  and `LyricsFont=Helvetica` in `/home/karaoke/usdx-build/config.ini`.
