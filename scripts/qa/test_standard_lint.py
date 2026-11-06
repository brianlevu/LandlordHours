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


class Chevron(unittest.TestCase):
    def test_hand_drawn_chevron_counts(self):
        self.assertEqual(rules(scan_text('Image(systemName: "chevron.right")\n')).count("chevron"), 1)

    def test_lhchevron_home_is_exempt(self):
        f = scan_text('Image(systemName: systemName)\nImage(systemName: "chevron.right")\n', name="Sources/Views/Components/LHRow.swift")
        self.assertNotIn("chevron", rules(f))


class FixedSize(unittest.TestCase):
    def test_raw_fixed_size_counts(self):
        self.assertEqual(rules(scan_text("Text(x).fixedSize(horizontal: false, vertical: true)\n")).count("fixed-size"), 1)

    def test_wrapper_call_counts(self):
        self.assertEqual(rules(scan_text("Text(x).lhWrapsText()\n")).count("fixed-size"), 1)

    def test_second_wrapper_cannot_hide_a_fixed_size(self):
        f = scan_text("extension View {\n    func other() -> some View {\n        fixedSize(horizontal: false, vertical: true)\n    }\n}\n")
        self.assertEqual(rules(f).count("fixed-size"), 1)

    def test_the_sanctioned_wrapper_body_is_exempt(self):
        f = scan_text("extension View {\n    func lhWrapsText() -> some View {\n        fixedSize(horizontal: false, vertical: true)\n    }\n}\n",
                      name="Sources/Views/Components/AppDesignSystem.swift")
        self.assertNotIn("fixed-size", rules(f))


def fscan(files):
    """files: {relative path: text}"""
    root = tempfile.mkdtemp(prefix="lint-test-")
    for name, text in files.items():
        path = os.path.join(root, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w", encoding="utf-8").write(text)
    return sl.scan(root)


CLAMP = "X().dynamicTypeSize(...DynamicTypeSize.xxxLarge)\n"


class V2Rules(unittest.TestCase):
    def test_clamp_quota_three_sites_in_allowed_files(self):
        f = fscan({"Sources/Views/House/CraftHouseView.swift": CLAMP * 2, "Sources/Views/DashboardView.swift": CLAMP})
        self.assertNotIn("dynamic-type-clamp", rules(f))

    def test_fourth_site_and_other_files_are_new(self):
        f = fscan({"Sources/Views/House/CraftHouseView.swift": CLAMP * 3, "Sources/Views/DashboardView.swift": CLAMP})
        self.assertEqual(rules(f).count("dynamic-type-clamp"), 1)
        f = fscan({"Sources/Views/Other.swift": CLAMP})
        self.assertEqual(rules(f).count("dynamic-type-clamp"), 1)

    def test_drag_gesture_only_in_craft_house_view(self):
        self.assertNotIn("custom-swipe", rules(fscan({"Sources/Views/House/CraftHouseView.swift": "x.gesture(DragGesture())\n"})))
        self.assertIn("custom-swipe", rules(fscan({"Sources/Views/Row.swift": "x.gesture(DragGesture())\n"})))
        self.assertIn("custom-swipe", rules(fscan({"Sources/Views/House/CraftHouseView.swift": "TodaySwipeRow(x)\n"})))

    def test_craft_image(self):
        self.assertIn("craft_image".replace("_", "-"), rules(fscan({"Sources/Views/A.swift": 'Image("craft_half")\n'})))
        self.assertIn("craft-image", rules(fscan({"Sources/Views/A.swift": "Image(stage.rawValue)\n"})))
        self.assertNotIn("craft-image", rules(fscan({"Sources/Views/House/CraftHouseView.swift": 'Image("craft_half")\n'})))
        self.assertNotIn("craft-image", rules(fscan({"Sources/Views/Components/LHThumb.swift": "Image(stage.rawValue)\n"})))

    def test_hero_card(self):
        t = "CraftHouseView().background(.white, in: RoundedRectangle(cornerRadius: 20))\n"
        self.assertIn("hero-card", rules(fscan({"Sources/Views/House/Wrap.swift": t})))
        self.assertIn("hero-card", rules(fscan({"Sources/Views/DashboardView.swift": "LHCard { CraftHouseView() }\n"})))
        self.assertNotIn("hero-card", rules(fscan({"Sources/Views/Settings.swift": t})))

    def test_blueprint_retired(self):
        for w in ("BlueprintGrid()", "InboxBlueprintPaper()", "TapeMeasure()", "StampView()", "AppColors.kraft", "Color.vellum", "HouseHeroView()"):
            self.assertIn("blueprint-retired", rules(fscan({"Sources/Views/A.swift": w + "\n"})), w)
        self.assertNotIn("blueprint-retired", rules(fscan({"Sources/Views/A.swift": "// BlueprintGrid retired\n"})))

    def test_tab_shell(self):
        good = "TabView {\n" + "".join(f'Tab("t{i}", systemImage: "x") {{ }}\n' for i in range(4)) + 'Tab("s", systemImage: "plus", role: .search) { }\n}\n'
        self.assertNotIn("tab-shell", rules(fscan({"Sources/Views/ContentView.swift": good})))
        bad = good.replace('Tab("t0", systemImage: "x") { }\n', "")
        self.assertIn("tab-shell", rules(fscan({"Sources/Views/ContentView.swift": bad})))
        self.assertIn("tab-shell", rules(fscan({"Sources/Views/ContentView.swift": good + ".tint(Color(hex: 0x123456))\n"})))
        glass = good + 'Button { } label: { Image(systemName: "plus") }\n.buttonStyle(.glass)\n'
        self.assertIn("tab-shell", rules(fscan({"Sources/Views/ContentView.swift": glass})))
        self.assertNotIn("tab-shell", rules(fscan({"Sources/Views/Other.swift": "Text(x)\n"})))

    def test_page_ink(self):
        self.assertIn("page-ink", rules(fscan({"Sources/Views/House/CraftHouseView.swift": ".foregroundStyle(colors.textTertiary)\n"})))
        self.assertNotIn("page-ink", rules(fscan({"Sources/Views/House/CraftHouseView.swift": ".foregroundStyle(colors.textPrimary)\n"})))
        self.assertNotIn("page-ink", rules(fscan({"Sources/Views/Other.swift": ".foregroundStyle(colors.textTertiary)\n"})))

    def test_timeline_view(self):
        self.assertIn("timeline-view", rules(fscan({"Sources/Views/House/A.swift": "TimelineView(.animation) { _ in }\n"})))
        self.assertNotIn("timeline-view", rules(fscan({"Sources/Views/A.swift": "TimelineView(.animation) { _ in }\n"})))

    def test_section_header_mono(self):
        self.assertIn("section-header-mono", rules(fscan({"Sources/Views/Components/LHSectionHeader.swift": "Text(x).font(.caption.monospaced())\n"})))
        self.assertIn("section-header-mono", rules(fscan({"Sources/Views/A.swift": ".font(.system(.caption, design: .monospaced))\n"})))
        self.assertNotIn("section-header-mono", rules(fscan({"Sources/Views/ReportsView.swift": ".font(.system(.caption, design: .monospaced))\n"})))
        self.assertNotIn("section-header-mono", rules(fscan({"Sources/PDF/Doc.swift": ".font(.system(.caption, design: .monospaced))\n"})))



class ScreenAnatomy(unittest.TestCase):
    """Screen anatomy S1/S4: headers come only from the scaffolds."""

    def test_hand_made_title_counts(self):
        for src in ('LHScreenTitle("Inbox")\n', 'ScreenHeader(title: "Records")\n', 'LongTailHeader(title: t)\n',
                    '.navigationTitle("Rentals")\n', '.navigationBarTitleDisplayMode(.inline)\n',
                    '.toolbar(.hidden, for: .navigationBar)\n', '.navigationBarHidden(true)\n'):
            self.assertEqual(rules(scan_text(src)).count("hand-header"), 1, src)

    def test_scaffold_file_may_build_headers(self):
        f = scan_text('.navigationTitle(title)\n.toolbar(.hidden, for: .navigationBar)\n',
                      name="Sources/Views/Components/LHScreenScaffold.swift")
        self.assertNotIn("hand-header", rules(f))

    def test_scaffold_call_is_clean(self):
        f = scan_text('List { rows }\n    .lhTabScreen("Inbox")\n')
        self.assertNotIn("hand-header", rules(f))

    def test_comment_is_ignored(self):
        self.assertNotIn("hand-header", rules(scan_text('// was LHScreenTitle("Inbox")\n')))

    def test_legacy_definition_is_not_a_call_site(self):
        f = scan_text('struct LHScreenTitle: View {\n', name="Sources/Views/Components/LHScreenTitle.swift")
        self.assertNotIn("hand-header", rules(f))

    def test_tab_root_without_scaffold_fails(self):
        f = scan_text('struct InboxView: View {\n  var body: some View { List { } }\n}\n',
                      name="Sources/Views/Inbox/InboxView.swift")
        self.assertIn("tab-scaffold", rules(f))

    def test_tab_root_with_scaffold_passes(self):
        f = scan_text('struct InboxView: View {\n  var body: some View { List { }.lhTabScreen("Inbox") }\n}\n',
                      name="Sources/Views/Inbox/InboxView.swift")
        self.assertNotIn("tab-scaffold", rules(f))

    def test_log_sheet_needs_sheet_scaffold(self):
        f = scan_text('ScrollView { }.lhTabScreen("Log time")\n', name="Sources/Views/LogTime/LogSheetStyle.swift")
        self.assertIn("tab-scaffold", rules(f))

    def test_literal_top_padding_in_tab_root_counts(self):
        f = scan_text('x.padding(.top, 8)\ny.contentMargins(.top, 0, for: .scrollContent)\n'
                      'z.padding(.top, LHMetrics.sectionGap)\n', name="Sources/Views/HistoryView.swift")
        self.assertEqual(rules(f).count("tab-top-padding"), 2)

    def test_literal_top_padding_elsewhere_is_fine(self):
        f = scan_text('x.padding(.top, 8)\n', name="Sources/Views/Components/LHRow.swift")
        self.assertNotIn("tab-top-padding", rules(f))

if __name__ == "__main__":
    unittest.main(verbosity=2)
