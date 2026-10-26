import json, subprocess, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_triage as T

LOG = """Test Case '-[App.FooUITests testA]' started.
/x/Foo.swift:12: error: -[App.FooUITests testA] : XCTAssertTrue failed - Missing "Go" Button
Test Case '-[App.FooUITests testA]' failed (3.0 seconds).
Test Case '-[App.FooUITests testB]' failed (1.0 seconds).
"""

class T1(unittest.TestCase):
    def test_parse_log(self):
        p = Path(tempfile.mkdtemp()) / "ui.log"; p.write_text(LOG)
        f = T.parse_log(p)
        self.assertEqual([(x["suite"], x["test"]) for x in f], [("FooUITests", "testA"), ("FooUITests", "testB")])
        self.assertIn("Missing", f[0]["message"])

    def test_fail_open_no_ai(self):
        f = [{"test": "t", "suite": "S", "message": "m"}]
        r = T.triage(f, 0.5, no_ai=True)
        self.assertEqual(r[0]["route"], "agent"); self.assertIsNone(r[0]["label"])

    def test_below_threshold_routes_to_agent(self):
        T.ask_many = lambda states: [{"stale_selector_or_string": 0.4, "real_behaviour_bug": 0.3,
                                      "environment_or_infrastructure": 0.2, "test_logic_bug": 0.1}]
        r = T.triage([{"test": "t", "suite": "S", "message": "m"}], 0.6)
        self.assertEqual(r[0]["route"], "agent"); self.assertEqual(r[0]["suggested"], "stale_selector_or_string")
        r = T.triage([{"test": "t", "suite": "S", "message": "m"}], 0.3)
        self.assertEqual(r[0]["route"], "label")

if __name__ == "__main__":
    unittest.main()
