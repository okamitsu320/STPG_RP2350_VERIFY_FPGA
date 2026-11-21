`timescale 1ns/1ps
// Public host simulation. No cable or programmer is used.
module board_contract_tb;
  reg clk = 0, rst_n = 0;
  reg [3:0] mode = 0;
  reg [2:0] ctrl = 0;
  reg [7:0] stimulus = 0;
  reg host_drives = 1;
  wire [7:0] io;
  wire [6:0] dout;
  assign io = host_drives ? stimulus : 8'bz;
  reg oe_n = 0, clk_50m = 0;
  wire led1, led2, led3;
  always #10 clk_50m = ~clk_50m;
  pattern_verify_dut_24pin_vf dut (
    .clk(clk), .rst_n(rst_n), .mode(mode), .ctrl(ctrl), .io(io), .dout(dout),
    .oe_n(oe_n), .clk_50m(clk_50m), .led1(led1), .led2(led2), .led3(led3)
  );

  task tick;
    begin #4; clk = 1; #1; clk = 0; #1; end
  endtask
  task reset;
    begin rst_n = 0; #1; tick; rst_n = 1; #1; end
  endtask
  task check_dout(input [7:0] expected);
    begin
      if (dout !== expected[6:0])
        $fatal(1, "response: expected %02x, observed %02x", expected[6:0], dout);
    end
  endtask
  task set_delay(input [2:0] delay);
    begin
      host_drives = 1; ctrl = 1; mode = 4'ha; stimulus = 8'h0a; tick;
      mode = 4'hb; stimulus = {5'b0, delay}; tick;
      ctrl = 0; mode = 7;
      repeat (4) tick;
    end
  endtask

  reg [7:0] lfsr_model;
  reg [7:0] history [0:2];
  reg [7:0] natural, expected;
  integer i, delay;
  initial begin
    reset; tick; check_dout(8'h05);
    // Independent black-box expectation: output is the pre-edge LFSR and then
    // state advances. Check both I/O directions without updating self-feedback.
    mode = 3; ctrl = 1; lfsr_model = 8'hff;
    for (i = 0; i < 40; i = i + 1) begin
      tick; check_dout(lfsr_model);
      lfsr_model = {lfsr_model[6:0], lfsr_model[7] ^ lfsr_model[5] ^ lfsr_model[4] ^ lfsr_model[3]};
    end
    ctrl = 4; host_drives = 0; #1;
    if (io !== lfsr_model) $fatal(1, "full-width LFSR bus response");
    tick; check_dout(lfsr_model);
    if (io !== lfsr_model) $fatal(1, "self-feedback changed LFSR");
    ctrl = 0; host_drives = 1;

    // Delay modes 0..3 are checked against a history queue, not another copy
    // of the RTL output mux. Other timing modes are not covered by this bench.
    for (delay = 0; delay < 4; delay = delay + 1) begin
      set_delay(delay[2:0]);
      history[0] = 8'haa; history[1] = 8'haa; history[2] = 8'haa;
      for (i = 0; i < 10; i = i + 1) begin
        ctrl = (i % 2 == 0) ? 2 : 0;
        natural = ctrl[1] ? 8'h55 : 8'haa;
        expected = (delay == 0) ? natural : history[delay - 1];
        tick; check_dout(expected);
        history[2] = history[1]; history[1] = history[0]; history[0] = natural;
      end
    end

    // RTL-only asynchronous masking/reset; not measured released voltage.
    // Advance state first, otherwise a missing OE state reset can hide behind
    // the explicit rst_n reset and still return the expected LFSR seed.
    reset; mode = 3; ctrl = 1; host_drives = 1;
    repeat (5) tick;
    mode = 0; ctrl = 4; host_drives = 0; tick;
    if (io !== 8'h05 || dout !== 7'h05) $fatal(1, "board drive before OE");
    oe_n = 1; #1;
    if (io !== 8'bz || dout !== 7'bz) $fatal(1, "OE does not mask both buses");
    if (led1 !== 1 || led2 !== 0 || led3 !== 1) $fatal(1, "board LED logic with OE high");
    // No clk edge while OE is high: this checks asynchronous reset, not a
    // coincidental synchronous reset. Observe state only through outputs.
    mode = 2; ctrl = 0; host_drives = 1;
    oe_n = 0; #1; tick;
    check_dout(8'h00);
    mode = 3; tick;
    check_dout(8'hff);
    $display("BOARD_CONTRACT_SIMULATION_PASS");
    $finish;
  end
  initial begin #10000; $fatal(1, "simulation deadline"); end
endmodule
