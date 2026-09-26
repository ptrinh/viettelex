#!/usr/bin/env python3
"""Structural check of an MSI the way Windows Installer loads it (stdlib only).

    check_msi.py <file.msi>

Checks, for every table in _Tables:
  * the table stream exists and its size is a whole number of rows;
  * every string reference points into the string pool;
  * rows are strictly ascending by primary key (the stored values: string ids /
    biased integers). Windows Installer relies on this order when it loads a
    persistent table; msitools' SQL INSERT (`msibuild -q`) appends rows out of order,
    which Windows reports as "Error 2211: Could not create database table <name>"
    during FileCost (VietTelex 1.0.0). Wine and libmsi accept such a file, so this
    must be checked on the bytes;
and, for the tables VietTelex writes, that the column schema is the standard one.
Exit 1 with a message per problem.
"""
import struct
import sys

# ---------------------------------------------------------------- compound file
def read_cfb(path):
    d = open(path, 'rb').read()
    if d[:8] != bytes.fromhex('d0cf11e0a1b11ae1'):
        raise SystemExit(f'{path}: not a compound file')
    ss = 1 << struct.unpack_from('<H', d, 30)[0]
    mss = 1 << struct.unpack_from('<H', d, 32)[0]
    nfat = struct.unpack_from('<I', d, 0x2c)[0]
    dirstart = struct.unpack_from('<I', d, 0x30)[0]
    cutoff = struct.unpack_from('<I', d, 0x38)[0]
    minifat_start = struct.unpack_from('<I', d, 0x3c)[0]
    difstart, ndif = struct.unpack_from('<II', d, 0x44)

    def sec(i):
        return d[(i + 1) * ss:(i + 2) * ss]
    difat = list(struct.unpack_from('<109I', d, 0x4c))
    s = difstart
    for _ in range(ndif):
        v = struct.unpack('<%dI' % (ss // 4), sec(s))
        difat += v[:-1]
        s = v[-1]
    fat = []
    for x in difat[:nfat]:
        fat += struct.unpack('<%dI' % (ss // 4), sec(x))

    def chain(st):
        out = []
        while st < 0xFFFFFFF0:
            out.append(st)
            st = fat[st]
        return out
    dird = b''.join(sec(i) for i in chain(dirstart))
    ents = []
    for i in range(len(dird) // 128):
        e = dird[i * 128:(i + 1) * 128]
        nl = struct.unpack_from('<H', e, 64)[0]
        ents.append((e[:max(nl - 2, 0)].decode('utf-16le', 'surrogatepass'), e[66],
                     *struct.unpack_from('<IQ', e, 116)))
    mini = b''.join(sec(i) for i in chain(ents[0][2]))
    minifat = []
    for i in chain(minifat_start):
        minifat += struct.unpack('<%dI' % (ss // 4), sec(i))

    def read(start, size):
        size &= 0xFFFFFFFF
        if size < cutoff:
            out, st = b'', start
            while st < 0xFFFFFFF0:
                out += mini[st * mss:(st + 1) * mss]
                st = minifat[st]
            return out[:size]
        return b''.join(sec(i) for i in chain(start))[:size]
    return {decode_name(n): read(st, sz) for n, t, st, sz in ents if t == 2}


def decode_name(n):
    b64 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._'
    out = ''
    for ch in n:
        c = ord(ch)
        if 0x3800 <= c < 0x4800:
            c -= 0x3800
            out += b64[c & 0x3f] + b64[c >> 6]
        elif 0x4800 <= c < 0x4840:
            out += b64[c - 0x4800]
        elif c == 0x4840:
            out += '!'
        else:
            out += ch
    return out

# ---------------------------------------------------------------- MSI database
T_STRING, T_NULLABLE, T_KEY, T_LOCAL = 0x0800, 0x1000, 0x2000, 0x0200


class Msi:
    def __init__(self, path):
        self.st = read_cfb(path)
        pool, data = self.st['!_StringPool'], self.st['!_StringData']
        cp = struct.unpack_from('<I', pool, 0)[0]
        self.long_refs = bool(cp & 0x80000000)
        self.strings = [None]
        off, i = 0, 4
        while i + 4 <= len(pool):
            ln, rc = struct.unpack_from('<HH', pool, i)
            i += 4
            if ln == 0 and rc > 0:  # long string: (0, len_hi) (len_lo, refcount)
                lo, rc2 = struct.unpack_from('<HH', pool, i)
                i += 4
                ln, rc = (rc << 16) | lo, rc2
            self.strings.append(data[off:off + ln])
            off += ln
        self.sref = 3 if self.long_refs else 2
        tables = self.st['!_Tables']
        self.tables = [self.s(struct.unpack_from('<H', tables, k)[0]) for k in range(0, len(tables), 2)]
        cols = self.st['!_Columns']
        n = len(cols) // 8   # Table(s2) Number(i2) Name(s2) Type(i2)
        c = [cols[k * 2 * n:(k + 1) * 2 * n] for k in range(4)]
        self.columns = {}
        for r in range(n):
            t = self.s(struct.unpack_from('<H', c[0], r * 2)[0])
            num = struct.unpack_from('<H', c[1], r * 2)[0] - 0x8000
            name = self.s(struct.unpack_from('<H', c[2], r * 2)[0])
            typ = struct.unpack_from('<H', c[3], r * 2)[0] - 0x8000
            self.columns.setdefault(t, []).append((num, name, typ))
        for t in self.columns:
            self.columns[t].sort()

    def s(self, sid):
        return self.strings[sid].decode('cp1252', 'replace') if 0 < sid < len(self.strings) else ''

    def width(self, typ):
        if typ & T_STRING:
            return self.sref
        return 4 if (typ & 0xff) == 4 else 2

    def rows(self, table):
        cols = self.columns[table]
        data = self.st.get('!' + table, b'')
        rowsize = sum(self.width(t) for _, _, t in cols)
        if rowsize == 0 or len(data) % rowsize:
            return None, f'{table}: stream size {len(data)} is not a multiple of row size {rowsize}'
        n = len(data) // rowsize
        out = [[] for _ in range(n)]
        off = 0
        for _, _, typ in cols:
            w = self.width(typ)
            for r in range(n):
                out[r].append(int.from_bytes(data[off + r * w:off + (r + 1) * w], 'little'))
            off += n * w
        return out, None


def typestr(typ):
    """_Columns type -> idt notation (s72, i2, L0, ...)."""
    size = typ & 0xff
    if typ & T_STRING:
        c = 'l' if typ & T_LOCAL else 's'
    else:
        c = 'i'
    return (c.upper() if typ & T_NULLABLE else c) + str(size)


# Standard schema of every table VietTelex's MSI writes: (name, type, key). Matches the
# MSI 5.0 schema as emitted by wixl in a Store-certified package (File/Media sequences i4).
STANDARD = {
    'Registry': [('Registry', 's72', 1), ('Root', 'i2', 0), ('Key', 'l255', 0), ('Name', 'L255', 0),
                 ('Value', 'L0', 0), ('Component_', 's72', 0)],
    'Component': [('Component', 's72', 1), ('ComponentId', 'S38', 0), ('Directory_', 's72', 0),
                  ('Attributes', 'i2', 0), ('Condition', 'S255', 0), ('KeyPath', 'S72', 0)],
    'File': [('File', 's72', 1), ('Component_', 's72', 0), ('FileName', 'l255', 0), ('FileSize', 'i4', 0),
             ('Version', 'S72', 0), ('Language', 'S20', 0), ('Attributes', 'I2', 0), ('Sequence', 'i4', 0)],
    'CustomAction': [('Action', 's72', 1), ('Type', 'i2', 0), ('Source', 'S72', 0), ('Target', 'S255', 0),
                     ('ExtendedType', 'I4', 0)],
    'InstallExecuteSequence': [('Action', 's72', 1), ('Condition', 'S255', 0), ('Sequence', 'I2', 0)],
    'Directory': [('Directory', 's72', 1), ('Directory_Parent', 'S72', 0), ('DefaultDir', 'l255', 0)],
    'Feature': [('Feature', 's38', 1), ('Feature_Parent', 'S38', 0), ('Title', 'L64', 0),
                ('Description', 'L255', 0), ('Display', 'I2', 0), ('Level', 'i2', 0),
                ('Directory_', 'S72', 0), ('Attributes', 'i2', 0)],
    'FeatureComponents': [('Feature_', 's38', 1), ('Component_', 's72', 1)],
    'Shortcut': [('Shortcut', 's72', 1), ('Directory_', 's72', 0), ('Name', 'l128', 0),
                 ('Component_', 's72', 0), ('Target', 's72', 0), ('Arguments', 'S255', 0),
                 ('Description', 'L255', 0), ('Hotkey', 'I2', 0), ('Icon_', 'S72', 0),
                 ('IconIndex', 'I2', 0), ('ShowCmd', 'I2', 0), ('WkDir', 'S72', 0),
                 ('DisplayResourceDLL', 'S255', 0), ('DisplayResourceId', 'I2', 0),
                 ('DescriptionResourceDLL', 'S255', 0), ('DescriptionResourceId', 'I2', 0)],
    'Property': [('Property', 's72', 1), ('Value', 'l0', 0)],
    'Upgrade': [('UpgradeCode', 's38', 1), ('VersionMin', 'S20', 1), ('VersionMax', 'S20', 1),
                ('Language', 'S255', 1), ('Attributes', 'i4', 1), ('Remove', 'S255', 0),
                ('ActionProperty', 's72', 0)],
    'Media': [('DiskId', 'i2', 1), ('LastSequence', 'i4', 0), ('DiskPrompt', 'L64', 0),
              ('Cabinet', 'S255', 0), ('VolumeLabel', 'S32', 0), ('Source', 'S72', 0)],
    'Icon': [('Name', 's72', 1), ('Data', 'v0', 0)],
    'MsiFileHash': [('File_', 's72', 1), ('Options', 'i2', 0), ('HashPart1', 'i4', 0),
                    ('HashPart2', 'i4', 0), ('HashPart3', 'i4', 0), ('HashPart4', 'i4', 0)],
}


def main(path):
    m = Msi(path)
    problems = []
    for table in m.tables:
        if table not in m.columns:
            problems.append(f'{table}: listed in _Tables but has no _Columns')
            continue
        cols = m.columns[table]
        if [c[0] for c in cols] != list(range(1, len(cols) + 1)):
            problems.append(f'{table}: column numbers are not 1..{len(cols)}')
        rows, err = m.rows(table)
        if err:
            problems.append(err)
            continue
        keyidx = [i for i, (_, _, t) in enumerate(cols) if t & T_KEY]
        for r, row in enumerate(rows):
            for i, (_, name, typ) in enumerate(cols):
                if typ & T_STRING and row[i] >= len(m.strings):
                    problems.append(f'{table} row {r}: {name} string id {row[i]} out of range')
        keys = [tuple(row[i] for i in keyidx) for row in rows]
        for r in range(1, len(keys)):
            if keys[r] <= keys[r - 1]:
                what = 'duplicate' if keys[r] == keys[r - 1] else 'out of order'
                problems.append(f'{table}: row {r} primary key {what} '
                                f'({[m.s(k) if cols[keyidx[j]][2] & T_STRING else k for j, k in enumerate(keys[r])]})')
                break
        if table in STANDARD:
            have = [(n, 'v0' if (t & T_STRING and (t & 0xff) == 0 and n == 'Data') else typestr(t),
                     1 if t & T_KEY else 0) for _, n, t in cols]
            if have != STANDARD[table]:
                problems.append(f'{table}: schema {have} != standard {STANDARD[table]}')
    for p in problems:
        print(f'{path}: {p}', file=sys.stderr)
    if not problems:
        print(f'  {path.rsplit("/", 1)[-1]}: {len(m.tables)} tables well-formed, rows ordered, schemas standard')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(max(main(p) for p in sys.argv[1:]))
