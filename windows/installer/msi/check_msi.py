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
and, for the tables VietTelex writes, that the column schema is the standard one;
that custom actions running an installed file are sequenced after CostFinalize
(error 2731 otherwise — VietTelex 1.0.3 could not be uninstalled); and that no custom
action is FileKey-based (error 2753 on repair — VietTelex 1.0.4).
Exit 1 with a message per problem.
"""
import re
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


def first_key_order_problem(keys):
    """Stored primary keys (string ids / biased ints) must be strictly ascending: that is
    the order Windows Installer loads a persistent table in. libmsi sorts by key TEXT, so a
    new string that reused a freed low id lands out of order (VietTelex 1.0.0, error 2211).
    Returns (row, 'duplicate'|'out of order') for the first bad row, else None."""
    for r in range(1, len(keys)):
        if keys[r] <= keys[r - 1]:
            return r, 'duplicate' if keys[r] == keys[r - 1] else 'out of order'
    return None


def ca_problems(cas, sequences, files, dirs, binaries=frozenset(), conditions=None):
    conditions = conditions or {}
    """Custom-action rules on plain data (see check_custom_action_sequence)."""
    problems = []
    for name, ca in cas.items():
        if (ca['Type'] & 0x3F) in FILE_SOURCED and ca['Source'] in files:
            problems.append(f'CustomAction {name}: type {ca["Type"]} runs installed file {ca["Source"]} '
                            f'(FileKey) -> error 2753 on repair/maintenance; use a property (type 50) action')
    for table, seq in sequences.items():
        cost_final = seq.get('CostFinalize')
        for action, number in seq.items():
            ca = cas.get(action)
            if not ca or number is None or number < 0:
                continue
            base = ca['Type'] & 0x3F
            target = ca['Target'] or ''
            if base in FILE_OR_DIR_SOURCED and (cost_final is None or number <= cost_final):
                problems.append(f'{table}: custom action {action} (type {ca["Type"]}, source {ca["Source"]}) '
                                f'at {number} runs before CostFinalize ({cost_final}) -> error 2731')
            if base in (35, 51) and any(f'[{d}]' in target for d in dirs):
                if cost_final is None or number <= cost_final:
                    problems.append(f'{table}: {action} formats a directory at {number}, before CostFinalize '
                                    f'({cost_final}) -> error 2731')
            if base == 50:
                setters = [a for a, n in seq.items() if cas.get(a) and (cas[a]['Type'] & 0x3F) == 51
                           and cas[a]['Source'] == ca['Source'] and n is not None and 0 <= n < number]
                if not setters:
                    problems.append(f'{table}: {action} runs the exe in property {ca["Source"]} '
                                    f'but nothing sets it before sequence {number}')
        if table == 'InstallExecuteSequence':
            problems += upgrade_order_problems(cas, seq, binaries, conditions.get(table, {}))
        problems += ice77_ice12_problems(cas, seq, dirs)
        if table == 'InstallExecuteSequence' and 'CleanupUser' in seq:
            n, init, rf = seq['CleanupUser'], seq.get('InstallInitialize'), seq.get('RemoveFiles')
            if not (init is not None and rf is not None and init < n < rf):
                problems.append(f'{table}: CleanupUser at {n} must be after InstallInitialize ({init}) '
                                f'and before RemoveFiles ({rf})')
    return problems


def ice63_problems(seq):
    """RemoveExistingProducts may only be sequenced (ICE63; Windows fails with error 2613):
    between InstallValidate and InstallInitialize; IMMEDIATELY after InstallInitialize;
    between InstallExecute/InstallExecuteAgain and InstallFinalize; or after InstallFinalize."""
    rep = seq.get('RemoveExistingProducts')
    if rep is None or rep < 0:
        return []
    iv, ii, fin = seq.get('InstallValidate'), seq.get('InstallInitialize'), seq.get('InstallFinalize')
    ex = [seq[a] for a in ('InstallExecute', 'InstallExecuteAgain') if seq.get(a) is not None]
    ok = False
    if iv is not None and ii is not None and iv < rep < ii:
        ok = True
    if ii is not None and rep > ii and not any(ii < n < rep for a, n in seq.items()
                                               if n is not None and n >= 0 and a != 'RemoveExistingProducts'):
        ok = True
    if fin is not None and any(e < rep < fin for e in ex):
        ok = True
    if fin is not None and rep > fin:
        ok = True
    if ok:
        return []
    return [f'RemoveExistingProducts at {rep} is not a legal position (ICE63 -> error 2613): allowed '
            f'InstallValidate<REP<InstallInitialize, immediately after InstallInitialize, '
            f'InstallExecute<REP<InstallFinalize, or after InstallFinalize']


def ice77_ice12_problems(cas, seq, dirs):
    """ICE77: deferred/rollback/commit custom actions only between InstallInitialize and
    InstallFinalize. ICE12: type 35 (set directory) after CostFinalize; a type 51 that sets
    a Directory property before CostFinalize."""
    problems = []
    ii, fin, cf = seq.get('InstallInitialize'), seq.get('InstallFinalize'), seq.get('CostFinalize')
    for action, n in seq.items():
        ca = cas.get(action)
        if not ca or n is None or n < 0:
            continue
        t, base = ca['Type'], ca['Type'] & 0x3F
        if t & (1024 | 256 | 512):  # in-script: deferred / rollback / commit
            if ii is None or fin is None or not (ii < n < fin):
                problems.append(f'ICE77: in-script custom action {action} at {n} must be between '
                                f'InstallInitialize ({ii}) and InstallFinalize ({fin})')
        if base == 35 and (cf is None or n <= cf):
            problems.append(f'ICE12: type-35 action {action} at {n} must come after CostFinalize ({cf})')
        if base == 51 and ca['Source'] in dirs and (cf is None or n >= cf):
            problems.append(f'ICE12: {action} sets directory {ca["Source"]} at {n}, after CostFinalize ({cf})')
    return problems


def upgrade_order_problems(cas, seq, binaries, conds=None):
    conds = conds or {}
    """Upgrade-in-place rules: the running app is closed before files are validated;
    in-use TIP DLLs are moved aside before this package removes or installs files and
    before the old product is removed; helper actions point at a real Binary row."""
    problems = []
    for name, ca in cas.items():
        if (ca['Type'] & 0x3F) == 2 and ca['Source'] not in binaries:
            problems.append(f'CustomAction {name}: Binary source {ca["Source"]} does not exist')
    iv, rep = seq.get('InstallValidate'), seq.get('RemoveExistingProducts')
    if 'QuitApp' in cas:
        q, t = seq.get('QuitApp'), cas['QuitApp']['Type']
        if q is None or iv is None or q >= iv:
            problems.append(f'QuitApp at {q} must run before InstallValidate ({iv}), or files stay in use')
        if t & 1024:
            problems.append('QuitApp must be immediate (runs as the user, before the script)')
    if 'ReleaseTip' in cas:
        r, t = seq.get('ReleaseTip'), cas['ReleaseTip']['Type']
        if not (t & 1024) or not (t & 2048):
            problems.append('ReleaseTip must be deferred and not impersonated (writes Program Files)')
        if re.search(r'\[[A-Za-z0-9_]+\]"', cas['ReleaseTip']['Target'] or ''):
            problems.append('ReleaseTip: a directory property right before a quote ends in "\\" and '
                            'escapes the quote on the helper command line; append "."')
        cond = conds.get('ReleaseTip') or ''
        if 'NOT UPGRADINGPRODUCTCODE' not in cond:
            problems.append('ReleaseTip needs the condition NOT UPGRADINGPRODUCTCODE: run from the old '
                            'package during a late RemoveExistingProducts it would move the NEW DLLs aside')
        if '--max-version' not in (cas['ReleaseTip']['Target'] or ''):
            problems.append('ReleaseTip needs --max-version <this version>: an old package being removed '
                            'must never move a newer version\'s DLLs')
        for before in ('RemoveFiles', 'InstallFiles', 'RemoveExistingProducts'):
            b = seq.get(before)
            if r is not None and b is not None and r >= b:
                problems.append(f'ReleaseTip at {r} must run before {before} ({b})')
    problems += ice63_problems(seq)
    return problems


def table_dicts(m, table):
    """Rows of `table` as dicts (strings decoded, ints unbiased, null -> None)."""
    if table not in m.columns:
        return []
    rows, err = m.rows(table)
    if err:
        return []
    out = []
    for row in rows:
        d = {}
        for (_, name, typ), v in zip(m.columns[table], row):
            if typ & T_STRING:
                d[name] = m.s(v) if v else None
            elif v == 0:
                d[name] = None
            else:
                d[name] = v - (0x80000000 if (typ & 0xff) == 4 else 0x8000)
        out.append(d)
    return out


# Custom-action base types (Type & 0x3F) whose source is a File or Directory: their
# path only exists after CostFinalize. Scheduled earlier they fail with error 2731
# "Selection Manager not initialized" (VietTelex 1.0.3: wixl put CleanupUser at
# sequence 1 despite Before="RemoveFiles", so every uninstall failed).
FILE_OR_DIR_SOURCED = {17, 18, 21, 22, 34}
FILE_SOURCED = {17, 18, 21, 22}


def check_custom_action_sequence(m):
    cas = {r['Action']: r for r in table_dicts(m, 'CustomAction')}
    files = {r['File'] for r in table_dicts(m, 'File')}
    dirs = {r['Directory'] for r in table_dicts(m, 'Directory')}
    binaries = {r['Name'] for r in table_dicts(m, 'Binary')}
    sequences = {t: {r['Action']: r['Sequence'] for r in table_dicts(m, t)}
                 for t in ('InstallExecuteSequence', 'InstallUISequence', 'AdminExecuteSequence',
                           'AdvtExecuteSequence') if t in m.columns}
    conditions = {t: {r['Action']: r['Condition'] for r in table_dicts(m, t)} for t in sequences}
    return ca_problems(cas, sequences, files, dirs, binaries, conditions)


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
        bad = first_key_order_problem(keys)
        if bad:
            r, what = bad
            problems.append(f'{table}: row {r} primary key {what} '
                            f'({[m.s(k) if cols[keyidx[j]][2] & T_STRING else k for j, k in enumerate(keys[r])]})')
        if table in STANDARD:
            have = [(n, 'v0' if (t & T_STRING and (t & 0xff) == 0 and n == 'Data') else typestr(t),
                     1 if t & T_KEY else 0) for _, n, t in cols]
            if have != STANDARD[table]:
                problems.append(f'{table}: schema {have} != standard {STANDARD[table]}')
    problems += check_custom_action_sequence(m)
    for p in problems:
        print(f'{path}: {p}', file=sys.stderr)
    if not problems:
        print(f'  {path.rsplit("/", 1)[-1]}: {len(m.tables)} tables well-formed, rows ordered, schemas standard')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(max(main(p) for p in sys.argv[1:]))
