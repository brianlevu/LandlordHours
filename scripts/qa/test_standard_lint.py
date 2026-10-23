#!/usr/bin/env python3
"""Tests for standard_lint.py.  python3 scripts/qa/test_standard_lint.py"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import standard_lint as sl  # noqa: E402


def scan_text(text, name="Sources/Views/T.swift"):
    root = tempfile.mkdtemp(prefix="lint-test-")
    path = os.path.join(root, name)
    os.makedirs(os.path.dirname(path))
    open(path, "w", encoding="utf-8").write(text)
    return sl.scan(root)


def rules(found):
    return [v["rule"] for v in found]


class DynamicTypeClamp(unittest.TestCase):
    def test_unmarked_clamp_counts(self):
        f = scan_text("Text(x).dynamicTypeSize(...DynamicTypeSize.xxxLarge)\n")
        self.assertEqual(rules(f).count("dynamic-type-clamp"), 1)

    def test_marker_on_same_line_exempts(self):
        f = scan_text("Text(x).dynamicTypeSize(...DynamicTypeSize.xxxLarge) // standard:§1.27-sidebar-clamp\n")
        self.assertNotIn("dynamic-type-clamp", rules(f))

    def test_marker_on_previous_line_exempts(self):
        f = scan_text("// standard:§1.27-sidebar-clamp\nSidebar().dynamicTypeSize(...DynamicTypeSize.xxxLarge)\n")
        self.assertNotIn("dynamic-type-clamp", rules(f))

    def test_marker_does_not_leak_to_later_clamps(self):
        f = scan_text("// standard:§1.27-sidebar-clamp\nA().dynamicTypeSize(...DynamicTypeSize.xxxLarge)\n"
                      "B()\nC().dynamicTypeSize(...DynamicTypeSize.large)\n")
        self.assertEqual(rules(f).count("dynamic-type-clamp"), 1)

    def test_other_rules_unaffected_by_marker(self):
        f = scan_text("Text(x).font(.system(size: 13)).dynamicTypeSize(...DynamicTypeSize.xxxLarge) // standard:§1.27-sidebar-clamp\n")
        self.assertIn("system-size", rules(f))
        self.assertNotIn("dynamic-type-clamp", rules(f))


if __name__ == "__main__":
    unittest.main(verbosity=2)
