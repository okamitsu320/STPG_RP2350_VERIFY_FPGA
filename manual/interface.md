# Reference interface and safe integration

| Port | Width | Direction relative to FPGA |
| --- | ---: | --- |
| clk | 1 | input |
| rst_n | 1 | active-low reset input |
| mode | 4 | input |
| ctrl | 3 | input |
| io | 8 | bidirectional |
| dout | 7 | output (registered, low seven response bits) |
| oe_n | 1 | active-low board output enable; high also resets the DUT state |
| clk_50m | 1 | board oscillator input, used for the LED counter only |
| led1 / led2 / led3 | 1 each | board LED outputs |

The first six rows are the 24-pin STPG interface. The other five pins are
board controls/indicators, not extra STPG pattern pins. All simulations and
the Quartus project use this one module in `rtl/`.

ctrl[0] enables state updates, ctrl[1] selects a mode option,
ctrl[2] enables the FPGA driver on io. When ctrl[2] is zero the pattern
generator may drive io; when it is one the pattern generator must release io
before the FPGA drives. With `oe_n=0`, the auxiliary dout pins are FPGA
outputs. With `oe_n=1`, both io and dout drivers are masked in the RTL and
the DUT state resets asynchronously. This does not prove electrical release
or that a floating output-enable input is safe.

**Never combine mode 8 with ctrl[2]=1.** This creates combinational feedback.
The simulation avoids this unsupported combination.

Selected modes: 0 gives identifier 0x05; 1 returns the previous input;
2 reports the free-running counter; 7 selects 0xAA or 0x55; A latches a
register address; B writes it; C reads it; F gives 0xFF. Register address 2
returns version 0x05. See RTL for other modes and timing-pipeline behaviour.
Not every mode is covered by the selected simulation.

The 48 data-register entries occupy addresses **0x10 through 0x3F**, inclusive.
The six-bit address is translated to an array index by subtracting 0x10:
0x10 maps to index 0 and 0x3F maps to index 47. In particular, 0x30 through
0x3F are valid data-register addresses, not out-of-range accesses.
Addresses below 0x10 select status/control functions; they are not this array.
Mode A captures only the low six bits of its input.

The address/counter simulation writes all 48 entries before reading them back
through the seven-bit auxiliary output, and checks both counter halves across
low-byte wraps with enable clear. These are logic checks, not timing or board
validation.

The [Cyclone 10 LP project](../boards/cyclone10lp/README.md) includes separate
owner-supplied constraints and uses the same RTL as the host benches, including
the OE/oscillator/LED ports. Its supplied SDC is not a full
external-interface timing specification.

Before any board use, independently establish the actual device/package,
voltage standards, oscillator/clock routing, reset, all 24 physical pins and
bidirectional output-enable timing. Supply reviewed Quartus project/SDC
constraints and timing reports for that exact board. No pin table from a
different board is a substitute for that verification. Manufacturer
photos, logos and third-party board design files are not redistributed.
