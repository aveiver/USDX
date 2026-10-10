"""
Tiny QR code encoder (byte mode, error correction level L, versions 1-5).

Enough for a short URL such as http://192.168.1.20:8080 so the karaoke
screen can show a code guests scan with their phone camera. Follows the
QR Code Model 2 spec (ISO/IEC 18004); structure after Project Nayuki's
reference implementation.

    matrix = encode("http://192.168.1.20:8080")   # list of rows of 0/1
"""

# version -> (data codewords, ec codewords) for level L, all single block
_CAPACITY = {1: (19, 7), 2: (34, 10), 3: (55, 15), 4: (80, 20), 5: (108, 26)}

_EXP = [0] * 512
_LOG = [0] * 256
_x = 1
for _i in range(255):
    _EXP[_i] = _x
    _LOG[_x] = _i
    _x <<= 1
    if _x & 0x100:
        _x ^= 0x11D
for _i in range(255, 512):
    _EXP[_i] = _EXP[_i - 255]


def _gf_mul(a, b):
    if a == 0 or b == 0:
        return 0
    return _EXP[_LOG[a] + _LOG[b]]


def _rs_generator(degree):
    # coefficients, highest power first, leading 1 omitted
    result = [0] * (degree - 1) + [1]
    root = 1
    for _ in range(degree):
        for j in range(degree):
            result[j] = _gf_mul(result[j], root)
            if j + 1 < degree:
                result[j] ^= result[j + 1]
        root = _gf_mul(root, 2)
    return result


def _rs_remainder(data, degree):
    gen = _rs_generator(degree)
    result = [0] * degree
    for b in data:
        factor = b ^ result.pop(0)
        result.append(0)
        for i in range(degree):
            result[i] ^= _gf_mul(gen[i], factor)
    return result


def _codewords(payload, version):
    data_cw, ec_cw = _CAPACITY[version]
    bits = []

    def put(value, length):
        for i in range(length - 1, -1, -1):
            bits.append((value >> i) & 1)

    put(0b0100, 4)            # byte mode
    put(len(payload), 8)      # character count (versions 1-9)
    for b in payload:
        put(b, 8)
    capacity_bits = data_cw * 8
    put(0, min(4, capacity_bits - len(bits)))   # terminator
    put(0, (8 - len(bits) % 8) % 8)             # byte align
    pad = 0xEC
    while len(bits) < capacity_bits:
        put(pad, 8)
        pad ^= 0xEC ^ 0x11
    data = [int(''.join(map(str, bits[i:i + 8])), 2) for i in range(0, len(bits), 8)]
    return data + _rs_remainder(data, ec_cw)


class _Matrix:
    def __init__(self, version):
        self.version = version
        self.size = version * 4 + 17
        self.mod = [[0] * self.size for _ in range(self.size)]
        self.func = [[False] * self.size for _ in range(self.size)]

    def set_func(self, x, y, dark):
        self.mod[y][x] = 1 if dark else 0
        self.func[y][x] = True

    def draw_function_patterns(self):
        n = self.size
        for i in range(n):            # timing patterns
            self.set_func(6, i, i % 2 == 0)
            self.set_func(i, 6, i % 2 == 0)
        for (cx, cy) in ((3, 3), (n - 4, 3), (3, n - 4)):   # finders + separators
            for dy in range(-4, 5):
                for dx in range(-4, 5):
                    x, y = cx + dx, cy + dy
                    if 0 <= x < n and 0 <= y < n:
                        dist = max(abs(dx), abs(dy))
                        self.set_func(x, y, dist not in (2, 4))
        if self.version >= 2:          # one alignment pattern for v2-v6
            p = self.version * 4 + 10
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    self.set_func(p + dx, p + dy, max(abs(dx), abs(dy)) != 1)
        self.draw_format(0)            # reserve the format areas

    def draw_format(self, mask):
        n = self.size
        data = (1 << 3) | mask         # level L = 01
        rem = data
        for _ in range(10):
            rem = (rem << 1) ^ ((rem >> 9) * 0x537)
        bits = ((data << 10) | rem) ^ 0x5412

        def bit(i):
            return (bits >> i) & 1

        for i in range(0, 6):
            self.set_func(8, i, bit(i))
        self.set_func(8, 7, bit(6))
        self.set_func(8, 8, bit(7))
        self.set_func(7, 8, bit(8))
        for i in range(9, 15):
            self.set_func(14 - i, 8, bit(i))
        for i in range(0, 8):
            self.set_func(n - 1 - i, 8, bit(i))
        for i in range(8, 15):
            self.set_func(8, n - 15 + i, bit(i))
        self.set_func(8, n - 8, 1)     # the dark module

    def draw_codewords(self, cw):
        n = self.size
        i = 0
        total = len(cw) * 8
        right = n - 1
        while right >= 1:
            if right == 6:
                right = 5
            for vert in range(n):
                for j in range(2):
                    x = right - j
                    upward = ((right + 1) & 2) == 0
                    y = n - 1 - vert if upward else vert
                    if not self.func[y][x] and i < total:
                        self.mod[y][x] = (cw[i >> 3] >> (7 - (i & 7))) & 1
                        i += 1
            right -= 2

    def apply_mask(self, mask):
        n = self.size
        for y in range(n):
            for x in range(n):
                if self.func[y][x]:
                    continue
                if mask == 0:
                    inv = (x + y) % 2 == 0
                elif mask == 1:
                    inv = y % 2 == 0
                elif mask == 2:
                    inv = x % 3 == 0
                elif mask == 3:
                    inv = (x + y) % 3 == 0
                elif mask == 4:
                    inv = (x // 3 + y // 2) % 2 == 0
                elif mask == 5:
                    inv = x * y % 2 + x * y % 3 == 0
                elif mask == 6:
                    inv = (x * y % 2 + x * y % 3) % 2 == 0
                else:
                    inv = ((x + y) % 2 + x * y % 3) % 2 == 0
                if inv:
                    self.mod[y][x] ^= 1

    def penalty(self):
        n = self.size
        m = self.mod
        score = 0
        lines = [m[y] for y in range(n)] + [[m[y][x] for y in range(n)] for x in range(n)]
        for line in lines:
            run = 1
            for i in range(1, n + 1):
                if i < n and line[i] == line[i - 1]:
                    run += 1
                else:
                    if run >= 5:
                        score += 3 + (run - 5)
                    run = 1
            s = ''.join(map(str, line))
            score += 40 * (s.count('10111010000') + s.count('00001011101'))
        for y in range(n - 1):
            for x in range(n - 1):
                c = m[y][x]
                if c == m[y][x + 1] == m[y + 1][x] == m[y + 1][x + 1]:
                    score += 3
        dark = sum(map(sum, m))
        total = n * n
        k = (abs(dark * 20 - total * 10) + total - 1) // total - 1
        score += max(0, k) * 10
        return score


def encode(text):
    payload = text.encode('utf-8')
    version = next((v for v in sorted(_CAPACITY) if len(payload) <= _CAPACITY[v][0] - 2), None)
    if version is None:
        raise ValueError('text too long for a version 1-5 QR code')
    cw = _codewords(payload, version)
    best = None
    for mask in range(8):
        q = _Matrix(version)
        q.draw_function_patterns()
        q.draw_codewords(cw)
        q.apply_mask(mask)
        q.draw_format(mask)
        p = q.penalty()
        if best is None or p < best[0]:
            best = (p, q)
    return best[1].mod


if __name__ == '__main__':
    import sys
    for row in encode(sys.argv[1] if len(sys.argv) > 1 else 'http://192.168.1.20:8080'):
        print(''.join('##' if c else '  ' for c in row))
