"""Make client/rdr_door_hashes.lua (RDR2's own door hashes, by model) from femga's RDR2 door list.

RedM (spur_core, 25 Nov 2026). RDR2's door system takes only the game's own hash for each door
(_ADD_DOOR_TO_SYSTEM_NEW), and nothing in the game turns a door into its hash. whip made a door's hash from its
position, which on RDR2 registers a door tied to nothing: it took a lock state and the door stayed free. This makes
the table client/doors.lua looks the hash up in: the nearest door of the same model.

    https://github.com/femga/rdr3_discoveries/blob/master/doorHashes/doorhashes.lua   (data only)
    femga's rdr3_discoveries; credit femga. spur_core is based on whip_core by Whippy and WLVF; non-commercial.

Run:  python -I dev/door_hashes_rdr.py <path to doorhashes.lua>   (writes client/rdr_door_hashes.lua)

The file is read as text, never run. Each row is [doorhash] = {doorhash, model hash, model name, x, y, z}. A door
hash can be listed more than once (the same building placed in several spots shares its door hashes), and in a Lua
table literal only the last would be kept, so every row is kept here. The model hash is taken from the name (it
matches femga's column for every row).
"""
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'client', 'rdr_door_hashes.lua')

ROW = re.compile(r'^\s*\[(\d+)\]\s*=\s*\{\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*"([A-Za-z0-9_]+)"\s*,'
                 r'\s*(-?[0-9.eE+-]+)\s*,\s*(-?[0-9.eE+-]+)\s*,\s*(-?[0-9.eE+-]+)\s*\}\s*,?\s*$')


def joaat(s):
    h = 0
    for c in s.lower().encode('ascii'):
        h = (h + c) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h ^= h >> 6
    h = (h + (h << 3)) & 0xFFFFFFFF
    h ^= h >> 11
    return (h + (h << 15)) & 0xFFFFFFFF


def main():
    if len(sys.argv) != 2:
        sys.exit('usage: python -I dev/door_hashes_rdr.py <doorhashes.lua>')
    by_model = defaultdict(set)
    names = {}
    rows = bad = 0
    with open(sys.argv[1], encoding='utf-8') as f:
        for line in f:
            if not line.lstrip().startswith('['):   # the rows; not the comments or the table's own line
                continue
            m = ROW.match(line)
            if not m:
                bad += 1
                continue
            _, door, model_col, name, x, y, z = m.groups()
            model = joaat(name)
            if (int(model_col) & 0xFFFFFFFF) != model:
                bad += 1
                continue
            by_model[model].add((int(door) & 0xFFFFFFFF, round(float(x), 2), round(float(y), 2), round(float(z), 2)))
            names[model] = name
            rows += 1
    if bad:
        sys.exit('%d rows not understood: nothing written' % bad)

    out = [
        '-- RedM (spur_core, 25 Nov 2026): RDR2\'s own door hashes, by model, from femga\'s RDR2 door list',
        '-- (rdr3_discoveries doorHashes/doorhashes.lua; credit femga). Made by dev/door_hashes_rdr.py: don\'t edit by',
        '-- hand. client/doors.lua takes the hash of the nearest door of a door\'s model (RdrDoorHashes.find).',
        '-- [model hash, unsigned] = { door hash, x, y, z, door hash, x, y, z, ... }',
        '-- spur_core is based on whip_core by Whippy and WLVF; non-commercial.',
        'RdrDoorHashes = RdrDoorHashes or {}',
        'RdrDoorHashes.byModel = {',
    ]
    for model in sorted(by_model, key=lambda k: names[k]):
        flat = []
        for door, x, y, z in sorted(by_model[model]):
            flat.append('%d,%.2f,%.2f,%.2f' % (door, x, y, z))
        out.append('    [%d] = { %s },   -- %s' % (model, ', '.join(flat), names[model]))
    out += [
        '}',
        '',
        '--- The game\'s hash for the door of this model nearest (x, y, z), within `range` metres (1.5), and how far.',
        '---@param model number  signed or unsigned',
        '---@return number|nil hash, number|nil metres',
        'function RdrDoorHashes.find(model, x, y, z, range)',
        '    local list = RdrDoorHashes.byModel[(tonumber(model) or 0) & 0xFFFFFFFF]',
        '    if not list then return nil end',
        '    local best, bestSq = nil, (range or 1.5) ^ 2',
        '    for i = 1, #list, 4 do',
        '        local dx, dy, dz = list[i + 1] - x, list[i + 2] - y, list[i + 3] - z',
        '        local dsq = dx * dx + dy * dy + dz * dz',
        '        if dsq < bestSq then best, bestSq = list[i], dsq end',
        '    end',
        '    if best then return best, math.sqrt(bestSq) end',
        'end',
        '',
    ]
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out))
    print('%d rows, %d doors by model and spot, %d models -> %s'
          % (rows, sum(len(v) for v in by_model.values()), len(by_model), os.path.normpath(OUT)))


if __name__ == '__main__':
    main()
