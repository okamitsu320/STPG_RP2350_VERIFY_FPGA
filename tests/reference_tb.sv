`timescale 1ns/1ps
module reference_tb;
  reg clk = 0;
  reg rst_n = 0;
  reg [3:0] mode = 0;
  reg [2:0] ctrl = 0;
  reg host_drive = 1;
  reg [7:0] host_value = 0;
  wire [7:0] io;
  wire [6:0] dout;
  assign io = host_drive ? host_value : 8'bz;
  wire led1, led2, led3;
  reg clk_50m = 0;
  always #10 clk_50m = ~clk_50m;
  pattern_verify_dut_24pin_vf dut (
    .clk(clk), .rst_n(rst_n), .mode(mode), .ctrl(ctrl), .io(io), .dout(dout),
    .clk_50m(clk_50m), .oe_n(1'b0), .led1(led1), .led2(led2), .led3(led3)
  );
  always #5 clk = ~clk;

  task tick;
    begin @(posedge clk); #1; end
  endtask
  task expect_output(input [6:0] value);
    begin
      if (dout !== value) $fatal(1, "registered output mismatch");
    end
  endtask

  initial begin
    // Force an actual reset edge, then leave reset with known inputs.
    #1; rst_n = 1; #1; rst_n = 0; tick();
    expect_output(0);
    @(negedge clk); rst_n = 1; tick(); expect_output(7'h05);

    // Mode 1 reports the previous enabled host input, not the current input.
    @(negedge clk); mode = 1; ctrl = 1; host_value = 8'h23;
    tick(); expect_output(0);
    @(negedge clk); host_value = 8'h45;
    tick(); expect_output(7'h23);
    @(negedge clk); ctrl = 0; host_value = 8'h11;
    tick(); expect_output(7'h45);
    tick(); expect_output(7'h45);

    // Register-file version and a write/read through host-driven io.
    @(negedge clk); mode = 4'hA; ctrl = 1; host_value = 2;
    tick();
    @(negedge clk); mode = 4'hC; ctrl = 0;
    tick(); expect_output(7'h05);
    @(negedge clk); mode = 4'hA; ctrl = 1; host_value = 6'h10;
    tick();
    @(negedge clk); mode = 4'hB; host_value = 8'h36;
    tick();
    @(negedge clk); mode = 4'hC; ctrl = 0;
    tick(); expect_output(7'h36);

    // Release host before enabling FPGA, and disable FPGA before host drive.
    @(negedge clk); host_drive = 0; mode = 0; ctrl = 4;
    #1; if (io !== 8'h05) $fatal(1, "bidirectional identifier mismatch");
    tick(); expect_output(7'h05);
    @(negedge clk); ctrl = 0;
    #1; if (io !== 8'bz) $fatal(1, "FPGA did not release io");
    host_drive = 1; host_value = 8'h22;
    #1; if (io !== 8'h22) $fatal(1, "host input mismatch");

    // Pattern constants and low-seven-bit truncation.
    mode = 7; ctrl = 0; tick(); expect_output(7'h2A);
    @(negedge clk); ctrl = 2; tick(); expect_output(7'h55);
    @(negedge clk); mode = 4'hF; tick(); expect_output(7'h7F);
    $display("REFERENCE_SIMULATION_PASS");
    $finish;
  end
  initial begin #10000; $fatal(1, "simulation deadline"); end
endmodule
