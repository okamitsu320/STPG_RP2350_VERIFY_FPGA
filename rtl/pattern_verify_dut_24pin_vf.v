// pattern_verify_dut_24pin_vf.v
`timescale 1ns/1ps
// 24-pin FPGA pseudo-DUT — unified bidirectional design, vf
// Verilog-2001
//
// Combines v04 (all modes 0-F, regfile, timing_mode pipeline) with
// bidirectional io bus for STIL force/measure/turnaround pattern debugging.
//
// Port interface (24 pins + OE + clk_50m + LED):
//   clk(1) + rst_n(1) + mode[3:0](4) + ctrl[2:0](3) + io[7:0](8) + dout[6:0](7) = 24
//   oe_n: 0 -> operate; 1 -> RTL output-disable and state reset
//   Do not infer a safe floating pin or electrical release from this RTL.
//   clk_50m: board oscillator, used for LED blink only
//   led1/led2/led3: status LEDs. Use the QSF, not old board pin comments.
//
//   ctrl[0] = enable   (same as v04)
//   ctrl[1] = option   (same as v04)
//   ctrl[2] = io_oe    1: DUT drives io[7:0] / 0: PG drives io[7:0] (din equivalent)
//
//   io_oe=0: io used as data input (equivalent to din in v04)
//            dout[6:0] = response[6:0]  (DUT always drives, 7-bit auxiliary output)
//   io_oe=1: DUT drives io[7:0] = dout_nat (full 8-bit response)
//            dout[6:0] = response[6:0]  (same, lower 7 bits)
//
// IMPORTANT: mode=8 with io_oe=1 creates a combinational loop (io_in=io=dout_nat=f(io_in)).
//            Never assert ctrl[2]=1 while mode=8.
//
// ID:  mode=0 → dout_nat = 8'h05 (vf identifier)
// VER: regfile addr=0x02 → 8'h05
//
// Modes 0-F: identical to v04 (see v04 header for mode table)
// timing_mode pipeline: identical to v04

module pattern_verify_dut_24pin_vf (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] mode,
    input  wire [2:0] ctrl,
    inout  wire [7:0] io,
    output wire [6:0] dout,
    // OE + board OSC + LEDs (added for hardware bring-up)
    input  wire       clk_50m,  // board oscillator (LED blink only)
    input  wire       oe_n,     // OE active-low; see the board QSF
    output wire       led1,     // always OFF (H=OFF)
    output wire       led2,     // always ON (L=ON)
    output wire       led3      // blinks when OE=L; start-up phase is unspecified
);

    wire io_oe  = ctrl[2];
    wire enable = ctrl[0];
    wire option = ctrl[1];

    // io_in: value driven onto io bus by PG (valid when io_oe=0)
    // When io_oe=1, DUT drives io, so io_in = dout_nat (DUT reads its own output)
    wire [7:0] io_in = io;

    // Declare dout_nat before use in assign (Verilog-2001 forward-declaration restriction)
    reg [7:0] dout_nat;

    // Tristate driver: DUT drives io when io_oe=1 AND oe_n=0 (OE=L = operate)
    assign io = (io_oe && !oe_n) ? dout_nat : 8'bzzzzzzzz;

    // Internal 8-bit result register; dout[6:0] is Hi-Z when oe_n=1 (OE=H)
    reg [7:0] dout_reg;
    assign dout = !oe_n ? dout_reg[6:0] : 7'bzzzzzzz;

    // LED blink counter: free-running from 50MHz OSC, no reset needed
    // bit[25]: period = 2^26 / 50e6 ~= 1.34s -> ~0.75Hz visible blink
    reg [25:0] led_cnt;
    always @(posedge clk_50m) led_cnt <= led_cnt + 26'd1;

    assign led1 = 1'b1;                          // H=OFF: vf is normal-op mode
    assign led2 = 1'b0;                          // L=ON:  normal-op mode active
    assign led3 = !oe_n ? ~led_cnt[25] : 1'b1;  // blinks when OE=L (oe_n=0), off when OE=H

    // State registers (identical to v04, din_prev renamed to io_prev)
    reg [15:0] cycle_count;
    reg  [7:0] lfsr;
    reg [31:0] signature;
    reg  [7:0] accumulator;
    reg  [7:0] io_prev;
    reg  [5:0] addr_latch;
    reg  [7:0] regfile [0:47];

    // v0.4 timing pipeline
    reg  [2:0] timing_mode;
    reg  [7:0] dout_pipe [0:2];

    wire lfsr_fb = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];

    integer rst_i;

    // Combinational: dout_natural for modes 0-B, D-F
    // mode=C is handled in sequential block (Quartus regfile synthesis requirement)
    // (dout_nat declared above before assign io)
    always @(*) begin
        case (mode)
            4'h0: dout_nat = 8'h05;
            4'h1: dout_nat = io_prev;
            4'h2: dout_nat = option ? cycle_count[15:8]  : cycle_count[7:0];
            4'h3: dout_nat = lfsr;
            4'h4: dout_nat = option ? signature[15:8]    : signature[7:0];
            4'h5: dout_nat = option ? signature[31:24]   : signature[23:16];
            4'h6: dout_nat = {io_prev[7:1], ~io_prev[0]};
            4'h7: dout_nat = option ? 8'h55 : 8'hAA;
            4'h8: dout_nat = {io_in[6:0], io_in[7]} ^ 8'hA5;  // do NOT use with io_oe=1
            4'h9: dout_nat = accumulator;
            4'hA: dout_nat = {2'b00, addr_latch};
            4'hB: dout_nat = 8'h00;
            4'hC: dout_nat = 8'h00;
            4'hD: dout_nat = 8'h00;
            4'hE: dout_nat = {2'b00, addr_latch};
            4'hF: dout_nat = 8'hFF;
            default: dout_nat = 8'hFF;
        endcase
    end

    // cycle_count: free-running; also resets when OE=H (oe_n=1, pin open-safe)
    always @(posedge clk or negedge rst_n or posedge oe_n) begin
        if (!rst_n || oe_n) cycle_count <= 16'h0000;
        else                cycle_count <= cycle_count + 16'h0001;
    end

    // State + timing pipeline + dout_reg; also resets when OE=H
    always @(posedge clk or negedge rst_n or posedge oe_n) begin
        if (!rst_n || oe_n) begin
            lfsr         <= 8'hFF;
            signature    <= 32'h00000000;
            accumulator  <= 8'h00;
            io_prev      <= 8'h00;
            addr_latch   <= 6'h00;
            timing_mode  <= 3'h0;
            dout_pipe[0] <= 8'h00;
            dout_pipe[1] <= 8'h00;
            dout_pipe[2] <= 8'h00;
            dout_reg     <= 8'h00;
            for (rst_i = 0; rst_i < 48; rst_i = rst_i + 1)
                regfile[rst_i] <= 8'h00;
        end else begin
            // General state: modes 0-9, enable-gated, io_oe=0 only (PG drives io)
            // When io_oe=1 DUT drives io; io_in would be DUT's own output (feedback).
            // State must not be corrupted by self-feedback, so skip when io_oe=1.
            if (enable && (mode < 4'hA) && !io_oe) begin
                lfsr        <= {lfsr[6:0], lfsr_fb};
                signature   <= {signature[23:0], io_in} ^ {8'h00, signature[31:8]};
                accumulator <= accumulator + io_in;
                io_prev     <= io_in;
            end

            // Mode-specific register-file updates (only when PG drives io)
            case (mode)
                4'hA: if (enable && !io_oe) addr_latch <= io_in[5:0];
                4'hB: if (enable && !io_oe) begin
                          if (addr_latch == 6'h0A)
                              timing_mode <= io_in[2:0];
                          else if (addr_latch >= 6'h10)
                              regfile[addr_latch - 6'h10] <= io_in;
                      end
                4'hD: if (enable && !io_oe) begin
                          if (io_in[0]) signature   <= 32'h00000000;
                          if (io_in[1]) accumulator <= 8'h00;
                          if (io_in[2]) lfsr        <= 8'hFF;
                          if (io_in[3]) timing_mode <= 3'h0;
                      end
                default: ;
            endcase

            // Delay pipeline: shifts every clock
            dout_pipe[2] <= dout_pipe[1];
            dout_pipe[1] <= dout_pipe[0];
            dout_pipe[0] <= dout_nat;

            // dout_reg: mode=C reads regfile here (same block as write → Quartus retains FF)
            if (mode == 4'hC) begin
                if      (addr_latch == 6'h00) dout_reg <= 8'hA5;
                else if (addr_latch == 6'h01) dout_reg <= 8'h3C;
                else if (addr_latch == 6'h02) dout_reg <= 8'h05;
                else if (addr_latch == 6'h03) dout_reg <= 8'h00;
                else if (addr_latch == 6'h04) dout_reg <= cycle_count[7:0];
                else if (addr_latch == 6'h05) dout_reg <= cycle_count[15:8];
                else if (addr_latch == 6'h06) dout_reg <= signature[7:0];
                else if (addr_latch == 6'h07) dout_reg <= signature[15:8];
                else if (addr_latch == 6'h08) dout_reg <= signature[23:16];
                else if (addr_latch == 6'h09) dout_reg <= signature[31:24];
                else if (addr_latch == 6'h0A) dout_reg <= {5'b0, timing_mode};
                else if (addr_latch >= 6'h10) dout_reg <= regfile[addr_latch - 6'h10];
                else                          dout_reg <= 8'h00;
            end else begin
                case (timing_mode)
                    3'h0: dout_reg <= dout_nat;
                    3'h1: dout_reg <= dout_pipe[0];
                    3'h2: dout_reg <= dout_pipe[1];
                    3'h3: dout_reg <= dout_pipe[2];
                    3'h4: dout_reg <= {dout_pipe[0][7:4], dout_nat[3:0]};
                    3'h5: dout_reg <= (cycle_count[3:0] == 4'h7) ? 8'hFF : 8'h00;
                    default: dout_reg <= dout_nat;
                endcase
            end
        end
    end

endmodule
