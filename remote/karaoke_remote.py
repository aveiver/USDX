#!/usr/bin/env python3
"""
Karaoke queue - a small web page guests open on their phones (same Wi-Fi)
to queue songs for the UltraStar ui-v2 build.

The game and this server talk through plain files in one folder
(default: ../game/remote next to this script):

  written by the game                 written by this server
  -------------------                 ----------------------
  songs.tsv     the song list         queue.txt   the queue, in order
  nowplaying.txt what's on now        url.txt     address for the TV
  claims/<id>   "I took this one"     qr.txt      QR code of that address
                                      pin.txt     host PIN (created once)

Only the standard library is used. Run:

  python3 karaoke_remote.py [--dir DIR] [--port 8080]
"""

import argparse
import hashlib
import http.cookies
import json
import mimetypes
import os
import secrets
import socket
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qr  # noqa: E402

WEB_DIR = os.path.join(HERE, 'web')
FONT_DIR = os.path.normpath(os.path.join(HERE, '..', 'game', 'fonts', 'Helvetica'))


def atomic_write(path, text):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(text)
    os.replace(tmp, path)


def clean(s):
    # tabs and line breaks would break the line-based files
    return ' '.join(str(s).replace('\t', ' ').split())


class Store:
    """Songs (from the game), the queue (ours) and now playing (from the game)."""

    def __init__(self, folder):
        self.dir = folder
        self.lock = threading.Lock()
        self.songs = []          # list of dicts, sorted by artist then title
        self.by_id = {}
        self.songs_mtime = None
        self.queue = []          # [{qid, id, key, title, artist, guest, added}]
        self.host_tokens = set()
        os.makedirs(os.path.join(folder, 'claims'), exist_ok=True)
        self.pin = self._load_pin()
        self._load_queue()

    # -- files --------------------------------------------------------------

    def path(self, name):
        return os.path.join(self.dir, name)

    def _load_pin(self):
        p = self.path('pin.txt')
        try:
            with open(p, encoding='utf-8') as f:
                pin = f.read().strip()
            if pin:
                return pin
        except OSError:
            pass
        pin = '%04d' % secrets.randbelow(10000)
        atomic_write(p, pin + '\n')
        return pin

    def _load_queue(self):
        # pick up a queue left over from a previous run
        try:
            with open(self.path('queue.txt'), encoding='utf-8') as f:
                for line in f:
                    parts = line.rstrip('\n').split('\t')
                    if len(parts) >= 4:
                        self.queue.append({'qid': parts[0], 'key': parts[1], 'title': parts[2],
                                           'artist': parts[3], 'guest': '', 'added': time.time(),
                                           'id': self._song_id(parts[1])})
        except OSError:
            pass

    def save_queue(self):
        lines = ['%s\t%s\t%s\t%s\n' % (q['qid'], q['key'], clean(q['title']), clean(q['artist']))
                 for q in self.queue]
        atomic_write(self.path('queue.txt'), ''.join(lines))

    @staticmethod
    def _song_id(key):
        return hashlib.sha1(key.encode('utf-8')).hexdigest()[:12]

    def refresh_songs(self):
        p = self.path('songs.tsv')
        try:
            mtime = os.path.getmtime(p)
        except OSError:
            return
        if mtime == self.songs_mtime:
            return
        songs = []
        with open(p, encoding='utf-8', errors='replace') as f:
            for line in f:
                parts = line.rstrip('\n').split('\t')
                if len(parts) < 6:
                    continue
                key, title, artist, year, duet, cover = parts[:6]
                songs.append({'id': self._song_id(key), 'key': key, 'title': title, 'artist': artist,
                              'year': year if year not in ('', '0') else '', 'duet': duet == '1',
                              'cover': cover})
        songs.sort(key=lambda s: (s['artist'].casefold(), s['title'].casefold()))
        with self.lock:
            self.songs = songs
            self.by_id = {s['id']: s for s in songs}
            self.songs_mtime = mtime

    def process_claims(self):
        """The game drops claims/<qid> when it starts a queued song."""
        cdir = self.path('claims')
        try:
            names = os.listdir(cdir)
        except OSError:
            return
        if not names:
            return
        with self.lock:
            before = len(self.queue)
            self.queue = [q for q in self.queue if q['qid'] not in names]
            if len(self.queue) != before:
                self.save_queue()
        for n in names:
            try:
                os.remove(os.path.join(cdir, n))
            except OSError:
                pass

    def now_playing(self):
        info = {}
        try:
            mtime = os.path.getmtime(self.path('nowplaying.txt'))
            with open(self.path('nowplaying.txt'), encoding='utf-8', errors='replace') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.rstrip('\n').split('=', 1)
                        info[k] = v
        except OSError:
            return None
        if info.get('state') != 'playing':
            return None
        # the game writes how far in it was; the file time says when
        try:
            started = mtime - float(info.get('elapsed', '0'))
            duration = float(info.get('duration', '0'))
        except ValueError:
            started, duration = 0, 0
        song = self.by_id.get(self._song_id(info.get('key', '')))
        return {'title': info.get('title', ''), 'artist': info.get('artist', ''),
                'id': song['id'] if song else None,
                'elapsed': max(0, time.time() - started) if started else 0,
                'duration': duration}

    # -- queue operations ---------------------------------------------------

    def add(self, song_id, guest):
        with self.lock:
            song = self.by_id.get(song_id)
            if not song:
                return None, 'That song is not available'
            if any(q['key'] == song['key'] for q in self.queue):
                return None, 'Already in the queue'
            item = {'qid': secrets.token_hex(4), 'id': song['id'], 'key': song['key'],
                    'title': song['title'], 'artist': song['artist'], 'guest': guest,
                    'added': time.time()}
            self.queue.append(item)
            self.save_queue()
            return item, None

    def remove(self, qid, guest, host):
        with self.lock:
            for q in self.queue:
                if q['qid'] == qid:
                    if not host and q['guest'] != guest:
                        return 'Only the host can remove other songs'
                    self.queue.remove(q)
                    self.save_queue()
                    return None
        return 'Not in the queue any more'

    def move(self, qid, delta):
        with self.lock:
            for i, q in enumerate(self.queue):
                if q['qid'] == qid:
                    j = max(0, min(len(self.queue) - 1, i + delta))
                    self.queue.insert(j, self.queue.pop(i))
                    self.save_queue()
                    return None
        return 'Not in the queue any more'


def lan_address():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('10.255.255.255', 1))   # no packet is sent
        return s.getsockname()[0]
    except OSError:
        return '127.0.0.1'
    finally:
        s.close()


def publish_address(store, port):
    """url.txt and qr.txt for the TV; refreshed in case the IP changes."""
    url = 'http://%s:%d' % (lan_address(), port)
    try:
        with open(store.path('url.txt'), encoding='utf-8') as f:
            if f.read().strip() == url:
                return url
    except OSError:
        pass
    matrix = qr.encode(url)
    atomic_write(store.path('qr.txt'), ''.join(''.join(map(str, row)) + '\n' for row in matrix))
    atomic_write(store.path('url.txt'), url + '\n')
    return url


class Handler(BaseHTTPRequestHandler):
    store = None
    server_version = 'KaraokeQueue/1.0'

    def log_message(self, fmt, *args):   # keep the terminal quiet
        pass

    # -- helpers ------------------------------------------------------------

    def cookies(self):
        c = http.cookies.SimpleCookie()
        try:
            c.load(self.headers.get('Cookie', ''))
        except http.cookies.CookieError:
            pass
        return {k: v.value for k, v in c.items()}

    def identity(self):
        c = self.cookies()
        guest = c.get('kq_guest', '')
        new_guest = None
        if len(guest) != 16:
            guest = new_guest = secrets.token_hex(8)
        host = c.get('kq_host', '') in self.store.host_tokens
        return guest, new_guest, host

    def send_json(self, obj, status=200, set_cookies=()):
        body = json.dumps(obj).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        for ck in set_cookies:
            self.send_header('Set-Cookie', ck)
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path, cache=True):
        try:
            with open(path, 'rb') as f:
                data = f.read()
        except OSError:
            self.send_error(404)
            return
        ctype = mimetypes.guess_type(path)[0] or 'application/octet-stream'
        self.send_response(200)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'max-age=86400' if cache else 'no-cache')
        self.end_headers()
        self.wfile.write(data)

    def read_body(self):
        try:
            n = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            n = 0
        if n <= 0 or n > 10000:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode('utf-8'))
        except (ValueError, UnicodeDecodeError):
            return {}

    def guest_cookie(self, new_guest):
        if not new_guest:
            return ()
        return ('kq_guest=%s; Path=/; Max-Age=31536000; SameSite=Lax' % new_guest,)

    # -- routes -------------------------------------------------------------

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        p = url.path
        st = self.store
        if p in ('/', '/index.html'):
            self.send_file(os.path.join(WEB_DIR, 'index.html'), cache=False)
        elif p.startswith('/fonts/'):
            name = os.path.basename(p)
            if name in ('Helvetica.ttf', 'Helvetica-Bold.ttf'):
                self.send_file(os.path.join(FONT_DIR, name))
            else:
                self.send_error(404)
        elif p == '/api/songs':
            st.refresh_songs()
            with st.lock:
                songs = [{'id': s['id'], 'title': s['title'], 'artist': s['artist'], 'year': s['year'],
                          'duet': s['duet'], 'cover': bool(s['cover'])} for s in st.songs]
            self.send_json({'songs': songs})
        elif p.startswith('/api/cover/'):
            song = st.by_id.get(p.rsplit('/', 1)[-1])
            # only cover files the game listed are ever served
            if song and song['cover'] and os.path.isfile(song['cover']):
                self.send_file(song['cover'])
            else:
                self.send_error(404)
        elif p == '/api/state':
            guest, new_guest, host = self.identity()
            st.refresh_songs()
            with st.lock:
                queue = [{'qid': q['qid'], 'id': q['id'], 'title': q['title'], 'artist': q['artist'],
                          'mine': q['guest'] == guest} for q in st.queue]
            self.send_json({'now': st.now_playing(), 'queue': queue, 'host': host,
                            'songs': len(st.songs)},
                           set_cookies=self.guest_cookie(new_guest))
        else:
            self.send_error(404)

    def do_POST(self):
        p = urllib.parse.urlparse(self.path).path
        st = self.store
        guest, new_guest, host = self.identity()
        body = self.read_body()
        cookies = self.guest_cookie(new_guest)

        if p == '/api/queue':
            st.refresh_songs()
            item, err = st.add(str(body.get('id', '')), guest)
            if err:
                self.send_json({'error': err}, 400, cookies)
            else:
                self.send_json({'ok': True, 'position': len(st.queue)}, 200, cookies)
        elif p == '/api/remove':
            err = st.remove(str(body.get('qid', '')), guest, host)
            self.send_json({'error': err} if err else {'ok': True}, 400 if err else 200, cookies)
        elif p == '/api/move':
            if not host:
                self.send_json({'error': 'Host only'}, 403, cookies)
                return
            try:
                delta = int(body.get('delta', 0))
            except (TypeError, ValueError):
                delta = 0
            err = st.move(str(body.get('qid', '')), delta)
            self.send_json({'error': err} if err else {'ok': True}, 400 if err else 200, cookies)
        elif p == '/api/host':
            if str(body.get('pin', '')).strip() == st.pin:
                token = secrets.token_hex(16)
                st.host_tokens.add(token)
                self.send_json({'ok': True}, 200,
                               cookies + ('kq_host=%s; Path=/; Max-Age=86400; SameSite=Lax' % token,))
            else:
                time.sleep(1)   # slow down guessing
                self.send_json({'error': 'Wrong PIN'}, 403, cookies)
        else:
            self.send_error(404)


def background(store, port):
    tick = 0
    while True:
        try:
            store.process_claims()
            if tick % 60 == 0:
                publish_address(store, port)
        except Exception as e:  # keep serving whatever happens
            print('background:', e, file=sys.stderr)
        tick += 1
        time.sleep(0.5)


def main():
    ap = argparse.ArgumentParser(description='Karaoke song queue for phones on the same network')
    ap.add_argument('--dir', default=os.path.normpath(os.path.join(HERE, '..', 'game', 'remote')),
                    help='folder shared with the game (default: ../game/remote)')
    ap.add_argument('--port', type=int, default=int(os.environ.get('KARAOKE_PORT', '8080')))
    args = ap.parse_args()

    os.makedirs(args.dir, exist_ok=True)
    store = Store(args.dir)
    Handler.store = store
    url = publish_address(store, args.port)
    threading.Thread(target=background, args=(store, args.port), daemon=True).start()

    httpd = ThreadingHTTPServer(('0.0.0.0', args.port), Handler)
    print('Karaoke queue on %s  (host PIN %s, in %s)' % (url, store.pin, store.path('pin.txt')), flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
