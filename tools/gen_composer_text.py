#!/usr/bin/env python3
"""Reproduce Composer's lossless static text table. No third-party packages.

The plain ASCII strings in templates/composer-text.json are in stable table order.
~A through ~P interpolate the corresponding value in Composer._render; this applies
only to static templates, never recursively to user input. Byte offsets in _text
are checked as part of --check. Append new strings instead of reordering entries.
"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def compress(data):
    out = bytearray()
    i = 0
    while i < len(data):
        best = distance = 0
        pos = data.rfind(data[i:i + 5], max(0, i - 16383), i) if len(data) - i >= 5 else -1
        while pos >= 0:
            length = 5
            while length < 127 and i + length < len(data) and data[pos + length] == data[i + length]:
                length += 1
            if length > best:
                best, distance = length, i - pos
            pos = data.rfind(data[i:i + 5], max(0, i - 16383), pos)
        if best >= 5:
            out.extend((128, distance // 128, distance % 128, best))
            i += best
        else:
            out.append(data[i])
            i += 1
    return bytes(out)


def expand(packed):
    out = bytearray()
    i = 0
    while i < len(packed):
        char = packed[i]
        i += 1
        if char < 128:
            out.append(char)
        else:
            distance = packed[i] * 128 + packed[i + 1]
            length = packed[i + 2]
            i += 3
            assert 0 < distance <= len(out)
            for _ in range(length):
                out.append(out[-distance])
    return bytes(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    strings = json.loads((ROOT / 'templates/composer-text.json').read_text())
    assert len(strings) == len(set(strings)), 'table entries must be unique'
    data = b''.join(text.encode('ascii') for text in strings)
    packed = compress(data)
    assert expand(packed) == data
    path = ROOT / 'src/Composer.sol'
    source = path.read_text()
    offsets, offset = set(), 0
    for text in strings:
        offsets.add((offset, len(text)))
        offset += len(text)
    used = {(int(a), int(b)) for a, b in re.findall(r'_text\(text, (\d+), (\d+)\)', source)}
    assert used == offsets, 'text table offsets differ from Composer call sites'
    pattern = r'(bytes internal constant TEXT\s*=\s*hex")[0-9a-f]+(";)'
    assert len(re.findall(pattern, source)) == 1, 'expected one generated TEXT constant'
    expected = re.sub(pattern, lambda m: m.group(1) + packed.hex() + m.group(2), source)
    assert f'out = new bytes({len(data)});' in source, 'expanded buffer length differs'
    if args.check:
        assert expected == source, 'run tools/gen_composer_text.py to regenerate TEXT'
    else:
        path.write_text(expected)
    print(f'Composer text: {len(strings)} strings, {len(data)} ASCII bytes, {len(packed)} packed bytes; round-trip and offsets OK')


if __name__ == '__main__':
    main()
