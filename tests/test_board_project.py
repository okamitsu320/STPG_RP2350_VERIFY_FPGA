"""Safe host syntax/source checks and simulations, never Quartus/JTAG/USB."""
import base64
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "boards/cyclone10lp"
SYN = BOARD / "syn"


def tcl_records(source):
    tool = shutil.which("tclsh")
    if not tool:
        raise AssertionError("install Tcl for the host-only QSF/SDC syntax check")
    encoded = base64.b64encode(source.encode()).decode()
    # Safe child interpreter has no exec/open/socket. Only these seven aliases
    # are provided, all host recorders. No real helper or adapter is sourced.
    script = r'''
proc record {kind args} { puts [join [linsert $args 0 $kind] "\t"]; return {} }
proc ports {name} { return $name }
set child [interp create -safe]
foreach {command kind} {
 set_global_assignment GLOBAL set_location_assignment LOCATION
 set_instance_assignment INSTANCE create_clock CLOCK
 set_clock_groups GROUP derive_clock_uncertainty UNCERTAINTY
} { interp alias $child $command {} record $kind }
interp alias $child get_ports {} ports
'''
    script += 'set body [encoding convertfrom utf-8 [binary decode base64 {' + encoded + '}]]\n'
    script += 'if {[catch {interp eval $child $body} reason]} {puts stderr $reason; exit 1}\n'
    done = subprocess.run([tool], input=script, capture_output=True, text=True, timeout=10)
    if done.returncode:
        raise AssertionError(done.stderr)
    return [line.split("\t") for line in done.stdout.splitlines()]


class BoardProject(unittest.TestCase):
    def test_qsf_has_complete_unique_pins_standards_and_local_source_closure(self):
        rows = tcl_records((SYN / "vf_c10lp.qsf").read_text())
        global_settings = {row[2]: row[3] for row in rows if row[0] == "GLOBAL" and row[1] == "-name"}
        self.assertEqual(global_settings["DEVICE"], "10CL006YE144C8G")
        self.assertEqual(global_settings["TOP_LEVEL_ENTITY"], "pattern_verify_dut_24pin_vf")
        self.assertEqual(global_settings["FAMILY"], "Cyclone 10 LP")
        rtl = (SYN / global_settings["VERILOG_FILE"]).resolve(strict=True)
        sdc = (SYN / global_settings["SDC_FILE"]).resolve(strict=True)
        self.assertTrue(rtl.is_relative_to(ROOT) and sdc.is_relative_to(BOARD))
        self.assertEqual(rtl, ROOT / "rtl/pattern_verify_dut_24pin_vf.v")
        ports = {}
        header = rtl.read_text().split(");", 1)[0]
        for width, name in re.findall(r"(?:input|output|inout)\s+wire\s*(?:\[(\d+):0\])?\s*(\w+)", header):
            if width:
                ports.update({f"{name}[{i}]": name for i in range(int(width) + 1)})
            else:
                ports[name] = name
        pins = {row[3]: row[1] for row in rows if row[0] == "LOCATION"}
        self.assertEqual(set(pins), set(ports))
        self.assertEqual(len(pins), 29)
        self.assertEqual(len(set(pins.values())), 29)
        self.assertEqual(pins["oe_n"], "PIN_25")
        self.assertEqual(pins["clk_50m"], "PIN_91")
        standards = {row[5]: row[3] for row in rows if row[0] == "INSTANCE" and row[2] == "IO_STANDARD"}
        self.assertEqual(standards, {port: "3.3-V LVCMOS" for port in ports})
        pulls = {row[5]: row[3] for row in rows if row[0] == "INSTANCE" and row[2] == "WEAK_PULL_UP_RESISTOR"}
        self.assertEqual(pulls, {f"io[{i}]": "OFF" for i in range(8)})
        self.assertNotIn("oe_n", pulls)  # floating-input safety is NOT established
        self.assertIn('PROJECT_REVISION = "vf_c10lp"', (SYN / "vf_c10lp.qpf").read_text())

    def test_sdc_clock_contract_and_safe_interpreter(self):
        rows = tcl_records((SYN / "vf_c10lp.sdc").read_text())
        clocks = {row[2]: (row[4], row[5]) for row in rows if row[0] == "CLOCK"}
        self.assertEqual(clocks, {"clk": ("20.0", "clk"), "clk_50m": ("20.0", "clk_50m")})
        self.assertIn(["GROUP", "-asynchronous", "-group", "clk", "-group", "clk_50m"], rows)
        self.assertIn(["UNCERTAINTY"], rows)
        # A deliberately invalid port expression and an arbitrary exec fail in
        # the safe interpreter, not at the OS. No debugger is ever invoked.
        with self.assertRaises(AssertionError):
            tcl_records("set_location_assignment PIN_1 -to mode[0]")
        with self.assertRaises(AssertionError):
            tcl_records("exec STPG_FAKE_PROGRAM_MUST_NEVER_RUN")

    def test_all_benches_wire_the_single_board_rtl_explicitly(self):
        sources = list(ROOT.rglob("*.v"))
        self.assertEqual(sources, [ROOT / "rtl/pattern_verify_dut_24pin_vf.v"])
        ports = {"clk", "rst_n", "mode", "ctrl", "io", "dout", "clk_50m", "oe_n", "led1", "led2", "led3"}
        benches = list((ROOT / "tests").glob("*_tb.sv"))
        self.assertEqual(len(benches), 3)
        for bench in benches:
            body = bench.read_text()
            connection = re.search(r"pattern_verify_dut_24pin_vf\s+dut\s*\((.*?)\);", body, re.S)
            self.assertIsNotNone(connection, bench.name)
            self.assertEqual(set(re.findall(r"\.(\w+)\s*\(", connection[1])), ports, bench.name)
            self.assertNotIn("STPG_C10LP_BOARD", body)

    def simulate(self, rtl):
        for tool in ("iverilog", "vvp"):
            self.assertIsNotNone(shutil.which(tool), f"install {tool} for this host simulation")
        with tempfile.TemporaryDirectory(prefix="stpg-board-sim-") as directory:
            image = str(Path(directory) / "simulation")
            command = ["iverilog", "-g2012", "-s", "board_contract_tb", "-o", image]
            built = subprocess.run(command + [str(rtl), str(ROOT / "tests/board_contract_tb.sv")],
                                   capture_output=True, text=True, timeout=30)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run(["vvp", image], capture_output=True, text=True, timeout=30)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            self.assertIn("BOARD_CONTRACT_SIMULATION_PASS", ran.stdout)

    def test_board_lfsr_delay_and_oe_masking(self):
        self.simulate(ROOT / "rtl/pattern_verify_dut_24pin_vf.v")


if __name__ == "__main__":
    unittest.main()
