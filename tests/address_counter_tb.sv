`timescale 1ns/1ps
// Public, synthetic host simulation of the board RTL: no hardware access.
module address_counter_tb;
  reg clk = 0;
  reg rst_n = 0;
  reg [3:0] mode = 0;
  reg [2:0] ctrl = 0;
  reg [7:0] host_value = 0;
  wire [7:0] io;
  wire [6:0] dout;
  reg [15:0] model_cycles = 0;
  integer i;
  integer expected_before_edge;
  assign io = host_value;  // ctrl[2] stays zero: only this test drives io.
  wire led1, led2, led3;
  reg clk_50m = 0;
  always #10 clk_50m = ~clk_50m;
  pattern_verify_dut_24pin_vf dut (
    .clk(clk), .rst_n(rst_n), .mode(mode), .ctrl(ctrl), .io(io), .dout(dout),
    .clk_50m(clk_50m), .oe_n(1'b0), .led1(led1), .led2(led2), .led3(led3)
  );
  always #5 clk = ~clk;
  // Independent stimulus-side count; never inspect DUT registers as the oracle.
  always @(posedge clk or negedge rst_n)
    if (!rst_n) model_cycles <= 0;
    else model_cycles <= (model_cycles + 1) & 16'hffff;

  task tick;
    begin @(posedge clk); #1; end
  endtask
  task expect_output(input [6:0] value);
    begin
      if (dout !== value)
        $fatal(1, "address/counter mismatch: got %h expected %h", dout, value);
    end
  endtask
  task address(input [5:0] value);
    begin
      @(negedge clk); mode = 4'hA; ctrl = 1; host_value = {2'b00, value};
      tick();
    end
  endtask

  initial begin
    #1; rst_n = 1; #1; rst_n = 0; tick();
    expect_output(0);
    @(negedge clk); rst_n = 1;

    // All 48 entries, including 0x30..0x3f, are addressable via address-0x10.
    // Write the entire bank before reading so aliases cannot hide each other.
    for (i = 0; i < 48; i = i + 1) begin
      address(6'h10 + i);
      @(negedge clk); mode = 4'hB; ctrl = 1;
      host_value = (17 + 3*i) & 127;  // 48 distinct values on the 7-bit output
      tick();
    end
    for (i = 0; i < 48; i = i + 1) begin
      address(6'h10 + i);
      @(negedge clk); mode = 4'hC; ctrl = 0;
      tick(); expect_output((17 + 3*i) & 127);
    end

    // The counter is free-running even with enable clear. Verify both halves
    // through the registered public output, across multiple low-byte wraps.
    @(negedge clk); mode = 2; ctrl = 0;
    for (i = 0; i < 260; i = i + 1) begin
      expected_before_edge = model_cycles;
      tick(); expect_output(expected_before_edge & 127);
      @(negedge clk); ctrl = 2;  // option=1, enable=0
      expected_before_edge = model_cycles;
      tick(); expect_output((expected_before_edge >> 8) & 127);
      @(negedge clk); ctrl = 0;
    end
    $display("ADDRESS_COUNTER_SIMULATION_PASS");
    $finish;
  end
  initial begin #20000; $fatal(1, "simulation deadline"); end
endmodule
