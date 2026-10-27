#!/usr/bin/env python3
"""
Make an UltraStar song (.txt with notes and timings) from your own audio or
music-video file, on your own PC.

    ~/vocal-remover/bin/python make-song.py "Artist - Title.mp4" \\
        --artist "Artist" --title "Title" [--lyrics lyrics.txt]

What it does:
  1. splits the vocals from the music with Demucs (and keeps the music as a
     backing track for the Vocals switch)
  2. finds when each word is sung with Whisper, a speech-recognition model
     that runs locally. With --lyrics (a plain text file, one sung line per
     line) your text and line breaks are used and only the timing comes from
     Whisper; without it the words Whisper hears are used.
  3. tracks the sung pitch and turns each word into one or more notes
  4. writes a song folder into the songs folder: the media file, the .txt,
     a cover picture and the backing track

The result is a good starting point, not perfect: check it by singing it, and
fix words or timings in the .txt (or the song editor) where needed.

Setup once (as karaoke):  ~/vocal-remover/bin/pip install faster-whisper
"""

import argparse
import difflib
import os
import re
import shutil
import subprocess
import sys
import tempfile

import numpy as np

SR = 16000          # analysis sample rate
HOP = 160           # 10 ms pitch frames
BPM = 300           # UltraStar beat = 60 / (BPM * 4) s = 50 ms
BEAT = 60.0 / (BPM * 4)


# ---------------------------------------------------------------- helpers

def run(cmd, what):
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if res.returncode != 0:
        tail = res.stdout.decode('utf-8', 'replace').strip().splitlines()[-10:]
        sys.exit('%s failed:\n  %s' % (what, '\n  '.join(tail)))
    return res


def load_mono(path):
    """float32 mono samples at SR, decoded by ffmpeg."""
    res = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-i', path, '-vn',
                          '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if res.returncode != 0:
        sys.exit('ffmpeg could not read %s: %s' % (path, res.stderr.decode()[-300:]))
    return np.frombuffer(res.stdout, dtype=np.float32).copy()


# ---------------------------------------------------------------- pitch

def track_pitch(x, fmin=65.0, fmax=1050.0, threshold=0.15):
    """YIN pitch tracker. Returns (midi per 10 ms frame, nan when unvoiced)."""
    win = 1024
    tau_min = int(SR / fmax)
    tau_max = int(SR / fmin)
    span = win + tau_max
    n = max(0, (len(x) - span) // HOP + 1)
    midi = np.full(n, np.nan)
    if n == 0:
        return midi
    rms_all = np.sqrt(np.mean(x ** 2)) + 1e-9
    nfft = 1 << int(np.ceil(np.log2(span + win)))
    for start in range(0, n, 512):                       # blocks of frames
        idx = np.arange(start, min(n, start + 512))
        frames = np.stack([x[i * HOP:i * HOP + span] for i in idx]).astype(np.float64)
        a = frames[:, :win]
        # autocorrelation of the window against the frame, via FFT
        fa = np.fft.rfft(a, nfft)
        ff = np.fft.rfft(frames, nfft)
        acf = np.fft.irfft(np.conj(fa) * ff, nfft)[:, :tau_max + 1]
        sq = np.cumsum(np.concatenate([np.zeros((len(idx), 1)), frames ** 2], axis=1), axis=1)
        e0 = sq[:, win][:, None]
        taus = np.arange(tau_max + 1)
        e_tau = sq[:, taus + win] - sq[:, taus]
        d = e0 + e_tau - 2 * acf
        d[:, 0] = 0
        cum = np.cumsum(d[:, 1:], axis=1)
        cmnd = np.ones_like(d)
        cmnd[:, 1:] = d[:, 1:] * taus[1:] / np.maximum(cum, 1e-12)
        rms = np.sqrt(np.mean(a ** 2, axis=1))
        for k, i in enumerate(idx):
            if rms[k] < 0.05 * rms_all:
                continue
            c = cmnd[k]
            below = np.where(c[tau_min:tau_max] < threshold)[0]
            if len(below) == 0:
                continue
            t = below[0] + tau_min
            while t + 1 < tau_max and c[t + 1] < c[t]:
                t += 1
            # parabolic interpolation around the minimum
            if 1 <= t < tau_max:
                y0, y1, y2 = c[t - 1], c[t], c[t + 1]
                den = y0 - 2 * y1 + y2
                tf = t + (0.5 * (y0 - y2) / den if den != 0 else 0)
            else:
                tf = t
            f0 = SR / tf
            midi[i] = 69 + 12 * np.log2(f0 / 440.0)
    return midi


def median_filter(v, k=5):
    out = v.copy()
    h = k // 2
    for i in range(len(v)):
        w = v[max(0, i - h):i + h + 1]
        w = w[~np.isnan(w)]
        out[i] = np.median(w) if len(w) and not np.isnan(v[i]) else np.nan
    return out


def word_notes(midi, t0, t1, fallback):
    """Splits one word (t0..t1 s) into notes [(start, end, pitch)] where the
    sung pitch clearly changes (a held / melismatic word)."""
    a = int(t0 / (HOP / SR))
    b = max(a + 1, int(t1 / (HOP / SR)))
    seg = midi[a:b]
    if len(seg) == 0 or np.all(np.isnan(seg)):
        return [(t0, t1, fallback)]
    r = np.round(seg)
    runs = []                                  # [first frame, last frame, pitch]
    for i, p in enumerate(r):
        if np.isnan(p):
            continue
        if runs and runs[-1][2] == p and i - runs[-1][1] <= 3:
            runs[-1][1] = i
        else:
            runs.append([i, i, p])
    # merge runs shorter than 80 ms into a neighbour
    changed = True
    while changed and len(runs) > 1:
        changed = False
        for j, (s, e, p) in enumerate(runs):
            if e - s + 1 < 8:
                k = j - 1 if j > 0 else j + 1
                runs[k][0] = min(runs[k][0], s)
                runs[k][1] = max(runs[k][1], e)
                del runs[j]
                changed = True
                break
        # join neighbours that ended up on the same pitch
        j = 1
        while j < len(runs):
            if runs[j][2] == runs[j - 1][2]:
                runs[j - 1][1] = runs[j][1]
                del runs[j]
            else:
                j += 1
    runs = runs[:4]                           # at most 4 notes per word
    notes = []
    for j, (s, e, p) in enumerate(runs):
        ns = t0 if j == 0 else a * HOP / SR + s * HOP / SR
        ne = t1 if j == len(runs) - 1 else a * HOP / SR + runs[j + 1][0] * HOP / SR
        notes.append((ns, ne, int(p)))
    return notes


# ---------------------------------------------------------------- words

def norm(w):
    return re.sub(r"[^a-z0-9']", '', w.lower())


def transcribe(vocals_audio, model_size, language, prompt):
    """vocals_audio: float32 mono samples at 16 kHz (decoded by ffmpeg, so
    faster-whisper's own decoder (PyAV) isn't needed)."""
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        sys.exit('faster-whisper is not installed. Run:\n'
                 '  ~/vocal-remover/bin/pip install faster-whisper')
    print('Finding the words (Whisper %s, first run downloads the model)...' % model_size, flush=True)
    model = WhisperModel(model_size, device='cpu', compute_type='int8')
    segments, _info = model.transcribe(vocals_audio, language=language, word_timestamps=True,
                                       initial_prompt=prompt, vad_filter=True,
                                       condition_on_previous_text=False)
    lines = []
    for seg in segments:
        words = [(w.word.strip(), w.start, w.end) for w in (seg.words or []) if w.word.strip()]
        if words:
            lines.append(words)
    return lines


def align_lyrics(lyric_lines, heard_lines):
    """Gives the user's own words the timings of the words Whisper heard."""
    heard = [w for line in heard_lines for w in line]
    mine = [(li, w) for li, line in enumerate(lyric_lines) for w in line.split()]
    sm = difflib.SequenceMatcher(a=[norm(w) for _, w in mine], b=[norm(w[0]) for w in heard],
                                 autojunk=False)
    times = [None] * len(mine)
    for blk in sm.get_matching_blocks():
        for k in range(blk.size):
            h = heard[blk.b + k]
            times[blk.a + k] = (h[1], h[2])
    # unmatched words: share out the time between their matched neighbours
    i = 0
    total_end = heard[-1][2] if heard else 0.0
    while i < len(mine):
        if times[i] is not None:
            i += 1
            continue
        j = i
        while j < len(mine) and times[j] is None:
            j += 1
        start = times[i - 1][1] if i > 0 else max(0.0, (times[j][0] if j < len(mine) else total_end) - 0.4 * (j - i))
        end = times[j][0] if j < len(mine) else start + 0.4 * (j - i)
        if end <= start:
            end = start + 0.2 * (j - i)
        # don't stretch missed words across an instrumental gap
        end = min(end, start + 0.6 * (j - i))
        weights = [max(1, len(mine[k][1])) for k in range(i, j)]
        pos = start
        for k, wgt in zip(range(i, j), weights):
            dur = (end - start) * wgt / sum(weights)
            times[k] = (pos, pos + dur)
            pos += dur
        i = j
    out = [[] for _ in lyric_lines]
    for (li, w), t in zip(mine, times):
        out[li].append((w, t[0], t[1]))
    return [l for l in out if l], sum(1 for t in sm.get_matching_blocks() for _ in range(t.size)), len(mine)


def split_long_lines(lines, gap=1.2, max_words=8, max_chars=38):
    """Lines that fit on screen: break at pauses, after a sentence ends, and
    before a line gets too long."""
    out = []
    for line in lines:
        cur = []
        for w in line:
            chars = sum(len(x[0]) + 1 for x in cur) + len(w[0])
            ended = cur and cur[-1][0][-1:] in '.!?' and len(cur) >= 3
            if cur and (w[1] - cur[-1][2] > gap or len(cur) >= max_words
                        or chars > max_chars or ended):
                out.append(cur)
                cur = []
            cur.append(w)
        if cur:
            out.append(cur)
    # a lone short word at the end of a phrase joins the line before it
    merged = []
    for line in out:
        if (merged and len(line) == 1 and line[0][1] - merged[-1][-1][2] < 0.6
                and sum(len(x[0]) + 1 for x in merged[-1]) + len(line[0][0]) <= max_chars + 8):
            merged[-1] = merged[-1] + line
        else:
            merged.append(line)
    return merged


def snap_onsets(lines, midi, max_back=0.3):
    """Whisper tends to put sung word starts a little late; move each word's
    start back to where the singing actually begins (voiced pitch frames),
    never before the previous word ends."""
    fr = HOP / SR
    prev_end = 0.0
    out = []
    for line in lines:
        nl = []
        for (w, t0, t1) in line:
            i = int(t0 / fr)
            limit = max(int((prev_end + 0.02) / fr), int((t0 - max_back) / fr), 0)
            if 0 <= i < len(midi):
                # start from the first voiced frame at/after t0 (within 100 ms)
                j = i
                while j < min(len(midi), i + 10) and np.isnan(midi[j]):
                    j += 1
                if j < len(midi) and not np.isnan(midi[j]):
                    while j - 1 >= limit and not np.isnan(midi[j - 1]):
                        j -= 1
                    # only move to a clear start: a short silence must come
                    # right before it (continuous sound = no reliable onset)
                    clear = j - 3 >= 0 and j - 1 >= limit and np.all(np.isnan(midi[j - 3:j]))
                    # pitch frames cover 64 ms from their start: use the middle
                    if clear and j < i:
                        t0 = min(t0, j * fr + 0.032)
            nl.append((w, t0, max(t1, t0 + BEAT)))
            prev_end = max(t0, t1)
        out.append(nl)
    return out


# ---------------------------------------------------------------- output

def build_txt(lines, midi, artist, title, media_name, cover, instrumental, video):
    voiced = midi[~np.isnan(midi)]
    fallback = int(np.round(np.median(voiced))) if len(voiced) else 60
    gap = lines[0][0][1]
    body = []
    last_end_beat = 0
    for li, line in enumerate(lines):
        if li > 0:
            body.append('- %d' % last_end_beat)
        for wi, (word, t0, t1) in enumerate(line):
            t1 = max(t1, t0 + BEAT)
            notes = word_notes(midi, t0, t1, fallback)
            for ni, (ns, ne, p) in enumerate(notes):
                start = int(round((ns - gap) / BEAT))
                length = int(round((ne - ns) / BEAT))
                if start < last_end_beat:
                    start = last_end_beat
                length = max(1, length)
                if ni == 0:
                    text = word if wi == 0 else ' ' + word
                else:
                    text = '~'
                body.append(': %d %d %d %s' % (start, length, p - 60, text))
                last_end_beat = start + length
    head = ['#TITLE:%s' % title, '#ARTIST:%s' % artist, '#MP3:%s' % media_name]
    if video:
        head.append('#VIDEO:%s' % media_name)
    if cover:
        head.append('#COVER:%s' % cover)
    if instrumental:
        head.append('#INSTRUMENTAL:%s' % instrumental)
    head += ['#BPM:%d' % BPM, '#GAP:%d' % int(round(gap * 1000))]
    return '\n'.join(head + body + ['E', ''])


def main():
    ap = argparse.ArgumentParser(description='Make an UltraStar song from your own audio/video file.')
    ap.add_argument('media', help='mp3 / mp4 / ... file of the song')
    ap.add_argument('--artist', required=True)
    ap.add_argument('--title', required=True)
    ap.add_argument('--lyrics', help='plain text file with the lyrics, one sung line per line')
    ap.add_argument('--songs', default='/home/karaoke/songs', help='songs folder to write into')
    ap.add_argument('--whisper', default='medium',
                    help='Whisper model: small (fast), medium (default), large-v3 (best, slow)')
    ap.add_argument('--no-snap', action='store_true',
                    help="use Whisper's word starts as they are (don't move them to the sung onset)")
    ap.add_argument('--offset', type=int, default=0,
                    help='move all lyrics by this many ms (negative = earlier), e.g. --offset -150')
    ap.add_argument('--force', action='store_true', help='remake the .txt of a song made before')
    ap.add_argument('--language', default='en', help="sung language, e.g. en (or 'auto')")
    args = ap.parse_args()

    media = os.path.abspath(args.media)
    if not os.path.isfile(media):
        sys.exit('No such file: ' + media)
    name = re.sub(r'[\\/:*?"<>|]+', '', '%s - %s' % (args.artist, args.title)).strip()
    dest = os.path.join(args.songs, name)
    if os.path.exists(os.path.join(dest, name + '.txt')) and not args.force:
        sys.exit('%s already exists - add --force to make its .txt again.' % dest)
    ext = os.path.splitext(media)[1].lower()
    video = ext in ('.mp4', '.mkv', '.webm', '.mov', '.avi', '.m4v')

    lyric_lines = None
    if args.lyrics:
        with open(args.lyrics, encoding='utf-8', errors='replace') as fh:
            lyric_lines = [l.strip() for l in fh if l.strip() and not l.strip().startswith('[')]

    with tempfile.TemporaryDirectory(prefix='make-song-') as work:
        wav = os.path.join(work, 'song.wav')
        run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', media, '-vn', '-ac', '2',
             '-ar', '44100', wav], 'Reading the audio')

        print('Separating the vocals (Demucs)...', flush=True)
        run([sys.executable, '-m', 'demucs', '--two-stems', 'vocals', '-n', 'htdemucs',
             '-o', work, '--filename', '{stem}.{ext}', wav], 'Demucs')
        vocals = os.path.join(work, 'htdemucs', 'vocals.wav')
        backing = os.path.join(work, 'htdemucs', 'no_vocals.wav')

        prompt = ' '.join(lyric_lines)[:800] if lyric_lines else None
        vocals_audio = load_mono(vocals)
        heard = transcribe(vocals_audio, args.whisper, None if args.language == 'auto' else args.language, prompt)
        if not heard:
            sys.exit('Whisper found no sung words - is there singing in this file?')
        if lyric_lines:
            lines, matched, total = align_lyrics(lyric_lines, heard)
            print('Matched %d of %d of your words to the singing.' % (matched, total))
        else:
            lines = heard
        lines = split_long_lines(lines)

        print('Tracking the sung notes...', flush=True)
        midi = median_filter(track_pitch(vocals_audio))
        if not args.no_snap:
            lines = snap_onsets(lines, midi)
        if args.offset:
            lines = [[(w, max(0.0, a + args.offset / 1000.0), max(0.0, b + args.offset / 1000.0))
                      for (w, a, b) in l] for l in lines]

        os.makedirs(dest, exist_ok=True)
        media_name = name + ext
        shutil.copy2(media, os.path.join(dest, media_name))
        instrumental = name + ' [Instrumental].mp3'
        run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', backing, '-b:a', '256k',
             os.path.join(dest, instrumental)], 'Saving the backing track')
        cover = None
        if video:
            cover = name + ' [CO].jpg'
            # the attached cover picture if there is one, else a frame 20 s in
            res = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', media,
                                  '-map', '0:v:m:attached_pic?', '-frames:v', '1',
                                  os.path.join(dest, cover)])
            if res.returncode != 0 or not os.path.isfile(os.path.join(dest, cover)):
                subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-ss', '20', '-i', media,
                                '-frames:v', '1', os.path.join(dest, cover)])
            if not os.path.isfile(os.path.join(dest, cover)):
                cover = None

        txt = build_txt(lines, midi, args.artist, args.title, media_name, cover, instrumental, video)
        with open(os.path.join(dest, name + '.txt'), 'w', encoding='utf-8') as fh:
            fh.write(txt)
        # the words on their own, one line per sung line: fix any wrong words
        # here and run again with --lyrics this file --force
        words_file = os.path.join(dest, 'words.txt')
        if not args.lyrics or os.path.abspath(args.lyrics) != os.path.abspath(words_file):
            with open(words_file, 'w', encoding='utf-8') as fh:
                fh.write('\n'.join(' '.join(w for w, _a, _b in l) for l in lines) + '\n')

    # same backing track as the rest of the library: lead vocal removed,
    # backing vocals kept (karaoke model), when that tool is installed
    kara_py = os.path.expanduser('~/karaoke-remover/bin/python')
    if os.path.isfile(kara_py):
        print('Making the backing track with backing vocals kept (karaoke model)...', flush=True)
        subprocess.run([kara_py, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        'make-instrumentals.py'), '--keep-backing', '--model',
                        'UVR_MDXNET_KARA_2.onnx', dest])

    print('\nWords file: %s\n  (fix wrong words there, then run again with --lyrics "that file" --force)'
          % os.path.join(dest, 'words.txt'))
    print('\nDone: %s\n%d lines, %d words. Restart the game to find it, sing it once, and fix '
          'any wrong words or timings in the .txt.' % (dest, len(lines), sum(len(l) for l in lines)))


if __name__ == '__main__':
    main()
