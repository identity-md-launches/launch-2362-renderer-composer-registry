#!/usr/bin/env python3
"""Export the pinned build's three implementation ABIs without rewriting deployment evidence."""
import argparse
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
for name in ('Registry', 'Composer', 'Renderer'):
    artifact = json.loads((root / f'out/{name}.sol/{name}.json').read_text())
    data = json.dumps(artifact['abi'], indent=2) + '\n'
    for folder in ('docs/abi', 'web/src/abi', 'web/public/abi'):
        path = root / folder / f'{name}.json'
        if args.check:
            assert path.read_text() == data, f'{path.relative_to(root)} differs from the build'
        else:
            path.write_text(data)
print('Three implementation ABIs and both web copies match the compiler artifacts.')
