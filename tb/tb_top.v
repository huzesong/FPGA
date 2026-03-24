// =============================================================================
// Testbench: tb_top
// Description: Integration testbench for the top-level module.
//
// Tests both signal paths:
//   Part 1: IRIG-B decoding - injects a synthetic IRIG-B frame sequence and
//           verifies decoded time (including leap year Feb 29).
//   Part 2: GNSS NMEA via simulated UART - sends a $GPRMC sentence at 9600
//           baud (real timing) and verifies GPS time/date outputs.
//
// IRIG-B simulation clock: CLK_FREQ=1000 (fast simulation)
// UART baud rate: 9600, CLK_FREQ=50MHz -> use BAUD_RATE=50000 to keep the
//   bit period short (50_000_000/50_000 = 1000 cycles/bit instead of 5208).
//
// To keep simulation fast, we use:
//   CLK_FREQ  = 50_000_000 (real value, but IRIG-B timing scaled)
//   We override CLK_FREQ for b_code_decoder but use a faster baud rate for UART.
//
// For top-level testing we use a dedicated smaller test approach:
//   - Test the NMEA parser directly (injecting bytes one-per-cycle)
//   - Test the B-code decoder with small CLK_FREQ as a unit test
//
// This testbench exercises the wiring of all sub-modules through the top module.
// IRIG-B timing: CLK_FREQ_B=1000, baud rate: CLK_FREQ_B/5 for quick UART.
// =============================================================================
`timescale 1ns/1ps

module tb_top;

    // -----------------------------------------------------------------------
    // Parameters: choose values that make simulation fast
    // -----------------------------------------------------------------------
    parameter CLK_FREQ         = 1_000;    // Small clock freq for fast IRIG-B sim
    parameter BAUD_RATE        = 100;      // 10 cycles per UART bit at 1 kHz
    parameter MAX_SENTENCE_LEN = 96;

    localparam CLK_PERIOD = 2;   // ns
    localparam UART_BIT_CYCLES = CLK_FREQ / BAUD_RATE;  // 10 cycles / bit

    // IRIG-B timing
    localparam BIT_PERIOD = CLK_FREQ / 100;   // 10 cycles/bit at 100 bits/s
    localparam PULSE_0    = CLK_FREQ * 2 / 1000;  // 2 cycles
    localparam PULSE_1    = CLK_FREQ * 5 / 1000;  // 5 cycles
    localparam PULSE_REF  = CLK_FREQ * 8 / 1000;  // 8 cycles

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    reg  clk, rst_n, b_code_in, gnss_rx;

    wire [5:0]  b_second, b_minute;
    wire [4:0]  b_hour;
    wire [8:0]  b_day_of_year;
    wire [6:0]  b_year;
    wire [3:0]  b_month;
    wire [4:0]  b_day;
    wire        b_is_leap, b_time_valid, b_pps;

    wire [2:0]  gps_sentence_type;
    wire [MAX_SENTENCE_LEN*8-1:0] gps_sentence_raw;
    wire [6:0]  gps_sentence_len;
    wire        gps_sentence_valid;
    wire [5:0]  gps_hour, gps_minute, gps_second;
    wire        gps_time_valid;
    wire [4:0]  gps_day;
    wire [3:0]  gps_month;
    wire [6:0]  gps_year;
    wire        gps_date_valid, gps_is_leap, gps_status;

    // BD/GA wires (present for port list, not actively checked here)
    wire [2:0]  bd_sentence_type; wire [MAX_SENTENCE_LEN*8-1:0] bd_sentence_raw;
    wire [6:0]  bd_sentence_len;  wire bd_sentence_valid;
    wire [5:0]  bd_hour, bd_minute, bd_second; wire bd_time_valid;
    wire [4:0]  bd_day; wire [3:0] bd_month; wire [6:0] bd_year;
    wire        bd_date_valid, bd_is_leap, bd_status;
    wire [2:0]  ga_sentence_type; wire [MAX_SENTENCE_LEN*8-1:0] ga_sentence_raw;
    wire [6:0]  ga_sentence_len;  wire ga_sentence_valid;
    wire [5:0]  ga_hour, ga_minute, ga_second; wire ga_time_valid;
    wire [4:0]  ga_day; wire [3:0] ga_month; wire [6:0] ga_year;
    wire        ga_date_valid, ga_is_leap, ga_status;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    top #(
        .CLK_FREQ         (CLK_FREQ),
        .BAUD_RATE        (BAUD_RATE),
        .MAX_SENTENCE_LEN (MAX_SENTENCE_LEN)
    ) dut (
        .clk                (clk),       .rst_n              (rst_n),
        .b_code_in          (b_code_in), .gnss_rx            (gnss_rx),
        .b_second           (b_second),  .b_minute           (b_minute),
        .b_hour             (b_hour),    .b_day_of_year      (b_day_of_year),
        .b_year             (b_year),    .b_month            (b_month),
        .b_day              (b_day),     .b_is_leap          (b_is_leap),
        .b_time_valid       (b_time_valid), .b_pps           (b_pps),
        .gps_sentence_type  (gps_sentence_type),
        .gps_sentence_raw   (gps_sentence_raw),
        .gps_sentence_len   (gps_sentence_len),
        .gps_sentence_valid (gps_sentence_valid),
        .gps_hour           (gps_hour),  .gps_minute         (gps_minute),
        .gps_second         (gps_second), .gps_time_valid    (gps_time_valid),
        .gps_day            (gps_day),   .gps_month          (gps_month),
        .gps_year           (gps_year),  .gps_date_valid     (gps_date_valid),
        .gps_is_leap        (gps_is_leap), .gps_status       (gps_status),
        .bd_sentence_type(bd_sentence_type), .bd_sentence_raw(bd_sentence_raw),
        .bd_sentence_len(bd_sentence_len),   .bd_sentence_valid(bd_sentence_valid),
        .bd_hour(bd_hour), .bd_minute(bd_minute), .bd_second(bd_second),
        .bd_time_valid(bd_time_valid),
        .bd_day(bd_day), .bd_month(bd_month), .bd_year(bd_year),
        .bd_date_valid(bd_date_valid), .bd_is_leap(bd_is_leap), .bd_status(bd_status),
        .ga_sentence_type(ga_sentence_type), .ga_sentence_raw(ga_sentence_raw),
        .ga_sentence_len(ga_sentence_len),   .ga_sentence_valid(ga_sentence_valid),
        .ga_hour(ga_hour), .ga_minute(ga_minute), .ga_second(ga_second),
        .ga_time_valid(ga_time_valid),
        .ga_day(ga_day), .ga_month(ga_month), .ga_year(ga_year),
        .ga_date_valid(ga_date_valid), .ga_is_leap(ga_is_leap), .ga_status(ga_status)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -----------------------------------------------------------------------
    // GPS sentence capture flag
    // -----------------------------------------------------------------------
    reg gps_got;
    always @(posedge clk) begin
        if (!rst_n)               gps_got <= 0;
        else if (gps_sentence_valid) gps_got <= 1;
    end

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
                $display("  PASS: %-24s = %0d", name, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: %-24s = %0d  (expected %0d)", name, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // IRIG-B bit emission task
    // -----------------------------------------------------------------------
    task emit_bbit;
        input [1:0] bit_val;
        integer     pulse_len;
        begin
            case (bit_val)
                2'd0:    pulse_len = PULSE_0;
                2'd1:    pulse_len = PULSE_1;
                default: pulse_len = PULSE_REF;
            endcase
            @(negedge clk); b_code_in = 1'b1;
            repeat (pulse_len)              @(posedge clk);
            @(negedge clk); b_code_in = 1'b0;
            repeat (BIT_PERIOD - pulse_len) @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // IRIG-B frame task:
    //   sec=10 (tens=1->bit6, units=0)
    //   min=20 (tens=2->bit16, units=0)
    //   hr=8   (tens=0, units=8->bit23)
    //   doy=60 (tens=6->bit36+bit37, units=0)
    //   yr=24  (tens=2->bit65, units=4->bit62)
    //   DoY 60, leap year 2024: Jan(31)+Feb(29)=60 -> Feb 29
    // -----------------------------------------------------------------------
    task emit_irigb_frame;
        begin
            emit_bbit(2'd2); // P0

            // Bits 1-4: sec units=0
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            // Bit 5
            emit_bbit(2'd0);
            // Bits 6-7: sec tens=1 (10=bit6)
            emit_bbit(2'd1); emit_bbit(2'd0); // bit6=1 (w=10), bit7=0 (w=20)
            // Bit 8
            emit_bbit(2'd0);

            emit_bbit(2'd2); // P1

            // Bits 10-13: min units=0
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            // Bit 14
            emit_bbit(2'd0);
            // Bits 15-17: min tens=2 (20=bit16)
            emit_bbit(2'd0); emit_bbit(2'd1); emit_bbit(2'd0); // bit15=0(w10),bit16=1(w20),bit17=0(w40)
            // Bit 18
            emit_bbit(2'd0);

            emit_bbit(2'd2); // P2

            // Bits 20-23: hr units=8 (bit23)
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd1);
            // Bit 24
            emit_bbit(2'd0);
            // Bits 25-26: hr tens=0
            emit_bbit(2'd0); emit_bbit(2'd0);
            // Bits 27-28
            emit_bbit(2'd0); emit_bbit(2'd0);

            emit_bbit(2'd2); // P3

            // Bits 30-33: doy units=0
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            // Bit 34
            emit_bbit(2'd0);
            // Bits 35-38: doy tens=6 (20+40=60 -> bit36 and bit37)
            emit_bbit(2'd0); // bit35: w=10 CLR
            emit_bbit(2'd1); // bit36: w=20 SET
            emit_bbit(2'd1); // bit37: w=40 SET
            emit_bbit(2'd0); // bit38: w=80 CLR

            emit_bbit(2'd2); // P4

            // Bits 40-41: doy hundreds=0
            emit_bbit(2'd0); emit_bbit(2'd0);
            // Bits 42-48
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);

            emit_bbit(2'd2); // P5

            // Bits 50-58
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);

            emit_bbit(2'd2); // P6

            // Bits 60-63: yr units=4 (bit62)
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd1); emit_bbit(2'd0);
            // Bits 64-67: yr tens=2 (20=bit65)
            emit_bbit(2'd0); emit_bbit(2'd1); emit_bbit(2'd0); emit_bbit(2'd0);
            // Bit 68: LSP
            emit_bbit(2'd0);

            emit_bbit(2'd2); // P7 (bit 69)

            // Bits 70-78
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);

            emit_bbit(2'd2); // P8 (bit 79)

            // Bits 80-98
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            emit_bbit(2'd0); emit_bbit(2'd0); emit_bbit(2'd0);
            emit_bbit(2'd0);

            emit_bbit(2'd2); // P9 (bit 99)
        end
    endtask

    // -----------------------------------------------------------------------
    // UART byte transmission (8N1, LSB first)
    // -----------------------------------------------------------------------
    task uart_send_byte;
        input [7:0] data;
        integer     i;
        begin
            // Start bit
            gnss_rx = 1'b0;
            repeat (UART_BIT_CYCLES) @(posedge clk);
            // 8 data bits LSB first
            for (i = 0; i < 8; i = i + 1) begin
                gnss_rx = data[i];
                repeat (UART_BIT_CYCLES) @(posedge clk);
            end
            // Stop bit
            gnss_rx = 1'b1;
            repeat (UART_BIT_CYCLES) @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Test flow
    // -----------------------------------------------------------------------
    initial begin
        pass_count = 0; fail_count = 0;
        b_code_in = 0;
        gnss_rx   = 1'b1;  // UART idle = high
        gps_got   = 0;
        rst_n     = 0;
        repeat (10) @(posedge clk);
        #1; rst_n = 1;
        repeat (5)  @(posedge clk);

        $display("=======================================================");
        $display("  Top-Level Integration Testbench");
        $display("=======================================================");

        // ==================================================================
        // PART 1: IRIG-B decoder via top module
        // Frame: sec=10, min=20, hr=8, doy=60, yr=24 (2024, leap year)
        // doy=60 in 2024: Jan(31)+Feb(29)=60 -> Feb 29 (leap day!)
        // ==================================================================
        $display("\n[PART 1] IRIG-B decoder (8 frames to sync)");
        repeat (8) emit_irigb_frame();
        repeat (10) @(posedge clk);

        check_val("b_time_valid",  b_time_valid,  1);
        check_val("b_second",      b_second,      10);
        check_val("b_minute",      b_minute,      20);
        check_val("b_hour",        b_hour,        8);
        check_val("b_day_of_year", b_day_of_year, 60);
        check_val("b_year",        b_year,        24);
        check_val("b_is_leap",     b_is_leap,     1);   // 2024 is leap
        check_val("b_month",       b_month,       2);   // February
        check_val("b_day",         b_day,         29);  // Feb 29!

        // ==================================================================
        // PART 2: GNSS via UART -> top module -> nmea_parser
        // $GPRMC,092751.000,A,...,280511,,,A*45
        // Expected: gps_hour=9, gps_min=27, gps_sec=51, day=28, mo=5, yr=11
        // ==================================================================
        $display("\n[PART 2] GPS NMEA via UART ($GPRMC)");

        uart_send_byte("$");
        uart_send_byte("G"); uart_send_byte("P");
        uart_send_byte("R"); uart_send_byte("M"); uart_send_byte("C");
        uart_send_byte(",");
        uart_send_byte("0"); uart_send_byte("9"); uart_send_byte("2");
        uart_send_byte("7"); uart_send_byte("5"); uart_send_byte("1");
        uart_send_byte("."); uart_send_byte("0"); uart_send_byte("0");
        uart_send_byte("0"); uart_send_byte(","); uart_send_byte("A");
        uart_send_byte(",");
        uart_send_byte("5"); uart_send_byte("3"); uart_send_byte("2");
        uart_send_byte("1"); uart_send_byte("."); uart_send_byte("6");
        uart_send_byte("8"); uart_send_byte("0"); uart_send_byte("2");
        uart_send_byte(","); uart_send_byte("N"); uart_send_byte(",");
        uart_send_byte("0"); uart_send_byte("0"); uart_send_byte("6");
        uart_send_byte("3"); uart_send_byte("0"); uart_send_byte(".");
        uart_send_byte("3"); uart_send_byte("3"); uart_send_byte("7");
        uart_send_byte("1"); uart_send_byte(","); uart_send_byte("W");
        uart_send_byte(",");
        uart_send_byte("0"); uart_send_byte("."); uart_send_byte("0");
        uart_send_byte("6"); uart_send_byte(",");
        uart_send_byte("3"); uart_send_byte("1"); uart_send_byte(".");
        uart_send_byte("6"); uart_send_byte("6"); uart_send_byte(",");
        uart_send_byte("2"); uart_send_byte("8"); uart_send_byte("0");
        uart_send_byte("5"); uart_send_byte("1"); uart_send_byte("1");
        uart_send_byte(","); uart_send_byte(","); uart_send_byte(",");
        uart_send_byte("A");
        uart_send_byte("*"); uart_send_byte("4"); uart_send_byte("5");
        uart_send_byte(8'h0D); uart_send_byte(8'h0A);

        // Wait for GPS valid
        begin : wait_gps
            integer to;
            to = 50000;
            while (!gps_got && to > 0) begin @(posedge clk); to = to - 1; end
            if (to == 0) $display("  WARNING: GPS valid timed out");
        end

        check_val("gps_sentence_valid", gps_got,         1);   // captured pulse
        check_val("gps_time_valid",     gps_time_valid,     1);
        check_val("gps_hour",           gps_hour,           9);
        check_val("gps_minute",         gps_minute,         27);
        check_val("gps_second",         gps_second,         51);
        check_val("gps_date_valid",     gps_date_valid,     1);
        check_val("gps_day",            gps_day,            28);
        check_val("gps_month",          gps_month,          5);
        check_val("gps_year",           gps_year,           11);
        check_val("gps_status",         gps_status,         1);
        check_val("gps_is_leap",        gps_is_leap,        0);  // 2011 not leap

        // ==================================================================
        // Summary
        // ==================================================================
        $display("\n=======================================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0) $display("  ALL TESTS PASSED");
        else                 $display("  SOME TESTS FAILED");
        $display("=======================================================");
        $finish;
    end

    initial begin
        #10_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
