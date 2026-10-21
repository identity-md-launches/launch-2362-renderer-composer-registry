from __future__ import annotations

import io
import json
import math
import re
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

try:
    from tools import gen_template as gen
except ModuleNotFoundError:  # Allows `python3 tools/test_gen_template.py` too.
    import gen_template as gen


POLYGON = re.compile(r"<polygon points='([^']*)'([^>]*)/>")
NUMBER = re.compile(r"-?\d+\.\d")


class GeneratorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.template = gen.build_template()
        self.hive = gen.build_hive()

    def test_template_structure(self) -> None:
        self.assertEqual(gen.SLOTS, 21)
        self.assertEqual(len(self.template.parts), gen.SLICES)
        self.assertEqual(len(self.template.offsets), gen.SLICES * 2)
        self.assertEqual(gen.marker_names(gen.ENVELOPE), gen.SLOT_ORDER)
        self.assertEqual(gen.SLOT_ORDER[:3], ("ID", "IMAGE", "CLAIMANT"))
        self.assertEqual(gen.SLOT_ORDER[3:16], tuple(f"F{i}" for i in range(1, 14)))
        cursor = 0
        for i in range(gen.SLICES):
            self.assertEqual(self.template.offsets[2 * i], cursor)
            cursor += self.template.offsets[2 * i + 1]
        self.assertEqual(cursor, len(self.template.blob))
        self.assertIn(b"bytes internal constant TEMPLATE", self.template.solidity)
        self.assertNotIn(b"<svg", self.template.blob, "the envelope holds no SVG; the image is one slot")

    def test_percent_encoding_is_exact(self) -> None:
        raw = b'%#"& <>?AZ\x7f\xc2\xb7'
        encoded = "%25%23%22%26%20%3C%3E%3FAZ\x7f%C2%B7"
        self.assertEqual(gen.percent_encode(raw), encoded)
        self.assertEqual(gen.percent_decode(encoded), raw)

    def test_escape_json_neutralises_markup(self) -> None:
        self.assertEqual(gen.escape_json('a"b\\c<d>&e\x01'), 'a\\"b\\\\c\\u003cd\\u003e\\u0026e\\u0001')
        self.assertEqual(gen.escape_json("plain Name 1.0-x"), "plain Name 1.0-x")

    # ------------------------------------------------------------------ the hive geometry

    def test_path_steps_table(self) -> None:
        counts = (32, 39, 40, 53, 70, 100, 200, 1000, 5000, 8191, 8192, 65535)
        expected = (0, 0, 2, 5, 9, 13, 21, 39, 58, 63, 64, 64)
        self.assertEqual(tuple(gen.path_steps(c) for c in counts), expected)
        self.assertEqual(gen.path_steps(0), 0)
        self.assertEqual(gen.path_steps(2**256 - 1), 64)
        # the eighth power, never an xor: 40 ^ 8 would be 32 and give no path at all
        self.assertEqual((40**8).bit_length() - 41, 2)

    def test_slot_layout_and_levels(self) -> None:
        self.assertEqual(gen.family_centre(5), (500.0, 480.0), "Swarmed sits in the centre")
        self.assertEqual(gen.family_centre(0), (500.0, 480.0 - gen.H), "Spawned sits above it")
        self.assertEqual(gen.family_centre(12), (500.0 - 144, 480.0 - 1.5 * gen.H))
        self.assertEqual(gen.H, math.sqrt(3) * 96)
        self.assertEqual([gen.level(i, 0) for i in range(13)], [0] * 13)
        self.assertEqual(gen.level(3, 403), 3)
        self.assertEqual(gen.level(4, 503), 3)
        self.assertEqual(gen.level(10, 1105), 1)
        self.assertEqual(gen.level(10, 1101), 1)
        with self.assertRaises(ValueError):
            gen.level(0, 202)
        with self.assertRaises(ValueError):
            gen.level(10, 1106)
        self.assertEqual(gen.PARTIAL_PAIRS, ((1, 1), (2, 1), (2, 2), (3, 1), (3, 2), (3, 3), (4, 1), (4, 2)))
        self.assertEqual([gen.rings_shown(0, s) for s in range(13)], [0] * 13)
        self.assertEqual([gen.rings_shown(5, s) for s in range(13)], [1] * 5 + [0] * 8)
        self.assertEqual([gen.rings_shown(14, s) for s in range(13)], [2] + [1] * 12)
        self.assertEqual([gen.rings_shown(39, s) for s in range(13)], [3] * 13)
        self.assertEqual([gen.rings_shown(5000, s) for s in range(13)], [3] * 13)

    def test_honey_polygons_follow_the_fill_line(self) -> None:
        for i, lv in gen.PARTIAL_PAIRS:
            with self.subTest(family=i, lv=lv):
                honey, above = gen.honey_polygons(i, lv)
                x, y = gen.family_centre(i)
                q = gen.hexagon(x, y, 77)
                yb, yt = max(p[1] for p in q), min(p[1] for p in q)
                line = yb - (yb - yt) * lv / gen.TIER_COUNT[i]
                self.assertEqual(len(above), 6)
                self.assertTrue(all(py <= line + 1e-9 for _, py in above))
                self.assertTrue(all(py >= line - 1e-9 for _, py in honey))
                self.assertEqual(sum(1 for _, py in honey if abs(py - line) < 1e-9), 2 + sum(1 for _, py in q if py == line))
                self.assertEqual(len(honey), 2 + sum(1 for _, py in q if py >= line))
        with self.assertRaises(ValueError):
            gen.honey_polygons(0, 1)
        with self.assertRaises(ValueError):
            gen.honey_polygons(3, 4)

    def test_path_points(self) -> None:
        self.assertEqual(gen.CORNERS[0], gen.V_RING[4])
        self.assertEqual(gen.CORNERS[6], gen.V_RING[4])
        self.assertIsNone(gen.path_end(32))
        self.assertIsNone(gen.path_end(64))
        self.assertEqual(len(gen.path_points(64)), 7, "a full path closes on its first corner")
        self.assertEqual(len(gen.path_points(32)), 4)
        self.assertEqual(len(gen.path_points(1)), 2)
        self.assertEqual(sum(1 for s in range(1, 65) if gen.path_end(s) is not None), 62)
        x0, y0 = gen.CORNERS[0]
        x1, y1 = gen.CORNERS[1]
        ex, ey = gen.path_end(1)
        self.assertAlmostEqual(ex, x0 + (6 / 64) * (x1 - x0))
        self.assertAlmostEqual(ey, y0 + (6 / 64) * (y1 - y0))
        self.assertEqual(gen.D([(1.0, 2.0), (3.5, 4.25)]), "M1.0 2.0L3.5 4.2")
        self.assertEqual(gen.P([(1.0, 2.0), (3.5, 4.25)]), "1.0,2.0 3.5,4.2")

    # ------------------------------------------------------------------ the normative SVG

    def test_hive_svg_element_order_for_each_state(self) -> None:
        top = (101, 201, 302, 0, 503, 0, 0, 801, 0, 0, 1105, 0, 0)
        svg = gen.hive_svg(top, 14)
        self.assertTrue(svg.startswith(gen.SVG_OPEN))
        self.assertTrue(svg.endswith("'/></svg>"))
        self.assertNotIn("<text", svg)
        self.assertNotIn("\n", svg)
        self.assertNotIn('"', svg)
        # 13 outlines; per family: full cells 77 + k rings, part-filled cells 2 clips + 77 + k + k clipped rings,
        # empty cells k outlines (the centre slot has k = 2 at count 14, every other slot 1); then V
        self.assertEqual(svg.count("<polygon points='"), 13 + (2 + 5 + 5 + 1 + 2 + 2 + 1 + 2 + 1 + 1 + 2 + 1 + 1) + 1)
        # the first cell (Spawned, lv 1 of 1, two rings in slot 1 at count 14 -> one ring) is full: no clip paths
        self.assertNotIn("id='a0'", svg)
        self.assertIn("id='a1'", svg)  # Zero-Shot at 201 of 2 is part-filled
        self.assertIn("id='h2'", svg)  # Hopper at 302 of 3
        self.assertNotIn("id='a4'", svg)  # Benchmarked at its top
        self.assertEqual(svg.count("<circle"), 1, "only 801 is rare here; 1105 is not")
        self.assertIn("stroke='#151515'", svg)  # dark outlines for the empty families
        self.assertNotIn("<path", svg, "no path up to 39 members")
        for number in NUMBER.findall(svg):
            self.assertRegex(number, r"^\d+\.\d$")
        fill_line = gen.hive_svg(top, 40)
        self.assertIn("<path d='M", fill_line)
        self.assertEqual(fill_line.count("L"), 1 + fill_line.count("Lr"), "two steps end on the first edge")

    def test_hive_svg_rare_dot_only_at_the_top_tier(self) -> None:
        for i, ids in enumerate(gen.TIERS):
            for top_id in ids:
                top = [0] * 13
                top[i] = top_id
                svg = gen.hive_svg(tuple(top), 0)
                self.assertEqual(svg.count("<circle"), 1 if top_id in gen.RARE_IDS else 0, top_id)
        self.assertEqual(gen.hive_svg((0,) * 13, 0).count("<circle"), 0)

    def test_hive_svg_opacities_by_ring_count(self) -> None:
        top = (0,) * 5 + (601,) + (0,) * 7  # Swarmed, the centre slot, lit
        for count, expected in ((0, ("1.00",)), (1, ("0.35", "1.00")), (14, ("0.35", "0.68", "1.00")), (27, ("0.35", "0.57", "0.78", "1.00"))):
            svg = gen.hive_svg(top, count)
            self.assertEqual(tuple(re.findall(r"fill-opacity='([^']*)'", svg)), expected, count)

    def test_hive_strings_are_unique_and_each_used_string_is_precomputed(self) -> None:
        points = self.hive.points
        constants = dict(self.hive.index_constants)
        self.assertEqual(constants["HEX_BASE"], 0)
        self.assertEqual(constants["HONEY_BASE"], 65)
        self.assertEqual(constants["V_INDEX"], 81)
        self.assertEqual(constants["CORNER_BASE"], 82)
        self.assertEqual(constants["END_BASE"], 88)
        self.assertEqual(constants["CENTRE_BASE"], 150)
        self.assertEqual(constants["POINT_COUNT"], 163)
        self.assertEqual(len(points), 163)
        self.assertEqual(len(set(points)), 163)
        self.assertEqual(len(set(self.hive.fragments)), len(self.hive.fragments))
        # every polygon of every reachable card state is one of the precomputed strings
        precomputed = set(points)
        for top in gen.CASES["synthetic_honey"].top, gen.CASES["synthetic_fullhouse"].top, (0,) * 13:
            for count in (0, 5, 14, 39, 40, 8192):
                svg = gen.hive_svg(top, count)
                for pts, _ in POLYGON.findall(svg):
                    self.assertIn(pts, precomputed)
                for match in re.finditer(r"<circle (cx='[^']*' cy='[^']*')", svg):
                    self.assertIn(match.group(1), precomputed)
                path = re.search(r"<path d='M([^']*)'", svg)
                if path:
                    for point in path.group(1).split("L"):
                        self.assertIn(point, precomputed)
        for steps in range(1, 65):
            end = gen.path_end(steps)
            if end is not None:
                self.assertEqual(points[88 + (steps - 2 if steps > 32 else steps - 1)], f"{end[0]:.1f} {end[1]:.1f}")
        for j in range(6):
            self.assertEqual(points[82 + j], f"{gen.V_RING[j][0]:.1f} {gen.V_RING[j][1]:.1f}")
        for p, (i, lv) in enumerate(gen.PARTIAL_PAIRS):
            honey, above = gen.honey_polygons(i, lv)
            self.assertEqual(points[65 + 2 * p], gen.P(honey))
            self.assertEqual(points[66 + 2 * p], gen.P(above))

    def test_hive_solidity_is_percent_encoded_and_indexable(self) -> None:
        text = self.hive.solidity.decode("ascii")
        self.assertIn("library HiveData {", text)
        for name, value in self.hive.index_constants:
            self.assertIn(f"uint256 internal constant {name} = {value};", text)
        for index, (name, _) in enumerate(gen.FRAGMENTS):
            self.assertIn(f"uint256 internal constant F_{name} = {index};", text)
        points_blob = re.search(r'POINTS =\n        "([^"]*)";', text).group(1)
        starts = re.search(r'POINT_STARTS =\n        "([^"]*)";', text).group(1)
        self.assertNotIn(" ", points_blob)
        self.assertNotIn("<", points_blob)
        self.assertEqual(len(starts), 4 * 164)
        cuts = [int(starts[i : i + 4], 16) for i in range(0, len(starts), 4)]
        self.assertEqual(cuts[-1], len(points_blob))
        for i, point in enumerate(self.hive.points):
            self.assertEqual(gen.percent_decode(points_blob[cuts[i] : cuts[i + 1]]), point.encode("ascii"))
        fragments_blob = re.search(r'FRAGMENTS =\n        "([^"]*)";', text).group(1)
        fstarts = re.search(r'FRAGMENT_STARTS =\n        "([^"]*)";', text).group(1)
        fcuts = [int(fstarts[i : i + 4], 16) for i in range(0, len(fstarts), 4)]
        for i, fragment in enumerate(self.hive.fragments):
            self.assertEqual(gen.percent_decode(fragments_blob[fcuts[i] : fcuts[i + 1]]), fragment.encode("ascii"))
        # a concatenation of fragments and points reproduces a golden image exactly
        svg = gen.hive_svg(gen.CASES["synthetic_newcomer"].top, 0)
        encoded = gen.percent_encode(svg.encode("ascii"))
        for piece in (points_blob[cuts[0] : cuts[1]], fragments_blob[fcuts[0] : fcuts[1]]):
            self.assertIn(piece, encoded)

    # ------------------------------------------------------------------ the goldens

    def test_synthetic_goldens_are_valid_json_and_svg(self) -> None:
        for name, data in gen.CASES.items():
            with self.subTest(case=name):
                preimage, svg, uri = gen.render_case(self.template, data)
                metadata = json.loads(preimage)
                self.assertEqual(metadata["name"], f"Sworn #{data.tokenId}")
                self.assertEqual(metadata["attributes"][0]["value"], data.claimant)
                self.assertEqual(metadata["traits"], list(data.traits))
                self.assertEqual(metadata["community"], list(data.community))
                self.assertEqual(len(metadata["oracle"]), len(data.oracle))
                self.assertEqual(len(metadata["attributes"]), 15 + len(data.community))
                self.assertEqual(metadata["attributes"][14], {"trait_type": "community_count", "value": data.communityCount})
                for index, top in enumerate(data.top):
                    self.assertEqual(metadata["attributes"][1 + index]["value"], "none" if top == 0 else str(top))
                for index, trait_id in enumerate(data.community):
                    cname = next(m.spec.name for m in data.oracle if m.traitId == trait_id)
                    self.assertEqual(metadata["attributes"][15 + index], {"trait_type": f"Community {trait_id}", "value": cname})
                for meta in metadata["oracle"]:
                    self.assertEqual(meta["minPanelSize"], 11 if meta["template"] in ("T3", "T5", "T6") else 5)
                    self.assertEqual(meta["minQuorum"], 7 if meta["template"] in ("T3", "T5", "T6") else 3)
                    self.assertNotIn("item", meta, "the shrunk oracle record carries no spec body")
                    self.assertIn("name", meta)
                self.assertEqual(svg, gen.hive_svg(data.top, data.communityCount).encode("ascii"))
                self.assertTrue(svg.startswith(b"<svg ") and svg.endswith(b"</svg>"))
                self.assertNotIn(data.claimant.encode(), svg, "the hive shows no address")
                self.assertEqual(metadata["image"], "data:image/svg+xml," + gen.percent_encode(svg))
                self.assertEqual(uri, b"data:application/json;base64," + gen.base64.b64encode(preimage))
        width = json.loads(gen.render_case(self.template, gen.CASES["synthetic_width"])[0])
        self.assertEqual(width["oracle"][0]["name"], 'a"b\\c<d>&e\'')
        self.assertNotIn(b"<script>", gen.render_case(self.template, gen.CASES["synthetic_width"])[0])

    def test_golden_cases_cover_the_requested_states(self) -> None:
        cases = gen.CASES
        self.assertEqual(
            list(cases),
            [
                "synthetic_direct",
                "synthetic_oracle",
                "synthetic_width",
                "synthetic_newcomer",
                "synthetic_outsider",
                "synthetic_honey",
                "synthetic_collector",
                "synthetic_fullhouse",
            ],
        )
        self.assertEqual((cases["synthetic_newcomer"].tokenId, cases["synthetic_newcomer"].traits), (3, (101,)))
        self.assertEqual(cases["synthetic_outsider"].tokenId, 4)
        self.assertEqual(cases["synthetic_outsider"].community, tuple(range(10001, 10006)))
        self.assertEqual(cases["synthetic_honey"].tokenId, 5)
        self.assertEqual(cases["synthetic_honey"].communityCount, 39)
        self.assertEqual(cases["synthetic_collector"].tokenId, 6)
        self.assertEqual(cases["synthetic_collector"].communityCount, 70)
        self.assertEqual(cases["synthetic_fullhouse"].tokenId, 7)
        self.assertEqual(cases["synthetic_fullhouse"].communityCount, 5000)
        self.assertEqual(cases["synthetic_fullhouse"].traits, gen.CATALOG_IDS)
        honey = gen.hive_svg(cases["synthetic_honey"].top, 39)
        self.assertEqual(honey.count("<clipPath id='a"), 4, "every multi-tier family is part-filled")
        self.assertEqual(honey.count("fill-opacity='0.57'"), 13, "three rings in every cell")
        self.assertNotIn("<path", honey)
        self.assertEqual(gen.cumulative_traits(gen.HONEY_TOP)[:8], (101, 201, 301, 302, 401, 402, 403, 501))
        collector = gen.hive_svg(cases["synthetic_collector"].top, 70)
        self.assertEqual(len(re.search(r"<path d='M([^']*)'", collector).group(1).split("L")), 2, "nine steps: one edge")
        fullhouse = gen.hive_svg(cases["synthetic_fullhouse"].top, 5000)
        self.assertEqual(fullhouse.count("<circle"), 6)
        self.assertEqual(len(re.search(r"<path d='M([^']*)'", fullhouse).group(1).split("L")), 7, "58 steps: six segments")
        outsider = gen.hive_svg(cases["synthetic_outsider"].top, 5)
        self.assertEqual(outsider.count("stroke='#151515'"), 13)
        self.assertEqual(outsider.count("stroke-width='3' stroke-linejoin='round'/>"), 5 + 1, "five ring outlines and V")

    def test_goldens_are_synthetic_only(self) -> None:
        for data in gen.CASES.values():
            self.assertTrue(data.claimant.endswith("c1a1"))

    def test_check_mode_detects_drift_without_rewriting(self) -> None:
        with tempfile.TemporaryDirectory(prefix="sworn-generator-") as directory:
            root = Path(directory)
            outputs = gen.build_outputs(root)
            with redirect_stdout(io.StringIO()):
                self.assertEqual(gen.check_outputs(outputs, root), 1)
                gen.write_outputs(outputs, root)
                self.assertEqual(gen.check_outputs(outputs, root), 0)
            for changed in (root / gen.BLOB_PATH, root / gen.HIVE_PATH, root / gen.GENERATED_PATHS[-1]):
                original = changed.read_bytes()
                changed.write_bytes(b"changed")
                with redirect_stdout(io.StringIO()):
                    self.assertEqual(gen.check_outputs(outputs, root), 1)
                self.assertEqual(changed.read_bytes(), b"changed")
                changed.write_bytes(original)
            (root / gen.HIVE_PATH).unlink()
            with redirect_stdout(io.StringIO()):
                self.assertEqual(gen.check_outputs(outputs, root), 1)

    def test_generated_file_set_is_complete_and_newline_free(self) -> None:
        outputs = gen.build_outputs()
        expected = {gen.BLOB_PATH, gen.OFFSETS_PATH, gen.SOLIDITY_PATH, gen.HIVE_PATH, *gen.GENERATED_PATHS}
        self.assertEqual(set(outputs), expected)
        self.assertEqual(len(outputs), 4 + 3 * 8)
        for path, data in outputs.items():
            # the Solidity files are forge-fmt shaped (one trailing LF); every other artifact is newline-free
            self.assertEqual(data.endswith(b"\n"), path in (gen.SOLIDITY_PATH, gen.HIVE_PATH), str(path))
            self.assertEqual(data.count(b"\n"), data.count(b"\n") if path.suffix == ".sol" else 0)

    def test_committed_tree_matches_the_generator(self) -> None:
        with redirect_stdout(io.StringIO()):
            self.assertEqual(gen.check_outputs(gen.build_outputs()), 0)
        self.assertFalse((gen.ROOT / "template" / "card.svg").exists(), "the SVG template file is gone")


if __name__ == "__main__":
    unittest.main()
