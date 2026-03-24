// =============================================================================
// Module: top
// Description: Top-level integration module for the GNSS/B-code time receiver.
//
// This module integrates all sub-components:
//   1. b_code_decoder  - Decodes IRIG-B timecode from b_code_in, outputs UTC time
//   2. uart_rx         - Receives NMEA bytes from the GNSS receiver UART line
//   3. nmea_parser     - Parses NMEA sentences and extracts per-constellation time
//
// External interfaces:
//   b_code_in   - IRIG-B digital pulse-width-modulated signal (idle low)
//   gnss_rx     - UART RX line from a GNSS receiver (NMEA-0183, 9600 baud default)
//
// All time/date outputs are in binary (not BCD).
// Leap-year flags are combinationally derived from the year value.
//
// Parameters:
//   CLK_FREQ          - System clock frequency in Hz   (default 50 MHz)
//   BAUD_RATE         - GNSS UART baud rate            (default 9600)
//   MAX_SENTENCE_LEN  - Max NMEA sentence buffer size  (default 96 bytes)
// =============================================================================
module top #(
    parameter CLK_FREQ         = 50_000_000,
    parameter BAUD_RATE        = 9600,
    parameter MAX_SENTENCE_LEN = 96
)(
    input  wire        clk,     // System clock (CLK_FREQ Hz)
    input  wire        rst_n,   // Active-low synchronous reset

    // -----------------------------------------------------------------------
    // External signal inputs
    // -----------------------------------------------------------------------
    input  wire        b_code_in,  // IRIG-B digital timecode input
    input  wire        gnss_rx,    // GNSS UART RX (NMEA-0183)

    // -----------------------------------------------------------------------
    // IRIG-B decoded outputs
    // -----------------------------------------------------------------------
    output wire [5:0]  b_second,       // 0-59
    output wire [5:0]  b_minute,       // 0-59
    output wire [4:0]  b_hour,         // 0-23
    output wire [8:0]  b_day_of_year,  // 1-366
    output wire [6:0]  b_year,         // 2-digit year (0-99, represents 2000-2099)
    output wire [3:0]  b_month,        // Calendar month  1-12
    output wire [4:0]  b_day,          // Calendar day    1-31
    output wire        b_is_leap,      // 1 = current year is a leap year
    output wire        b_time_valid,   // 1 = B-code time outputs are valid
    output wire        b_pps,          // 1 PPS pulse (one cycle at each frame start)

    // -----------------------------------------------------------------------
    // GPS (GP talker) outputs
    // -----------------------------------------------------------------------
    output wire [2:0]  gps_sentence_type,
    output wire [MAX_SENTENCE_LEN*8-1:0] gps_sentence_raw,
    output wire [6:0]  gps_sentence_len,
    output wire        gps_sentence_valid,

    output wire [5:0]  gps_hour,
    output wire [5:0]  gps_minute,
    output wire [5:0]  gps_second,
    output wire        gps_time_valid,

    output wire [4:0]  gps_day,
    output wire [3:0]  gps_month,
    output wire [6:0]  gps_year,
    output wire        gps_date_valid,
    output wire        gps_is_leap,
    output wire        gps_status,     // 1=Active, 0=Void

    // -----------------------------------------------------------------------
    // BeiDou (GB/BD talker) outputs
    // -----------------------------------------------------------------------
    output wire [2:0]  bd_sentence_type,
    output wire [MAX_SENTENCE_LEN*8-1:0] bd_sentence_raw,
    output wire [6:0]  bd_sentence_len,
    output wire        bd_sentence_valid,

    output wire [5:0]  bd_hour,
    output wire [5:0]  bd_minute,
    output wire [5:0]  bd_second,
    output wire        bd_time_valid,

    output wire [4:0]  bd_day,
    output wire [3:0]  bd_month,
    output wire [6:0]  bd_year,
    output wire        bd_date_valid,
    output wire        bd_is_leap,
    output wire        bd_status,

    // -----------------------------------------------------------------------
    // Galileo (GA talker) outputs
    // -----------------------------------------------------------------------
    output wire [2:0]  ga_sentence_type,
    output wire [MAX_SENTENCE_LEN*8-1:0] ga_sentence_raw,
    output wire [6:0]  ga_sentence_len,
    output wire        ga_sentence_valid,

    output wire [5:0]  ga_hour,
    output wire [5:0]  ga_minute,
    output wire [5:0]  ga_second,
    output wire        ga_time_valid,

    output wire [4:0]  ga_day,
    output wire [3:0]  ga_month,
    output wire [6:0]  ga_year,
    output wire        ga_date_valid,
    output wire        ga_is_leap,
    output wire        ga_status
);

    // -----------------------------------------------------------------------
    // Internal UART RX → NMEA parser connections
    // -----------------------------------------------------------------------
    wire [7:0] uart_data;
    wire       uart_valid;

    // -----------------------------------------------------------------------
    // IRIG-B decoder instance
    // -----------------------------------------------------------------------
    b_code_decoder #(
        .CLK_FREQ (CLK_FREQ)
    ) u_b_code (
        .clk         (clk),
        .rst_n       (rst_n),
        .b_code_in   (b_code_in),
        .second      (b_second),
        .minute      (b_minute),
        .hour        (b_hour),
        .day_of_year (b_day_of_year),
        .year        (b_year),
        .month       (b_month),
        .day         (b_day),
        .is_leap     (b_is_leap),
        .time_valid  (b_time_valid),
        .pps_out     (b_pps)
    );

    // -----------------------------------------------------------------------
    // UART receiver instance (for GNSS NMEA stream)
    // -----------------------------------------------------------------------
    uart_rx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx         (gnss_rx),
        .data       (uart_data),
        .data_valid (uart_valid)
    );

    // -----------------------------------------------------------------------
    // NMEA parser instance
    // -----------------------------------------------------------------------
    nmea_parser #(
        .MAX_SENTENCE_LEN (MAX_SENTENCE_LEN)
    ) u_nmea (
        .clk                (clk),
        .rst_n              (rst_n),
        .rx_data            (uart_data),
        .rx_valid           (uart_valid),

        // GPS
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

        // BeiDou
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

        // Galileo
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

endmodule
