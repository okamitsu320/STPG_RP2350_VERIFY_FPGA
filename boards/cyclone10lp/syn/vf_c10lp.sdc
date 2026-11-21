# Timing constraints for pattern_verify_dut_24pin_vf (Cyclone 10 LP)
# Target: 50 MHz (period = 20 ns)

create_clock -name clk     -period 20.0  [get_ports clk]
create_clock -name clk_50m -period 20.0  [get_ports clk_50m]

set_clock_groups -asynchronous -group {clk} -group {clk_50m}

derive_clock_uncertainty
