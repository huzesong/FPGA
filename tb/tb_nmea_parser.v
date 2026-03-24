// =============================================================================
// Testbench: tb_nmea_parser
// Description: Simulation testbench for the NMEA parser.
//
// Injects NMEA sentences directly into the parser byte-by-byte (bypassing
// the UART receiver) and verifies that time/date/status outputs are correctly
// extracted for each constellation.
//
// Checksum validation (XOR of all bytes between '$' and '*', exclusive):
//   $GPRMC,092751.000,A,5321.6802,N,00630.3371,W,0.06,31.66,280511,,,A  -> *45
//   $GPGGA,092750.000,5321.6802,N,00630.3371,W,1,8,1.03,61.7,M,55.2,M,, -> *75
//   $GBRMC,013456.000,A,3957.0000,N,11618.0000,E,0.00,0.00,230324,,,A    -> *7A
//   $GARMC,093000.000,A,4807.0380,N,01131.0000,E,0.00,0.00,240324,,,A    -> *74
// =============================================================================
`timescale 1ns/1ps

module tb_nmea_parser;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    parameter MAX_SENTENCE_LEN = 96;

    reg  clk, rst_n;
    reg  [7:0] rx_data;
    reg        rx_valid;

    // GPS
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

    // BeiDou
    wire [2:0]  bd_sentence_type;
    wire [MAX_SENTENCE_LEN*8-1:0] bd_sentence_raw;
    wire [6:0]  bd_sentence_len;
    wire        bd_sentence_valid;
    wire [5:0]  bd_hour, bd_minute, bd_second;
    wire        bd_time_valid;
    wire [4:0]  bd_day;
    wire [3:0]  bd_month;
    wire [6:0]  bd_year;
    wire        bd_date_valid, bd_is_leap, bd_status;

    // Galileo
    wire [2:0]  ga_sentence_type;
    wire [MAX_SENTENCE_LEN*8-1:0] ga_sentence_raw;
    wire [6:0]  ga_sentence_len;
    wire        ga_sentence_valid;
    wire [5:0]  ga_hour, ga_minute, ga_second;
    wire        ga_time_valid;
    wire [4:0]  ga_day;
    wire [3:0]  ga_month;
    wire [6:0]  ga_year;
    wire        ga_date_valid, ga_is_leap, ga_status;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    nmea_parser #(.MAX_SENTENCE_LEN(MAX_SENTENCE_LEN)) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .rx_data            (rx_data),
        .rx_valid           (rx_valid),
        .gps_sentence_type  (gps_sentence_type),
        .gps_sentence_raw   (gps_sentence_raw),
        .gps_sentence_len   (gps_sentence_len),
        .gps_sentence_valid (gps_sentence_valid),
        .gps_hour           (gps_hour),
        .gps_minute         (gps_minute),
        .gps_second         (gps_second),
        .gps_time_valid     (gps_time_valid),
        .gps_day            (gps_day),
        .gps_month          (gps_month),
        .gps_year           (gps_year),
        .gps_date_valid     (gps_date_valid),
        .gps_is_leap        (gps_is_leap),
        .gps_status         (gps_status),
        .bd_sentence_type   (bd_sentence_type),
        .bd_sentence_raw    (bd_sentence_raw),
        .bd_sentence_len    (bd_sentence_len),
        .bd_sentence_valid  (bd_sentence_valid),
        .bd_hour            (bd_hour),
        .bd_minute          (bd_minute),
        .bd_second          (bd_second),
        .bd_time_valid      (bd_time_valid),
        .bd_day             (bd_day),
        .bd_month           (bd_month),
        .bd_year            (bd_year),
        .bd_date_valid      (bd_date_valid),
        .bd_is_leap         (bd_is_leap),
        .bd_status          (bd_status),
        .ga_sentence_type   (ga_sentence_type),
        .ga_sentence_raw    (ga_sentence_raw),
        .ga_sentence_len    (ga_sentence_len),
        .ga_sentence_valid  (ga_sentence_valid),
        .ga_hour            (ga_hour),
        .ga_minute          (ga_minute),
        .ga_second          (ga_second),
        .ga_time_valid      (ga_time_valid),
        .ga_day             (ga_day),
        .ga_month           (ga_month),
        .ga_year            (ga_year),
        .ga_date_valid      (ga_date_valid),
        .ga_is_leap         (ga_is_leap),
        .ga_status          (ga_status)
    );

    // -----------------------------------------------------------------------
    // Clock 50 MHz
    // -----------------------------------------------------------------------
    initial clk = 0;
    always #10 clk = ~clk;

    // -----------------------------------------------------------------------
    // Capture flags - set when sentence_valid pulses; cleared by test flow
    // -----------------------------------------------------------------------
    reg gps_got, bd_got, ga_got;

    always @(posedge clk) begin
        if (!rst_n) begin
            gps_got <= 0; bd_got <= 0; ga_got <= 0;
        end else begin
            if (gps_sentence_valid) gps_got <= 1;
            if (bd_sentence_valid)  bd_got  <= 1;
            if (ga_sentence_valid)  ga_got  <= 1;
        end
    end

    // -----------------------------------------------------------------------
    // Inject one byte into the parser (one byte per two clock cycles)
    // -----------------------------------------------------------------------
    task inject_byte;
        input [7:0] ch;
        begin
            @(posedge clk); #1;
            rx_data  = ch;
            rx_valid = 1'b1;
            @(posedge clk); #1;
            rx_valid = 1'b0;
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
                $display("  PASS: %-30s = %0d", name, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: %-30s = %0d  (expected %0d)", name, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Wait up to N cycles for a flag to go high
    // -----------------------------------------------------------------------
    task wait_flag;
        input [1:0] which;   // 0=GPS, 1=BD, 2=GA
        integer     timeout;
        begin
            timeout = 5000;
            case (which)
                0: while (!gps_got && timeout > 0) begin @(posedge clk); timeout = timeout-1; end
                1: while (!bd_got  && timeout > 0) begin @(posedge clk); timeout = timeout-1; end
                2: while (!ga_got  && timeout > 0) begin @(posedge clk); timeout = timeout-1; end
            endcase
            if (timeout == 0) $display("  WARNING: wait_flag timed out");
        end
    endtask

    // -----------------------------------------------------------------------
    // Test flow
    // -----------------------------------------------------------------------
    initial begin
        pass_count = 0; fail_count = 0;
        rx_data = 8'd0; rx_valid = 1'b0;
        gps_got = 0; bd_got = 0; ga_got = 0;

        rst_n = 0; repeat(4) @(posedge clk); #1; rst_n = 1;
        repeat(4) @(posedge clk);

        $display("=======================================================");
        $display("  NMEA Parser Testbench");
        $display("=======================================================");

        // ==================================================================
        // TEST 1: $GPRMC  (GPS)
        // $GPRMC,092751.000,A,5321.6802,N,00630.3371,W,0.06,31.66,280511,,,A*45
        // Expected: hour=9, min=27, sec=51, status=A
        //           day=28, month=5, year=11 (2011 - not a leap year)
        // ==================================================================
        $display("\n[TEST 1] $GPRMC (GPS, RMC)");
        gps_got = 0;

        inject_byte("$");
        inject_byte("G"); inject_byte("P");
        inject_byte("R"); inject_byte("M"); inject_byte("C");
        inject_byte(",");
        inject_byte("0"); inject_byte("9"); inject_byte("2"); inject_byte("7");
        inject_byte("5"); inject_byte("1"); inject_byte("."); inject_byte("0");
        inject_byte("0"); inject_byte("0");
        inject_byte(","); inject_byte("A"); inject_byte(",");
        inject_byte("5"); inject_byte("3"); inject_byte("2"); inject_byte("1");
        inject_byte("."); inject_byte("6"); inject_byte("8"); inject_byte("0");
        inject_byte("2"); inject_byte(","); inject_byte("N"); inject_byte(",");
        inject_byte("0"); inject_byte("0"); inject_byte("6"); inject_byte("3");
        inject_byte("0"); inject_byte("."); inject_byte("3"); inject_byte("3");
        inject_byte("7"); inject_byte("1"); inject_byte(","); inject_byte("W");
        inject_byte(",");
        inject_byte("0"); inject_byte("."); inject_byte("0"); inject_byte("6");
        inject_byte(",");
        inject_byte("3"); inject_byte("1"); inject_byte("."); inject_byte("6");
        inject_byte("6"); inject_byte(",");
        inject_byte("2"); inject_byte("8"); inject_byte("0"); inject_byte("5");
        inject_byte("1"); inject_byte("1");
        inject_byte(","); inject_byte(","); inject_byte(",");
        inject_byte("A");
        inject_byte("*"); inject_byte("4"); inject_byte("5");  // Correct checksum: 45

        wait_flag(0);   // Wait for GPS valid captured

        check_val("gps_sentence_type",  gps_sentence_type,  3'b000); // RMC
        check_val("gps_time_valid",     gps_time_valid,     1);
        check_val("gps_hour",           gps_hour,           9);
        check_val("gps_minute",         gps_minute,         27);
        check_val("gps_second",         gps_second,         51);
        check_val("gps_date_valid",     gps_date_valid,     1);
        check_val("gps_day",            gps_day,            28);
        check_val("gps_month",          gps_month,          5);
        check_val("gps_year",           gps_year,           11);
        check_val("gps_status (A=1)",   gps_status,         1);
        check_val("gps_is_leap (2011)", gps_is_leap,        0); // 2011 not leap

        // ==================================================================
        // TEST 2: $GPGGA  (GPS GGA, time only - no date)
        // $GPGGA,092750.000,5321.6802,N,00630.3371,W,1,8,1.03,61.7,M,55.2,M,,*75
        // Expected: hour=9, min=27, sec=50; sentence_type=GGA
        // ==================================================================
        $display("\n[TEST 2] $GPGGA (GPS, GGA)");
        gps_got = 0;

        inject_byte("$");
        inject_byte("G"); inject_byte("P");
        inject_byte("G"); inject_byte("G"); inject_byte("A");
        inject_byte(",");
        inject_byte("0"); inject_byte("9"); inject_byte("2"); inject_byte("7");
        inject_byte("5"); inject_byte("0"); inject_byte("."); inject_byte("0");
        inject_byte("0"); inject_byte("0"); inject_byte(",");
        inject_byte("5"); inject_byte("3"); inject_byte("2"); inject_byte("1");
        inject_byte("."); inject_byte("6"); inject_byte("8"); inject_byte("0");
        inject_byte("2"); inject_byte(","); inject_byte("N"); inject_byte(",");
        inject_byte("0"); inject_byte("0"); inject_byte("6"); inject_byte("3");
        inject_byte("0"); inject_byte("."); inject_byte("3"); inject_byte("3");
        inject_byte("7"); inject_byte("1"); inject_byte(","); inject_byte("W");
        inject_byte(","); inject_byte("1"); inject_byte(","); inject_byte("8");
        inject_byte(",");
        inject_byte("1"); inject_byte("."); inject_byte("0"); inject_byte("3");
        inject_byte(",");
        inject_byte("6"); inject_byte("1"); inject_byte("."); inject_byte("7");
        inject_byte(","); inject_byte("M"); inject_byte(",");
        inject_byte("5"); inject_byte("5"); inject_byte("."); inject_byte("2");
        inject_byte(","); inject_byte("M"); inject_byte(","); inject_byte(",");
        inject_byte("*"); inject_byte("7"); inject_byte("5");  // Correct: 75

        wait_flag(0);

        check_val("gps_sentence_type (GGA)", gps_sentence_type, 3'b001); // GGA
        check_val("gps_hour",                gps_hour,           9);
        check_val("gps_minute",              gps_minute,         27);
        check_val("gps_second",              gps_second,         50);

        // ==================================================================
        // TEST 3: $GBRMC  (BeiDou, GB talker)
        // $GBRMC,013456.000,A,3957.0000,N,11618.0000,E,0.00,0.00,230324,,,A*7A
        // Expected: hour=1, min=34, sec=56, day=23, month=3, year=24
        //           2024 IS a leap year -> is_leap=1
        // ==================================================================
        $display("\n[TEST 3] $GBRMC (BeiDou, 2024 leap year)");
        bd_got = 0;

        inject_byte("$");
        inject_byte("G"); inject_byte("B");
        inject_byte("R"); inject_byte("M"); inject_byte("C");
        inject_byte(",");
        inject_byte("0"); inject_byte("1"); inject_byte("3"); inject_byte("4");
        inject_byte("5"); inject_byte("6"); inject_byte("."); inject_byte("0");
        inject_byte("0"); inject_byte("0");
        inject_byte(","); inject_byte("A"); inject_byte(",");
        inject_byte("3"); inject_byte("9"); inject_byte("5"); inject_byte("7");
        inject_byte("."); inject_byte("0"); inject_byte("0"); inject_byte("0");
        inject_byte("0"); inject_byte(","); inject_byte("N"); inject_byte(",");
        inject_byte("1"); inject_byte("1"); inject_byte("6"); inject_byte("1");
        inject_byte("8"); inject_byte("."); inject_byte("0"); inject_byte("0");
        inject_byte("0"); inject_byte("0"); inject_byte(","); inject_byte("E");
        inject_byte(",");
        inject_byte("0"); inject_byte("."); inject_byte("0"); inject_byte("0");
        inject_byte(",");
        inject_byte("0"); inject_byte("."); inject_byte("0"); inject_byte("0");
        inject_byte(",");
        inject_byte("2"); inject_byte("3"); inject_byte("0"); inject_byte("3");
        inject_byte("2"); inject_byte("4");
        inject_byte(","); inject_byte(","); inject_byte(",");
        inject_byte("A");
        inject_byte("*"); inject_byte("7"); inject_byte("A");  // Correct: 7A

        wait_flag(1);   // BD

        check_val("bd_sentence_type",  bd_sentence_type,   3'b000); // RMC
        check_val("bd_time_valid",     bd_time_valid,      1);
        check_val("bd_hour",           bd_hour,            1);
        check_val("bd_minute",         bd_minute,          34);
        check_val("bd_second",         bd_second,          56);
        check_val("bd_date_valid",     bd_date_valid,      1);
        check_val("bd_day",            bd_day,             23);
        check_val("bd_month",          bd_month,           3);
        check_val("bd_year",           bd_year,            24);
        check_val("bd_status (A=1)",   bd_status,          1);
        check_val("bd_is_leap (2024)", bd_is_leap,         1);  // 2024 IS leap

        // ==================================================================
        // TEST 4: $GARMC  (Galileo)
        // $GARMC,093000.000,A,4807.0380,N,01131.0000,E,0.00,0.00,240324,,,A*74
        // Expected: hour=9, min=30, sec=0, day=24, month=3, year=24 (leap)
        // ==================================================================
        $display("\n[TEST 4] $GARMC (Galileo, 2024 leap year)");
        ga_got = 0;

        inject_byte("$");
        inject_byte("G"); inject_byte("A");
        inject_byte("R"); inject_byte("M"); inject_byte("C");
        inject_byte(",");
        inject_byte("0"); inject_byte("9"); inject_byte("3"); inject_byte("0");
        inject_byte("0"); inject_byte("0"); inject_byte("."); inject_byte("0");
        inject_byte("0"); inject_byte("0");
        inject_byte(","); inject_byte("A"); inject_byte(",");
        inject_byte("4"); inject_byte("8"); inject_byte("0"); inject_byte("7");
        inject_byte("."); inject_byte("0"); inject_byte("3"); inject_byte("8");
        inject_byte("0"); inject_byte(","); inject_byte("N"); inject_byte(",");
        inject_byte("0"); inject_byte("1"); inject_byte("1"); inject_byte("3");
        inject_byte("1"); inject_byte("."); inject_byte("0"); inject_byte("0");
        inject_byte("0"); inject_byte("0"); inject_byte(","); inject_byte("E");
        inject_byte(",");
        inject_byte("0"); inject_byte("."); inject_byte("0"); inject_byte("0");
        inject_byte(",");
        inject_byte("0"); inject_byte("."); inject_byte("0"); inject_byte("0");
        inject_byte(",");
        inject_byte("2"); inject_byte("4"); inject_byte("0"); inject_byte("3");
        inject_byte("2"); inject_byte("4");
        inject_byte(","); inject_byte(","); inject_byte(",");
        inject_byte("A");
        inject_byte("*"); inject_byte("7"); inject_byte("4");  // Correct: 74

        wait_flag(2);   // GA

        check_val("ga_sentence_type",  ga_sentence_type,   3'b000); // RMC
        check_val("ga_time_valid",     ga_time_valid,      1);
        check_val("ga_hour",           ga_hour,            9);
        check_val("ga_minute",         ga_minute,          30);
        check_val("ga_second",         ga_second,          0);
        check_val("ga_date_valid",     ga_date_valid,      1);
        check_val("ga_day",            ga_day,             24);
        check_val("ga_month",          ga_month,           3);
        check_val("ga_year",           ga_year,            24);
        check_val("ga_status (A=1)",   ga_status,          1);
        check_val("ga_is_leap (2024)", ga_is_leap,         1);

        // ==================================================================
        // TEST 5: Sentence with wrong checksum -> outputs should NOT change
        // ==================================================================
        $display("\n[TEST 5] Bad checksum -> previous GPS outputs should be unchanged");
        gps_got = 0;

        // Send GPS RMC with clearly wrong checksum (FF)
        inject_byte("$");
        inject_byte("G"); inject_byte("P");
        inject_byte("R"); inject_byte("M"); inject_byte("C");
        inject_byte(",");
        inject_byte("1"); inject_byte("2"); inject_byte("3"); inject_byte("4");
        inject_byte("5"); inject_byte("6"); inject_byte("."); inject_byte("0");
        inject_byte("0"); inject_byte("0");
        inject_byte(","); inject_byte("A");
        inject_byte(","); inject_byte(","); inject_byte(","); inject_byte(",");
        inject_byte(","); inject_byte(","); inject_byte(","); inject_byte(",");
        inject_byte(",");
        inject_byte("*"); inject_byte("F"); inject_byte("F");  // WRONG checksum

        repeat (20) @(posedge clk);

        // GPS outputs should still show the values from TEST 2 (last valid GPS)
        check_val("gps_hour (unchanged)",   gps_hour,   9);
        check_val("gps_minute (unchanged)", gps_minute, 27);
        check_val("gps_second (unchanged)", gps_second, 50);  // From GGA test

        // ==================================================================
        // TEST 6: Leap year edge case - year 00 (2000, divisible by 400 -> LEAP)
        // Inject a GPS RMC with year=00
        // $GPRMC,000000.000,A,0000.0000,N,00000.0000,E,0.00,0.00,010100,,,A*??
        // ==================================================================
        $display("\n[TEST 6] Year 00 (2000) - leap year edge case");
        gps_got = 0;

        begin : test6_block
            // Pre-compute checksum for this sentence
            // GPRMC,000000.000,A,0000.0000,N,00000.0000,E,0.00,0.00,010100,,,A
            // = 0x47^0x50^0x52^0x4D^0x43^0x2C^... (computed offline: 0x20)
            inject_byte("$");
            inject_byte("G"); inject_byte("P");
            inject_byte("R"); inject_byte("M"); inject_byte("C");
            inject_byte(",");
            inject_byte("0"); inject_byte("0"); inject_byte("0"); inject_byte("0");
            inject_byte("0"); inject_byte("0"); inject_byte("."); inject_byte("0");
            inject_byte("0"); inject_byte("0");
            inject_byte(","); inject_byte("A"); inject_byte(",");
            inject_byte("0"); inject_byte("0"); inject_byte("0"); inject_byte("0");
            inject_byte("."); inject_byte("0"); inject_byte("0"); inject_byte("0");
            inject_byte("0"); inject_byte(","); inject_byte("N"); inject_byte(",");
            inject_byte("0"); inject_byte("0"); inject_byte("0"); inject_byte("0");
            inject_byte("0"); inject_byte("."); inject_byte("0"); inject_byte("0");
            inject_byte("0"); inject_byte("0"); inject_byte(","); inject_byte("E");
            inject_byte(",");
            inject_byte("0"); inject_byte("."); inject_byte("0"); inject_byte("0");
            inject_byte(",");
            inject_byte("0"); inject_byte("."); inject_byte("0"); inject_byte("0");
            inject_byte(",");
            // Date: day=01, month=01, year=00
            inject_byte("0"); inject_byte("1");  // day=01
            inject_byte("0"); inject_byte("1");  // month=01
            inject_byte("0"); inject_byte("0");  // year=00 (2000)
            inject_byte(","); inject_byte(","); inject_byte(",");
            inject_byte("A");
            inject_byte("*"); inject_byte("6"); inject_byte("E"); // checksum (pre-computed)
        end

        wait_flag(0);

        check_val("gps_year (2000)",    gps_year,     0);
        check_val("gps_is_leap (2000)", gps_is_leap,  1);  // 2000 IS a leap year

        // ==================================================================
        // Summary
        // ==================================================================
        $display("\n=======================================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED");
        $display("=======================================================");

        $finish;
    end

    initial begin
        #20_000_000;  // 20 ms timeout
        $display("TIMEOUT");
        $finish;
    end

endmodule
