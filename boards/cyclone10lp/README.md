# Cyclone 10 LP board project

Open `syn/vf_c10lp.qpf` in Quartus. The QSF selects device `10CL006YE144C8G`
and `../../../rtl/pattern_verify_dut_24pin_vf.v` relative to the `syn` folder.
No source outside this repository, user-specific installation path or generated
programming image is required to inspect this project.

There is only one production RTL, in the top-level `rtl/` directory. It is the
actual board RTL, including `oe_n`, `clk_50m` and three LEDs, and all host
simulations use it too. There is no second same-named module to choose from.
Moving this source did not change its bytes or the pin assignments.

## Build (not programming)

The QPF records version 20.1; the QSF records a last-written version of
25.1std.0 Lite Edition. These are project metadata, not a reproduced build
environment. With a suitable Quartus installation, use **Processing → Start
Compilation**, or from the `syn` folder:

```sh
quartus_sh --flow compile vf_c10lp
```

Review fitter/timing reports before considering hardware use. This export has
not been compiled with Quartus or programmed onto a board. Host syntax/source
closure and simulation results are not Quartus, pinout or electrical validation.
No programmer, cable, flash conversion or device operation is part of this
project's test command.

## Owner-supplied pin constraints

| Port | Package pins in bit order |
| --- | --- |
| clk / rst_n | 3 / 7 |
| mode[0..3] | 1, 2, 143, 144 |
| ctrl[0..2] | 141, 142, 137 |
| io[0..7] | 138, 135, 136, 132, 133, 119, 115, 121 |
| dout[0..6] | 120, 125, 124, 127, 126, 129, 128 |
| clk_50m / oe_n | 91 / 25 |
| led1 / led2 / led3 | 101 / 100 / 99 |

The QSF specifies 3.3-V LVCMOS, disables weak pull-ups on the eight `io` pins,
and reserves PIN_101 for regular I/O after configuration. Verify the actual
board revision, bank voltages, wiring and loads independently. The source
comments are not a substitute for that check.

`oe_n=1` masks the RTL's `io`/`dout` drivers and resets its state. This is not
proof of released pin voltage, safe start-up or safe disconnected wiring.
The provided QSF does **not** explicitly enable a weak pull-up on `oe_n`;
do not assume a floating pin is safe. LED counter start-up phase is unspecified.
Avoid mode 8 with ctrl[2]=1.

The SDC declares separate 20 ns clocks on `clk` and `clk_50m`, marks them
asynchronous and derives clock uncertainty. It has no external input/output
delay constraints; do not read a successful timing summary as qualification of
STPG-to-FPGA timing. There is no generated PLL or external vendor IP here.
