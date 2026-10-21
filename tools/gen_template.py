#!/usr/bin/env python3
"""Generate the Sworn renderer data, the hive card reference and the synthetic conformance goldens.

Two things are generated from this file alone (there is no SVG template file any more):

1. The JSON envelope (`ENVELOPE`), split around its 21 dynamic markers into 22 fixed slices:

       template/blob.hex        the envelope blob, 0x-prefixed hex
       template/offsets.txt     start,length pairs of the 22 fixed slices, decimal, comma-separated
       src/TemplateData.sol     the same blob and offsets as `bytes constant` (read by `Renderer.sol`)

2. The hive card image. `hive_svg` is the normative Python reference of the SVG; every coordinate string
   the Renderer needs (there is no trigonometry onchain) is precomputed here, percent-encoded exactly as
   `percent_encode` would encode it inside the image data URI, and written once to:

       src/HiveData.sol         the point strings, the markup fragments, their start tables and index constants

   The Renderer selects and concatenates those constants; it never computes a coordinate.

The goldens for the eight synthetic cards are written to `test/fixtures/golden_<case>_{preimage,svg,uri}.txt`.
Generated files are byte-exact and carry no terminal newline (the Solidity files end with one LF).
Run from the repository root:

    python3 tools/gen_template.py
    python3 tools/gen_template.py --check

Goldens are for synthetic wallets only (the `0x...c1a1` convention); never a real wallet.
"""

from __future__ import annotations

import argparse
import base64
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BLOB_PATH = Path("template/blob.hex")
OFFSETS_PATH = Path("template/offsets.txt")
SOLIDITY_PATH = Path("src/TemplateData.sol")
HIVE_PATH = Path("src/HiveData.sol")

DESCRIPTION = (
    "Sworn is an ownerless onchain registry of verifiable wallet feats. One card per wallet; every trait is a fact "
    "about the claimant wallet that minted the card, never about the holder. Direct-read traits are read "
    "from the settled WhitelistCurator; chain-proven, panel-attested "
    "and shared-fact traits are attested by the IMD oracle through the Intake and verified in the "
    "registry. Allowlists read hasTrait, never ownerOf. Facts about the wallet that minted it; direct traits "
    "frozen at mint; transferable."
)

FAMILIES = (
    "Spawned",
    "Zero-Shot",
    "Hopper",
    "Bullfrog",
    "Benchmarked",
    "Swarmed",
    "Uptime",
    "Holdout",
    "Final Token",
    "Hotfix",
    "PID",
    "Top Weights",
    "Pretrained",
)

ENVELOPE = (
    '{"name":"Sworn #{ID}",'
    '"description":"' + DESCRIPTION + '",'
    '"image":"data:image/svg+xml,{IMAGE}",'
    '"attributes":['
    '{"trait_type":"Claimant","value":"{CLAIMANT}"},'
    + "".join(
        '{"trait_type":"' + name + '","value":"{F' + str(index + 1) + '}"},' for index, name in enumerate(FAMILIES)
    )
    + '{"trait_type":"community_count","value":{CC}}{COMMUNITY_ATTRIBUTES}],'
    '"traits":[{TRAITS}],'
    '"community":[{COMMUNITY}],'
    '"oracle":[{ORACLE}]}'
)

# Slot order of the envelope: the Renderer fills them in this order (`Renderer._values`).
SLOT_ORDER = ("ID", "IMAGE", "CLAIMANT") + tuple(f"F{i}" for i in range(1, 14)) + (
    "CC",
    "COMMUNITY_ATTRIBUTES",
    "TRAITS",
    "COMMUNITY",
    "ORACLE",
)
SLOTS = len(SLOT_ORDER)
SLICES = SLOTS + 1

MARKER = re.compile(r"[{][A-Z0-9_]+[}]")
ADDRESS = re.compile(r"0x[0-9a-f]{40}")
ENCODE = set(b'%#"& <>?') | set(range(0x80, 0x100))

CATALOG_IDS = (
    101, 201, 202, 301, 302, 303, 401, 402, 403, 404, 501, 502, 503, 601,
    701, 801, 901, 1001, 1101, 1102, 1103, 1104, 1105, 1201, 1301,
)

# ----------------------------------------------------------------------------------------------------------
# The hive card (normative)
# ----------------------------------------------------------------------------------------------------------

H = math.sqrt(3) * 96
SLOT_OFFSETS = (
    (0, 0),
    (0, -H), (144, -H / 2), (144, H / 2), (0, H), (-144, H / 2), (-144, -H / 2),
    (144, -1.5 * H), (288, 0), (144, 1.5 * H), (-144, 1.5 * H), (-288, 0), (-144, -1.5 * H),
)
SLOT_FAMILY = (5, 0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12)  # family (0-based catalog order) in slot s
FAMILY_SLOT = tuple(SLOT_FAMILY.index(i) for i in range(13))
TIERS = (
    (101,), (201, 202), (301, 302, 303), (401, 402, 403, 404), (501, 502, 503), (601,), (701,), (801,), (901,),
    (1001,), (1101, 1102, 1103, 1104, 1105), (1201,), (1301,),
)
TIER_COUNT = (1, 2, 3, 4, 3, 1, 1, 1, 1, 1, 1, 1, 1)  # n per family; Ordinal counts as one level
ORDINAL = 10
RARE_IDS = frozenset((202, 801, 901, 1001, 1101, 1102, 1103, 1104, 1201))
CLASS_COLOUR = ("#00cc33",) * 5 + ("#8ff0a4",) + ("#00ff41",) * 5 + ("#dbfee6", "#8ff0a4")
OFF_COLOUR = "#151515"
RING_RADII = (62, 45, 28)
OPACITIES = (("1.00",), ("0.35", "1.00"), ("0.35", "0.68", "1.00"), ("0.35", "0.57", "0.78", "1.00"))
RADII = (89, 77, 62, 45, 28)
MAX_RINGS_SHOWN = 39
# (family, lv) pairs with 0 < lv < n, in family then level order: the eight HONEY/ABOVE polygon pairs
PARTIAL_PAIRS = tuple((i, lv) for i in range(13) for lv in range(1, TIER_COUNT[i]))

Point = tuple[float, float]


def fmt(v: float) -> str:
    return f"{v:.1f}"


def P(pts: list[Point]) -> str:
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)


def D(pts: list[Point]) -> str:
    return "M" + "L".join(f"{x:.1f} {y:.1f}" for x, y in pts)


def hexagon(x: float, y: float, r: float) -> list[Point]:
    return [(x + r * math.cos(math.radians(60 * k)), y + r * math.sin(math.radians(60 * k))) for k in range(6)]


def family_centre(i: int) -> Point:
    dx, dy = SLOT_OFFSETS[FAMILY_SLOT[i]]
    return (500 + dx, 480 + dy)


def level(i: int, top: int) -> int:
    """lv of family i for its top id: 0 for none, else the 1-based index in the tier list (Ordinal: 1)."""
    if top == 0:
        return 0
    if i == ORDINAL:
        if top not in TIERS[i]:
            raise ValueError(f"{top} is not an Ordinal id")
        return 1
    return TIERS[i].index(top) + 1


def honey_polygons(i: int, lv: int) -> tuple[list[Point], list[Point]]:
    """HONEY (the part of the r=77 cell below the fill line) and ABOVE (the cell flattened at the line)."""
    n = TIER_COUNT[i]
    if not 0 < lv < n:
        raise ValueError("honey polygons exist only for a part-filled family")
    x, y = family_centre(i)
    q = hexagon(x, y, 77)
    yb = max(p[1] for p in q)
    yt = min(p[1] for p in q)
    line = yb - (yb - yt) * lv / n
    honey: list[Point] = []
    for j in range(6):
        x0, y0 = q[j]
        x1, y1 = q[(j + 1) % 6]
        if y0 >= line:
            honey.append((x0, y0))
        if (y0 >= line) != (y1 >= line):
            t = (line - y0) / (y1 - y0)
            honey.append((x0 + t * (x1 - x0), line))
    above = [(px, min(py, line)) for px, py in q]
    return honey, above


def rings_shown(community_count: int, slot: int) -> int:
    shown = min(community_count, MAX_RINGS_SHOWN)
    return sum(1 for d in range(3) if 13 * d + slot < shown)


def path_steps(community_count: int) -> int:
    """The community path length in 64ths of the outer hexagon: 0 up to 39 members, 64 from 8192 on."""
    if community_count <= MAX_RINGS_SHOWN:
        return 0
    if community_count >= 8192:
        return 64
    return min(64, (community_count**8).bit_length() - 41)


V_RING = hexagon(500, 480, 440)
CORNERS = [V_RING[(4 + j) % 6] for j in range(7)]


def path_end(steps: int) -> Point | None:
    """The interpolated end point of the community path for `steps`, or None when it ends on a corner."""
    f = 6 * steps / 64
    j = math.floor(f)
    if f <= j:
        return None
    cx, cy = CORNERS[j]
    nx, ny = CORNERS[j + 1]
    return (cx + (f - j) * (nx - cx), cy + (f - j) * (ny - cy))


def path_points(steps: int) -> list[Point]:
    f = 6 * steps / 64
    j = math.floor(f)
    pts = CORNERS[: j + 1]
    end = path_end(steps)
    return pts + [end] if end is not None else pts


SVG_OPEN = (
    "<svg xmlns='http://www.w3.org/2000/svg' width='1000' height='1000' viewBox='0 0 1000 1000' "
    "font-family='ui-monospace,SFMono-Regular,Menlo,Consolas,DejaVu Sans Mono,monospace'>"
    "<rect width='1000' height='1000' fill='#0a0a0a'/>"
)


def hive_svg(top: tuple[int, ...], community_count: int) -> str:
    """The normative card image: one line, single quotes, numbers as f'{v:.1f}' unless literal."""
    if len(top) != 13:
        raise ValueError("top must hold one entry per family")
    out = [SVG_OPEN]
    for i in range(13):
        x, y = family_centre(i)
        n = TIER_COUNT[i]
        lv = level(i, top[i])
        c = CLASS_COLOUR[i]
        k = rings_shown(community_count, FAMILY_SLOT[i])
        radii = RING_RADII[:k]
        out.append(
            f"<polygon points='{P(hexagon(x, y, 89))}' fill='none' stroke='{c if lv > 0 else OFF_COLOUR}' "
            "stroke-width='4' stroke-linejoin='round'/>"
        )
        zones = "".join(
            f"<polygon points='{P(hexagon(x, y, r))}' fill='{c}' fill-opacity='{o}'/>"
            for r, o in zip((77,) + radii, OPACITIES[k])
        )
        if lv == n:
            out.append(zones)
        elif 0 < lv < n:
            honey, above = honey_polygons(i, lv)
            out.append(f"<clipPath id='a{i}'><polygon points='{P(above)}'/></clipPath>")
            out.append(f"<clipPath id='h{i}'><polygon points='{P(honey)}'/></clipPath>")
            out.append(f"<g clip-path='url(#h{i})'>{zones}</g>")
            for r in radii:
                out.append(
                    f"<polygon points='{P(hexagon(x, y, r))}' fill='none' stroke='#05751f' stroke-width='2' "
                    f"stroke-linejoin='round' clip-path='url(#a{i})'/>"
                )
        if lv > 0 and top[i] in RARE_IDS:
            out.append(f"<circle cx='{fmt(x)}' cy='{fmt(y)}' r='11.0' fill='#ffffff'/>")
        if lv == 0:
            for r in radii:
                out.append(
                    f"<polygon points='{P(hexagon(x, y, r))}' fill='none' stroke='#05751f' stroke-width='3' "
                    "stroke-linejoin='round'/>"
                )
    out.append(
        f"<polygon points='{P(V_RING)}' fill='none' stroke='#0c0c0c' stroke-width='3' stroke-linejoin='round'/>"
    )
    steps = path_steps(community_count)
    if steps > 0:
        out.append(
            f"<path d='{D(path_points(steps))}' fill='none' stroke='#05751f' stroke-width='5' "
            "stroke-linecap='round' stroke-linejoin='round'/>"
        )
    out.append("</svg>")
    return "".join(out)


# ----------------------------------------------------------------------------------------------------------
# The precomputed strings (HiveData.sol)
# ----------------------------------------------------------------------------------------------------------

# Markup fragments, in the order the Renderer meets them. Names become `F_<NAME>` index constants.
FRAGMENTS: tuple[tuple[str, str], ...] = (
    ("SVG_OPEN", SVG_OPEN),
    ("POLYGON_OPEN", "<polygon points='"),
    ("OUTER_STROKE", "' fill='none' stroke='"),
    ("OUTER_CLOSE", "' stroke-width='4' stroke-linejoin='round'/>"),
    ("ZONE_FILL", "' fill='"),
    ("ZONE_OPACITY", "' fill-opacity='"),
    ("CLOSE", "'/>"),
    ("CLIP_ABOVE_OPEN", "<clipPath id='a"),
    ("CLIP_POLYGON", "'><polygon points='"),
    ("CLIP_ABOVE_CLOSE", "'/></clipPath><clipPath id='h"),
    ("CLIP_HONEY_CLOSE", "'/></clipPath><g clip-path='url(#h"),
    ("GROUP_OPEN", ")'>"),
    ("GROUP_CLOSE", "</g>"),
    ("RING_CLIPPED", "' fill='none' stroke='#05751f' stroke-width='2' stroke-linejoin='round' clip-path='url(#a"),
    ("CLIPPED_CLOSE", ")'/>"),
    ("CIRCLE_OPEN", "<circle "),
    ("CIRCLE_CLOSE", " r='11.0' fill='#ffffff'/>"),
    ("RING_EMPTY", "' fill='none' stroke='#05751f' stroke-width='3' stroke-linejoin='round'/>"),
    ("V_CLOSE", "' fill='none' stroke='#0c0c0c' stroke-width='3' stroke-linejoin='round'/>"),
    ("PATH_OPEN", "<path d='M"),
    ("PATH_SEGMENT", "L"),
    ("PATH_CLOSE", "' fill='none' stroke='#05751f' stroke-width='5' stroke-linecap='round' stroke-linejoin='round'/>"),
    ("SVG_CLOSE", "</svg>"),
    ("COLOUR_DIRECT", "#00cc33"),
    ("COLOUR_CHAIN", "#00ff41"),
    ("COLOUR_SHARED", "#dbfee6"),
    ("COLOUR_PANEL", "#8ff0a4"),
    ("COLOUR_OFF", OFF_COLOUR),
    ("OPACITY_100", "1.00"),
    ("OPACITY_35", "0.35"),
    ("OPACITY_68", "0.68"),
    ("OPACITY_57", "0.57"),
    ("OPACITY_78", "0.78"),
)


@dataclass(frozen=True)
class HiveArtifacts:
    points: tuple[str, ...]  # raw (unencoded) point strings, by index
    fragments: tuple[str, ...]
    index_constants: tuple[tuple[str, int], ...]
    solidity: bytes


def hive_point_strings() -> tuple[tuple[str, ...], tuple[tuple[str, int], ...]]:
    """Every coordinate string the Renderer needs, each once, with the index constants that locate them.

    Layout (index = base + offset):
        HEX_BASE     + 5*family + radius index      P(hex(centre, r)) for r in 89, 77, 62, 45, 28   (65 strings)
        HONEY_BASE   + 2*pair, + 2*pair + 1         P(HONEY), P(ABOVE) for the eight part-filled (family, lv) pairs
        V_INDEX                                     P(V), the outer ring
        CORNER_BASE  + j, j in 0..5                 corner V[j] as 'x y' (the path's C[m] is corner (4+m)%6)
        END_BASE     + e                            the interpolated end point as 'x y' for the 62 step counts whose
                                                    path ends between corners (steps 1..31 -> e = steps-1;
                                                    33..63 -> e = steps-2; 32 and 64 end on a corner and have none)
        CENTRE_BASE  + family                       "cx='x' cy='y'" of the family's cell centre
    """
    points: list[str] = []
    constants: list[tuple[str, int]] = []
    constants.append(("HEX_BASE", len(points)))
    for i in range(13):
        x, y = family_centre(i)
        for r in RADII:
            points.append(P(hexagon(x, y, r)))
    constants.append(("HONEY_BASE", len(points)))
    for i, lv in PARTIAL_PAIRS:
        honey, above = honey_polygons(i, lv)
        points.append(P(honey))
        points.append(P(above))
    constants.append(("V_INDEX", len(points)))
    points.append(P(V_RING))
    constants.append(("CORNER_BASE", len(points)))
    for j in range(6):
        points.append(f"{V_RING[j][0]:.1f} {V_RING[j][1]:.1f}")
    constants.append(("END_BASE", len(points)))
    for steps in range(1, 65):
        end = path_end(steps)
        if end is not None:
            points.append(f"{end[0]:.1f} {end[1]:.1f}")
    constants.append(("CENTRE_BASE", len(points)))
    for i in range(13):
        x, y = family_centre(i)
        points.append(f"cx='{fmt(x)}' cy='{fmt(y)}'")
    constants.append(("POINT_COUNT", len(points)))
    if len(set(points)) != len(points):
        raise ValueError("a hive point string would be stored twice")
    return tuple(points), tuple(constants)


def starts_hex(encoded: tuple[str, ...]) -> str:
    """N+1 big-endian uint16 starts (the last is the blob length) as ASCII hex."""
    starts = [0]
    for item in encoded:
        starts.append(starts[-1] + len(item.encode("ascii")))
    if starts[-1] > 0xFFFF:
        raise ValueError("hive blob does not fit uint16 starts")
    return "".join(f"{value:04x}" for value in starts)


def build_hive() -> HiveArtifacts:
    points, constants = hive_point_strings()
    fragments = tuple(text for _, text in FRAGMENTS)
    if len(set(fragments)) != len(fragments):
        raise ValueError("a markup fragment would be stored twice")
    encoded_points = tuple(percent_encode(p.encode("ascii")) for p in points)
    encoded_fragments = tuple(percent_encode(f.encode("ascii")) for f in fragments)
    for item in encoded_points + encoded_fragments:
        if '"' in item or "\\" in item:
            raise ValueError("an encoded hive string cannot be written as a Solidity string literal")
    lines = [
        "// SPDX-License-Identifier: MIT",
        "pragma solidity 0.8.24;",
        "",
        "/// @notice Generated by tools/gen_template.py (`hive_svg` is the normative image); do not edit by hand.",
        "/// @dev    Every coordinate string of the hive card, precomputed and percent-encoded exactly as the",
        "///         image data URI needs it, so the Renderer does no trigonometry: it selects strings by index",
        "///         and concatenates them. POINTS holds the point strings back to back and POINT_STARTS their",
        "///         N+1 big-endian uint16 start offsets (the last one is the blob length) as ASCII hex, so the",
        "///         code data carries no byte the launch's opcode scan forbids (0xf2, 0xf4, 0xff). FRAGMENTS and",
        "///         FRAGMENT_STARTS hold the fixed markup, colours and opacities the same way. Point index =",
        "///         base + offset:",
        "///           HEX_BASE    + 5*family + r   P(hex(centre, radius)) for radius index r: 89, 77, 62, 45, 28",
        "///           HONEY_BASE  + 2*pair (+1)    P(HONEY), P(ABOVE) of the part-filled (family, lv) pairs, in",
        "///                                        family then level order: (1,1) (2,1) (2,2) (3,1) (3,2) (3,3)",
        "///                                        (4,1) (4,2)",
        "///           V_INDEX                      P(V), the outer ring hex(500,480,440)",
        "///           CORNER_BASE + j              V[j] as 'x y'; the community path's C[m] is corner (4+m)%6",
        "///           END_BASE    + e              the path's interpolated end point as 'x y'; steps 1..31 map",
        "///                                        to e = steps-1, 33..63 to e = steps-2; 32 and 64 end on a",
        "///                                        corner and have no entry",
        "///           CENTRE_BASE + family         \"cx='x' cy='y'\" of the family's cell centre (the rare dot)",
        "///         Families are in catalog order (0 = Spawned ... 12 = Pretrained); the slot layout is already",
        "///         folded into the coordinates.",
        "library HiveData {",
    ]
    for name, value in constants:
        lines.append(f"    uint256 internal constant {name} = {value};")
    lines.append(f"    uint256 internal constant FRAGMENT_COUNT = {len(fragments)};")
    for index, (name, _) in enumerate(FRAGMENTS):
        lines.append(f"    uint256 internal constant F_{name} = {index};")
    lines.append("    bytes internal constant POINTS =")
    lines.append(f'        "{"".join(encoded_points)}";')
    lines.append("    bytes internal constant POINT_STARTS =")
    lines.append(f'        "{starts_hex(encoded_points)}";')
    lines.append("    bytes internal constant FRAGMENTS =")
    lines.append(f'        "{"".join(encoded_fragments)}";')
    lines.append("    bytes internal constant FRAGMENT_STARTS =")
    lines.append(f'        "{starts_hex(encoded_fragments)}";')
    lines.append("}")
    solidity = ("\n".join(lines) + "\n").encode("ascii")
    return HiveArtifacts(points, fragments, constants, solidity)


# ----------------------------------------------------------------------------------------------------------
# Cards and goldens
# ----------------------------------------------------------------------------------------------------------

CURATOR = "0xcb0b0531e86a9ac36fa865ca8e3dbccf047fda91"
DEPOSITED = (
    "event Deposited(address indexed contributor, uint256 indexed hour, uint256 amount, uint256 creditedDelta, "
    "uint256 weightAdded, uint256 newWeight, uint256 txCount, uint256 hourTotal, uint256 earlyBps)"
)
B_DEPLOY = 25769870
B_END = 25789604


@dataclass(frozen=True)
class SpecData:
    kind: int
    target: str
    item: str
    arg: str
    fixedArg: str
    fixedVal: int
    sumArg: str
    op: int
    threshold: int
    fromBlock: int
    toBlock: int
    name: str


@dataclass(frozen=True)
class OracleMeta:
    traitId: int
    requestId: str
    oracleRequestId: str
    spec: SpecData


@dataclass(frozen=True)
class CardData:
    tokenId: int
    claimant: str
    top: tuple[int, ...]  # 13 entries, 0 = none
    traits: tuple[int, ...]
    community: tuple[int, ...]
    communityCount: int
    oracle: tuple[OracleMeta, ...] = field(default_factory=tuple)


SPEC_601 = SpecData(6, "0x0000ec93127baa929e58e97dd0095a2bfb38ec1d", "", "", "", 0, "", 0, 3, 25090085, 26199936, "Swarmed")
SPEC_801 = SpecData(1, CURATOR, DEPOSITED, "contributor", "hour", 64, "", 0, 1, B_DEPLOY, B_END, "Holdout")
SPEC_10001 = SpecData(
    1,
    "0x000000000000000000000000000000000000c0de",
    "event Transfer(address indexed from, address indexed to, uint256 value)",
    "to",
    "",
    0,
    "",
    0,
    1,
    B_DEPLOY,
    B_END,
    "Received a token",
)
# A renderer-only case: a name and an item the registry would refuse, to prove the escaping.
SPEC_HOSTILE = SpecData(
    4,
    "0x000000000000000000000000000000000000c0de",
    'function f(address) view returns (uint256)"</text><script>&\x01\\',
    "",
    "",
    0,
    "",
    1,
    1000,
    B_DEPLOY,
    B_END,
    'a"b\\c<d>&e\'',
)

REQUEST_1 = "0x1111111111111111111111111111111111111111111111111111111111111111"
REQUEST_2 = "0x2222222222222222222222222222222222222222222222222222222222222222"
ORACLE_1 = "0x0123456789abcdef0123456789abcdef00000000000000000000000000000000"
ORACLE_2 = "0xfedcba9876543210fedcba987654321000000000000000000000000000000000"


def community_spec(trait_id: int) -> SpecData:
    """A plain T1 community spec for a renderer-only case, named after its id."""
    return SpecData(
        1,
        "0x000000000000000000000000000000000000c0de",
        "event Transfer(address indexed from, address indexed to, uint256 value)",
        "to",
        "",
        0,
        "",
        0,
        1,
        B_DEPLOY,
        B_END,
        f"Community spec {trait_id}",
    )


def community_metas(ids: tuple[int, ...]) -> tuple[OracleMeta, ...]:
    return tuple(OracleMeta(i, REQUEST_1, ORACLE_1, community_spec(i)) for i in ids)


def cumulative_traits(top: tuple[int, ...]) -> tuple[int, ...]:
    """Every catalog id at or below the top of each family (tiers are monotone; Ordinal is the one id)."""
    out: list[int] = []
    for i, t in enumerate(top):
        if t == 0:
            continue
        out.extend((t,) if i == ORDINAL else TIERS[i][: TIERS[i].index(t) + 1])
    return tuple(out)


THIRTY_TWO = tuple(range(10001, 10033))
HONEY_TOP = (101, 201, 302, 403, 502, 601, 701, 801, 901, 1001, 1101, 1201, 1301)

CASES = {
    # a member with direct-read traits only: hour 0, five deposits, 1 ETH high water, 1000 points
    "synthetic_direct": CardData(
        tokenId=1,
        claimant="0x000000000000000000000000000000000000c1a1",
        top=(101, 202, 302, 401, 501, 0, 0, 0, 0, 0, 0, 0, 0),
        traits=(101, 201, 202, 301, 302, 401, 501),
        community=(),
        communityCount=0,
    ),
    # a non-member IDMD holder with one verified catalog chain trait and one verified community spec
    "synthetic_oracle": CardData(
        tokenId=2,
        claimant="0x00000000000000000000000000000000000ac1a1",
        top=(0, 0, 0, 0, 0, 601, 0, 801, 0, 0, 0, 0, 0),
        traits=(601, 801),
        community=(10001,),
        communityCount=1,
        oracle=(OracleMeta(601, "0x" + "33" * 32, "0x" + "44" * 16 + "00" * 16, SPEC_601), OracleMeta(801, REQUEST_1, ORACLE_1, SPEC_801), OracleMeta(10001, REQUEST_2, ORACLE_2, SPEC_10001)),
    ),
    # the widest values the renderer can meet, through the renderer alone
    "synthetic_width": CardData(
        tokenId=2**256 - 1,
        claimant="0xffffffffffffffffffffffffffffffffffffc1a1",
        top=(101, 202, 303, 404, 503, 601, 701, 801, 901, 1001, 1101, 1201, 1301),
        traits=CATALOG_IDS,
        community=THIRTY_TWO,
        communityCount=40,
        oracle=tuple(OracleMeta(i, REQUEST_1, ORACLE_1, SPEC_HOSTILE) for i in THIRTY_TWO),
    ),
    # a fresh member: one cell lit, no rings, no path
    "synthetic_newcomer": CardData(
        tokenId=3,
        claimant="0x000000000000000000000000000000000003c1a1",
        top=(101, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        traits=(101,),
        community=(),
        communityCount=0,
    ),
    # no catalog trait at all, five community specs: dark cells with ring outlines only
    "synthetic_outsider": CardData(
        tokenId=4,
        claimant="0x000000000000000000000000000000000004c1a1",
        top=(0,) * 13,
        traits=(),
        community=tuple(range(10001, 10006)),
        communityCount=5,
        oracle=community_metas(tuple(range(10001, 10006))),
    ),
    # every multi-tier family part-filled, three rings in every cell, no path (count 39)
    "synthetic_honey": CardData(
        tokenId=5,
        claimant="0x000000000000000000000000000000000005c1a1",
        top=HONEY_TOP,
        traits=cumulative_traits(HONEY_TOP),
        community=THIRTY_TWO,
        communityCount=39,
        oracle=community_metas(THIRTY_TWO),
    ),
    # two lit cells, three rings everywhere, a nine-step community path
    "synthetic_collector": CardData(
        tokenId=6,
        claimant="0x000000000000000000000000000000000006c1a1",
        top=(101, 0, 301, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        traits=(101, 301),
        community=THIRTY_TWO,
        communityCount=70,
        oracle=community_metas(THIRTY_TWO),
    ),
    # every family at its top tier (Ordinal 1101), every rare dot, a 58-step path
    "synthetic_fullhouse": CardData(
        tokenId=7,
        claimant="0x000000000000000000000000000000000007c1a1",
        top=(101, 202, 303, 404, 503, 601, 701, 801, 901, 1001, 1101, 1201, 1301),
        traits=CATALOG_IDS,
        community=THIRTY_TWO,
        communityCount=5000,
        oracle=community_metas(THIRTY_TWO),
    ),
}

GENERATED_PATHS = tuple(
    Path(f"test/fixtures/golden_{case}_{kind}.txt") for case in CASES for kind in ("preimage", "svg", "uri")
)


def percent_encode(raw: bytes) -> str:
    return "".join(f"%{byte:02X}" if byte in ENCODE else chr(byte) for byte in raw)


def percent_decode(encoded: str) -> bytes:
    raw = encoded.encode("ascii")
    out = bytearray()
    index = 0
    while index < len(raw):
        if raw[index] == ord("%"):
            if index + 2 >= len(raw):
                raise ValueError("truncated percent escape")
            pair = raw[index + 1 : index + 3]
            if not re.fullmatch(rb"[0-9A-F]{2}", pair):
                raise ValueError("percent escapes must use uppercase hexadecimal")
            out.append(int(pair, 16))
            index += 3
        else:
            out.append(raw[index])
            index += 1
    return bytes(out)


def marker_names(text: str) -> tuple[str, ...]:
    return tuple(match.group()[1:-1] for match in MARKER.finditer(text))


@dataclass(frozen=True)
class TemplateArtifacts:
    parts: tuple[str, ...]
    blob: bytes
    blob_hex: bytes
    offsets: tuple[int, ...]
    offsets_text: bytes
    solidity: bytes


def build_template() -> TemplateArtifacts:
    names = marker_names(ENVELOPE)
    if names != SLOT_ORDER:
        raise ValueError(f"slot order changed: got {names}, expected {SLOT_ORDER}")

    parts = tuple(MARKER.split(ENVELOPE))
    if len(parts) != SLICES:
        raise ValueError(f"expected {SLICES} fixed slices, got {len(parts)}")
    blob = "".join(parts).encode("ascii")
    offsets: list[int] = []
    cursor = 0
    for part in parts:
        size = len(part.encode("ascii"))
        offsets.extend((cursor, size))
        cursor += size
    if cursor != len(blob) or len(blob) > 20_000:
        raise ValueError("template offsets do not cover a deployable blob")
    if any(value > 0xFFFF for value in offsets):
        raise ValueError("template offset does not fit uint16")

    offsets_tuple = tuple(offsets)
    offsets_text = ",".join(str(value) for value in offsets_tuple).encode("ascii")
    blob_hex = b"0x" + blob.hex().encode("ascii")
    packed = b"".join(value.to_bytes(2, "big") for value in offsets_tuple)
    solidity = (
        "// SPDX-License-Identifier: MIT\n"
        "pragma solidity 0.8.24;\n\n"
        "/// @notice Generated by tools/gen_template.py from its JSON envelope; do not edit by hand.\n"
        "/// @dev    The metadata envelope as a compile-time constant (solc emits a codecopy) and the\n"
        "///         start,length pairs of its fixed slices as big-endian uint16, written as ASCII hex so the\n"
        "///         code data carries no byte the launch's opcode scan forbids (0xf2, 0xf4, 0xff). The image\n"
        "///         slot takes the whole percent-encoded hive SVG, built from `HiveData`.\n"
        "library TemplateData {\n"
        f"    uint256 internal constant SLOTS = {SLOTS};\n"
        f"    uint256 internal constant SLICES = {SLICES};\n"
        "    bytes internal constant TEMPLATE =\n"
        f'        hex"{blob.hex()}";\n'
        "    bytes internal constant OFFSETS =\n"
        f'        "{packed.hex()}";\n'
        "}\n"
    ).encode("ascii")
    return TemplateArtifacts(parts, blob, blob_hex, offsets_tuple, offsets_text, solidity)


def unsigned(value: int) -> str:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"expected unsigned integer, got {value!r}")
    return str(value)


def hex32(value: str) -> str:
    if not re.fullmatch(r"0x[0-9a-f]{64}", value):
        raise ValueError(f"expected a 32-byte lowercase hex word, got {value!r}")
    return value


def escape_json(raw: str) -> str:
    """Mirror of Renderer.escapeJson: `"` and `\\` escaped; control bytes, `<`, `>`, `&` as \\u00xx."""
    out = []
    for byte in raw.encode("latin-1"):
        if byte in (0x22, 0x5C):
            out.append("\\" + chr(byte))
        elif byte < 0x20 or byte in (0x3C, 0x3E, 0x26, 0x27):
            out.append(f"\\u00{byte:02x}")
        else:
            out.append(chr(byte))
    return "".join(out)


def oracle_entry(meta: OracleMeta) -> str:
    s = meta.spec
    return (
        '{"traitId":' + unsigned(meta.traitId)
        + ',"template":"T' + unsigned(s.kind)
        + '","evidence":"' + ("panel" if s.kind in (5, 6) else "chain")
        + '","fromBlock":' + unsigned(s.fromBlock)
        + ',"toBlock":' + unsigned(s.toBlock)
        + ',"minPanelSize":' + ("11" if s.kind in (3, 5, 6) else "5")
        + ',"minQuorum":' + ("7" if s.kind in (3, 5, 6) else "3")
        + ',"requestId":"' + hex32(meta.requestId)
        + '","oracleRequestId":"' + hex32(meta.oracleRequestId)
        + '","target":"' + s.target
        + '","name":"' + escape_json(s.name)
        + '"}'
    )


def card_values(data: CardData) -> tuple[str, ...]:
    if ADDRESS.fullmatch(data.claimant) is None:
        raise ValueError("claimant must be a full lowercase hexadecimal address")
    if not data.claimant.endswith("c1a1"):
        raise ValueError("goldens are for synthetic wallets only (0x...c1a1)")
    if len(data.top) != 13:
        raise ValueError("top must hold one entry per family")
    values = {
        "ID": unsigned(data.tokenId),
        "IMAGE": percent_encode(hive_svg(data.top, data.communityCount).encode("ascii")),
        "CLAIMANT": data.claimant,
        "CC": unsigned(data.communityCount),
        "TRAITS": ",".join(unsigned(v) for v in data.traits),
        "COMMUNITY": ",".join(unsigned(v) for v in data.community),
        "COMMUNITY_ATTRIBUTES": "".join(
            ',{"trait_type":"Community ' + unsigned(trait_id) + '","value":"'
            + escape_json(next((m.spec.name for m in data.oracle if m.traitId == trait_id), "")) + '"}'
            for trait_id in data.community
        ),
        "ORACLE": ",".join(oracle_entry(m) for m in data.oracle),
    }
    for index, top in enumerate(data.top):
        values[f"F{index + 1}"] = "none" if top == 0 else unsigned(top)
    return tuple(values[name] for name in SLOT_ORDER)


def render_case(template: TemplateArtifacts, data: CardData) -> tuple[bytes, bytes, bytes]:
    values = card_values(data)
    preimage = "".join(
        template.parts[index] + (values[index] if index < len(values) else "") for index in range(len(template.parts))
    ).encode("ascii")
    if b"\n" in preimage or b"\r" in preimage:
        raise ValueError("rendered preimage contains forbidden whitespace")

    metadata = json.loads(preimage)
    if list(metadata) != ["name", "description", "image", "attributes", "traits", "community", "oracle"]:
        raise ValueError("top-level JSON keys changed")
    if metadata["description"] != DESCRIPTION:
        raise ValueError("approved description changed")
    if len(metadata["attributes"]) != 15 + len(data.community):
        raise ValueError("metadata must contain fifteen base attributes plus the shown community traits")

    image_prefix = "data:image/svg+xml,"
    image = metadata["image"]
    if not image.startswith(image_prefix):
        raise ValueError("image data URI prefix changed")
    svg = percent_decode(image[len(image_prefix) :])
    if svg != hive_svg(data.top, data.communityCount).encode("ascii"):
        raise ValueError("image round trip changed the SVG")
    uri = b"data:application/json;base64," + base64.b64encode(preimage)
    return preimage, svg, uri


def build_outputs(root: Path = ROOT) -> dict[Path, bytes]:
    del root  # every output is derived from this file alone
    template = build_template()
    hive = build_hive()
    outputs = {
        BLOB_PATH: template.blob_hex,
        OFFSETS_PATH: template.offsets_text,
        SOLIDITY_PATH: template.solidity,
        HIVE_PATH: hive.solidity,
    }
    for case, data in CASES.items():
        preimage, svg, uri = render_case(template, data)
        outputs[Path(f"test/fixtures/golden_{case}_preimage.txt")] = preimage
        outputs[Path(f"test/fixtures/golden_{case}_svg.txt")] = svg
        outputs[Path(f"test/fixtures/golden_{case}_uri.txt")] = uri
    return outputs


def check_outputs(outputs: dict[Path, bytes], root: Path = ROOT) -> int:
    failures: list[str] = []
    for relative, expected in outputs.items():
        path = root / relative
        if not path.is_file():
            failures.append(f"missing {relative}")
        elif path.read_bytes() != expected:
            failures.append(f"differs {relative}")
    if failures:
        print("\n".join(failures))
        return 1
    print(f"checked {len(outputs)} generated artifacts")
    return 0


def write_outputs(outputs: dict[Path, bytes], root: Path = ROOT) -> None:
    for relative, data in outputs.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(f"generated {len(outputs)} artifacts")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="compare generated bytes without writing")
    args = parser.parse_args()
    try:
        outputs = build_outputs()
        if args.check:
            return check_outputs(outputs)
        write_outputs(outputs)
        return 0
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"generation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
