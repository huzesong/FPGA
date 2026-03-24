// =============================================================================
// Testbench: tb_b_code_decoder
// Description: Simulation testbench for the IRIG-B decoder.
//
// Uses a very small CLK_FREQ parameter so that all bit timings are just a
// handful of clock cycles, keeping simulation time short.
//
// Simulation timing:
//   CLK_FREQ   = 1000  (1 kHz equivalent for fast simulation)
//   BIT_PERIOD = 10 cycles  (IRIG-B: 100 bits/s -> CLK_FREQ/100)
//   Logic 0    : 2 cycles high  ( 2 ms equivalent)
//   Logic 1    : 5 cycles high  ( 5 ms equivalent)
//   Reference  : 8 cycles high  ( 8 ms equivalent)
//
// IRIG-B frame structure (100 bits/frame, 10 position identifiers):
//   Position identifiers at bits: 0,9,19,29,39,49,59,69,79,99
//
// Test frame values:
//   seconds=35 (tens=3, units=5)
//   minutes=30 (tens=3, units=0)
//   hours=14   (tens=1, units=4)
//   doy=123    (hundreds=1, tens=2, units=3)
//   year=24    (tens=2, units=4)  -> 2024, leap year
//
// Expected calendar date for doy=123 in 2024 (leap year):
//   Jan(31)+Feb(29)+Mar(31)+Apr(30) = 121 -> doy 122=May1, doy 123=May2
//   => month=5, day=2
// =============================================================================
`timescale 1ns/1ps

module tb_b_code_decoder;

    parameter CLK_FREQ   = 1000;
    parameter CLK_PERIOD = 2;

    localparam BIT_PERIOD = CLK_FREQ / 100;
    localparam PULSE_0    = CLK_FREQ * 2 / 1000;   // 2 cycles
    localparam PULSE_1    = CLK_FREQ * 5 / 1000;   // 5 cycles
    localparam PULSE_REF  = CLK_FREQ * 8 / 1000;   // 8 cycles

    reg  clk, rst_n, b_code_in;

    wire [5:0]  second, minute;
    wire [4:0]  hour;
    wire [8:0]  day_of_year;
    wire [6:0]  year;
    wire [3:0]  month;
    wire [4:0]  day;
    wire        is_leap, time_valid, pps_out;

    b_code_decoder #(.CLK_FREQ(CLK_FREQ)) dut (
        .clk        (clk),       .rst_n      (rst_n),
        .b_code_in  (b_code_in),
        .second     (second),    .minute     (minute),
        .hour       (hour),      .day_of_year(day_of_year),
        .year       (year),      .month      (month),
        .day        (day),       .is_leap    (is_leap),
        .time_valid (time_valid),.pps_out    (pps_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -----------------------------------------------------------------------
    // Emit one IRIG-B bit
    //   bit_val 0 = logic-0 (2 cycles high)
    //   bit_val 1 = logic-1 (5 cycles high)
    //   bit_val 2 = reference (8 cycles high)
    // -----------------------------------------------------------------------
    task emit_bit;
        input [1:0] bit_val;
        integer     pulse_len;
        begin
            case (bit_val)
                2'd0:    pulse_len = PULSE_0;
                2'd1:    pulse_len = PULSE_1;
                default: pulse_len = PULSE_REF;
            endcase
            @(negedge clk); b_code_in = 1'b1;
            repeat (pulse_len)            @(posedge clk);
            @(negedge clk); b_code_in = 1'b0;
            repeat (BIT_PERIOD - pulse_len) @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Emit one complete 100-bit IRIG-B frame.
    //
    // Frame layout (position identifiers at bits 0,9,19,29,39,49,59,69,79,99):
    //
    // Encoded values:
    //   sec=35:  units=5 -> bits1-4 = 1,0,1,0; tens=3 -> bits6-7 = 1,1
    //   min=30:  units=0 -> bits10-13 = 0,0,0,0; tens=3 -> bits15-17 = 1,1,0
    //   hr=14:   units=4 -> bits20-23 = 0,0,1,0; tens=1 -> bits25-26 = 1,0
    //   doy=123: units=3 -> bits30-33 = 1,1,0,0; tens=2 -> bits35-38 = 0,1,0,0
    //            hundreds=1 -> bits40-41 = 1,0
    //   yr=24:   units=4 -> bits60-63 = 0,0,1,0; tens=2 -> bits64-67 = 0,1,0,0
    // -----------------------------------------------------------------------
    task emit_frame;
        begin
            //--- Bit 0: P0 (reference) ---
            emit_bit(2'd2);

            //--- Bits 1-4: sec units=5 (1+4=5, weights 1,2,4,8) ---
            emit_bit(2'd1); // bit1:  w=1  SET
            emit_bit(2'd0); // bit2:  w=2  CLR
            emit_bit(2'd1); // bit3:  w=4  SET
            emit_bit(2'd0); // bit4:  w=8  CLR

            //--- Bit 5: unused (0) ---
            emit_bit(2'd0);

            //--- Bits 6-7: sec tens=3 (10+20=30, weights 10,20) ---
            emit_bit(2'd1); // bit6:  w=10 SET
            emit_bit(2'd1); // bit7:  w=20 SET

            //--- Bit 8: unused (0) ---
            emit_bit(2'd0);

            //--- Bit 9: P1 (reference) ---
            emit_bit(2'd2);

            //--- Bits 10-13: min units=0 ---
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);

            //--- Bit 14: unused ---
            emit_bit(2'd0);

            //--- Bits 15-17: min tens=3 (10+20=30, weights 10,20,40) ---
            emit_bit(2'd1); // bit15: w=10 SET
            emit_bit(2'd1); // bit16: w=20 SET
            emit_bit(2'd0); // bit17: w=40 CLR

            //--- Bit 18: unused ---
            emit_bit(2'd0);

            //--- Bit 19: P2 (reference) ---
            emit_bit(2'd2);

            //--- Bits 20-23: hr units=4 (4=4, weights 1,2,4,8) ---
            emit_bit(2'd0); // bit20: w=1  CLR
            emit_bit(2'd0); // bit21: w=2  CLR
            emit_bit(2'd1); // bit22: w=4  SET
            emit_bit(2'd0); // bit23: w=8  CLR

            //--- Bit 24: unused ---
            emit_bit(2'd0);

            //--- Bits 25-26: hr tens=1 (10, weights 10,20) ---
            emit_bit(2'd1); // bit25: w=10 SET
            emit_bit(2'd0); // bit26: w=20 CLR

            //--- Bits 27-28: unused ---
            emit_bit(2'd0); emit_bit(2'd0);

            //--- Bit 29: P3 (reference) ---
            emit_bit(2'd2);

            //--- Bits 30-33: doy units=3 (1+2=3, weights 1,2,4,8) ---
            emit_bit(2'd1); // bit30: w=1  SET
            emit_bit(2'd1); // bit31: w=2  SET
            emit_bit(2'd0); // bit32: w=4  CLR
            emit_bit(2'd0); // bit33: w=8  CLR

            //--- Bit 34: unused ---
            emit_bit(2'd0);

            //--- Bits 35-38: doy tens=2 (20, weights 10,20,40,80) ---
            emit_bit(2'd0); // bit35: w=10 CLR
            emit_bit(2'd1); // bit36: w=20 SET
            emit_bit(2'd0); // bit37: w=40 CLR
            emit_bit(2'd0); // bit38: w=80 CLR

            //--- Bit 39: P4 (reference) ---
            emit_bit(2'd2);

            //--- Bits 40-41: doy hundreds=1 (100, weights 100,200) ---
            emit_bit(2'd1); // bit40: w=100 SET
            emit_bit(2'd0); // bit41: w=200 CLR

            //--- Bits 42-48: SBS/CF (unused here = 0) ---
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);

            //--- Bit 49: P5 (reference) ---
            emit_bit(2'd2);

            //--- Bits 50-58: SBS/CF (0) ---
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);

            //--- Bit 59: P6 (reference) ---
            emit_bit(2'd2);

            //--- Bits 60-63: yr units=4 (weights 1,2,4,8) ---
            emit_bit(2'd0); // bit60: w=1  CLR
            emit_bit(2'd0); // bit61: w=2  CLR
            emit_bit(2'd1); // bit62: w=4  SET
            emit_bit(2'd0); // bit63: w=8  CLR

            //--- Bits 64-67: yr tens=2 (20, weights 10,20,40,80) ---
            emit_bit(2'd0); // bit64: w=10 CLR
            emit_bit(2'd1); // bit65: w=20 SET
            emit_bit(2'd0); // bit66: w=40 CLR
            emit_bit(2'd0); // bit67: w=80 CLR

            //--- Bit 68: leap second pending / CF (0) ---
            emit_bit(2'd0);

            //--- Bit 69: P7 (reference) ---
            emit_bit(2'd2);

            //--- Bits 70-78: DST flags / CF (0) ---
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);

            //--- Bit 79: P8 (reference) ---
            emit_bit(2'd2);

            //--- Bits 80-98: CF/quality (0) ---
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);
            emit_bit(2'd0); emit_bit(2'd0); emit_bit(2'd0);
            emit_bit(2'd0);

            //--- Bit 99: P9 (reference, end of frame) ---
            emit_bit(2'd2);
        end
    endtask

    // -----------------------------------------------------------------------
    // Assertion helper
    // -----------------------------------------------------------------------
    integer pass_count, fail_count;

    task check_val;
        input [255:0] name;
        input [31:0]  got;
        input [31:0]  expected;
        begin
            if (got === expected) begin
                $display("  PASS: %-20s = %0d", name, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: %-20s = %0d  (expected %0d)", name, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Test flow
    // -----------------------------------------------------------------------
    initial begin
        pass_count = 0; fail_count = 0;
        b_code_in = 1'b0;
        rst_n     = 1'b0;
        repeat (10) @(posedge clk);
        #1; rst_n = 1'b1;
        repeat (5)  @(posedge clk);

        $display("=== IRIG-B Decoder Testbench ===");
        $display("Emitting 8 frames to allow decoder synchronisation...");
        repeat (8) emit_frame();
        repeat (10) @(posedge clk);

        $display("Checking decoded values (expected: sec=35 min=30 hr=14 doy=123 yr=24):");
        check_val("time_valid",  time_valid,  1);
        check_val("second",      second,      35);
        check_val("minute",      minute,      30);
        check_val("hour",        hour,        14);
        check_val("day_of_year", day_of_year, 123);
        check_val("year",        year,        24);
        check_val("is_leap",     is_leap,     1);   // 2024 is leap (24%4==0)
        check_val("month",       month,       5);   // May
        check_val("day",         day,         2);   // 2nd

        $display("\n=== Results: %0d passed, %0d failed ===", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");

        $finish;
    end

    initial begin
        #1_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
