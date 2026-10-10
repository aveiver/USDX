# Phone song queue

Guests on the same Wi-Fi open a web page on their phone, search the song
list and queue songs. The game shows the next song on the singing screen,
and after a song (results shown for a moment) the next queued song starts
by itself.

## Running it

`deploy/launch-ui-v2.sh` (what the "Karaoke (new look)" shortcut runs)
starts the queue server in the background and then the game. To run the
server by hand instead:

```
python3 remote/karaoke_remote.py            # port 8080, files in game/remote
python3 remote/karaoke_remote.py --port 9000
```

Python 3 standard library only - nothing to install.

### A nicer address

- **No port number:** the server uses port 80 when the system allows it,
  otherwise 8080. To allow it once (Ubuntu):
  `echo net.ipv4.ip_unprivileged_port_start=80 | sudo tee /etc/sysctl.d/99-karaoke.conf && sudo sysctl --system`
- **A name instead of an IP:** give the PC a fixed IP and a local DNS name on
  the router (e.g. `karaoke.home`), then put that name in
  `game/remote/public-url.txt` - the TV and its QR code show it instead.

The address (and a QR code for it) appears on the game's main menu and at
the bottom of the song list. Guests open it and tap a song's + to queue it.

## Host PIN

Guests can remove only their own songs. The host PIN (printed when the
server starts, stored in `game/remote/pin.txt` - edit the file and restart
the server to change it) unlocks removing and reordering anyone's songs.
Tap "Host controls" at the bottom of the page.

## How it starts songs

- On the song list, a banner shows the next queued song and starts it after
  10 seconds without anyone touching the keyboard or mouse (click the banner
  to start straight away).
- On the results screen it counts down 12 seconds, then starts the next
  song. Enter starts it now, Esc stays on the results.
- The players and scoring setting from the last song are kept.

## Files (game/remote)

| file | written by | what |
| --- | --- | --- |
| songs.tsv | game | song list: key, title, artist, year, duet, cover path |
| nowplaying.txt | game | what's being sung and how far in |
| claims/&lt;id&gt; | game | "I started this one" - the server drops it from the queue |
| queue.txt | server | the queue, in order |
| url.txt, qr.txt | server | address for the TV and its QR code |
| pin.txt | server | host PIN |
