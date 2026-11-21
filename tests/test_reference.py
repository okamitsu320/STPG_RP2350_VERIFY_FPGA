"""Host simulation only; no board-specific build or physical contact."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReferenceSimulation(unittest.TestCase):
    def simulate(self, top, marker):
        # Missing tools are a failure: a skipped simulation is not evidence.
        for tool in ("iverilog", "vvp"):
            self.assertIsNotNone(shutil.which(tool), f"install {tool} before this test")
        with tempfile.TemporaryDirectory(prefix="stpg-fpga-sim-") as directory:
            image = str(Path(directory) / "simulation")
            built = subprocess.run(["iverilog", "-g2012", "-s", top, "-o", image,
                                    str(ROOT / "rtl/pattern_verify_dut_24pin_vf.v"),
                                    str(ROOT / "tests" / (top + ".sv"))],
                                   capture_output=True, text=True, timeout=30)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run(["vvp", image], capture_output=True, text=True, timeout=30)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            self.assertIn(marker, ran.stdout)

    def test_reference_behaviour(self):
        self.simulate("reference_tb", "REFERENCE_SIMULATION_PASS")

    def test_all_48_addresses_and_both_counter_halves(self):
        self.simulate("address_counter_tb", "ADDRESS_COUNTER_SIMULATION_PASS")


if __name__ == "__main__":
    unittest.main()
