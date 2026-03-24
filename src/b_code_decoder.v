// =============================================================================
// Module: b_code_decoder
// Description: IRIG-B Timecode Decoder
//
// Decodes an IRIG-B digital timecode signal and outputs UTC time fields.
// Supports IRIG-B standard (100 bits/second, pulse-width modulated):
//
//   Bit encoding (pulse high duration):
//     Logic 0   : ~2 ms  (100 000 cycles @ 50 MHz)
//     Logic 1   : ~5 ms  (250 000 cycles @ 50 MHz)
//     Reference : ~8 ms  (400 000 cycles @ 50 MHz)
//
//   Frame layout (100 bits, 1 frame = 1 second):
//     Bit  0       : P0  (frame reference marker)
//     Bits  1- 4   : Seconds  units BCD  (weights 1,2,4,8)
//     Bit   5      : 0
//     Bits  6- 7   : Seconds  tens  BCD  (weights 10,20)
//     Bit   8      : 0
//     Bit   9      : P1  (reference)
//     Bits 10-13   : Minutes  units BCD  (weights 1,2,4,8)
//     Bit  14      : 0
//     Bits 15-17   : Minutes  tens  BCD  (weights 10,20,40)
//     Bit  18      : 0
//     Bit  19      : P2  (reference)
//     Bits 20-23   : Hours    units BCD  (weights 1,2,4,8)
//     Bit  24      : 0
//     Bits 25-26   : Hours    tens  BCD  (weights 10,20)
//     Bits 27-28   : 0
//     Bit  29      : P3  (reference)
//     Bits 30-33   : Day-of-year units BCD  (weights 1,2,4,8)
//     Bit  34      : 0
//     Bits 35-38   : Day-of-year tens  BCD  (weights 10,20,40,80)
//     Bit  39      : P4  (reference)
//     Bits 40-41   : Day-of-year hundreds BCD  (weights 100,200)
//     Bits 42-48   : Straight Binary Seconds / control
//     Bit  49      : P5  (reference)
//     Bits 50-58   : SBS (continued)
//     Bit  59      : P6  (reference)
//     Bits 60-63   : Year units BCD  (weights 1,2,4,8)
//     Bits 64-67   : Year tens  BCD  (weights 10,20,40,80)
//     Bit  68      : Leap second pending / control
//     Bit  69      : P7  (reference)
//     Bits 70-78   : DST flags and control-function bits
//     Bit  79      : P8  (reference)
//     Bits 80-98   : Control-function / quality
//     Bit  99      : P9  (last reference, end-of-frame marker)
//
// Parameters:
//   CLK_FREQ  - System clock frequency in Hz (default 50 MHz)
//
// Inputs:
//   clk           - System clock
//   rst_n         - Active-low synchronous reset
//   b_code_in     - IRIG-B digital input (idle low, high during pulse)
//
// Outputs:
//   second [5:0]      - Decoded seconds  (0-59)
//   minute [5:0]      - Decoded minutes  (0-59)
//   hour   [4:0]      - Decoded hours    (0-23)
//   day_of_year [8:0] - Decoded day of year (1-366)
//   year   [6:0]      - Decoded 2-digit year (0-99)
//   month  [3:0]      - Calendar month   (1-12, derived from day_of_year)
//   day    [4:0]      - Calendar day     (1-31, derived from day_of_year)
//   is_leap           - 1 when the current year is a leap year
//   time_valid        - 1 when the decoded time is valid (synced to frame)
//   pps_out           - Pulses high for one clock cycle at every frame start (1 PPS)
// =============================================================================
module b_code_decoder #(
    parameter CLK_FREQ = 50_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        b_code_in,

    // Decoded time outputs
    output reg  [5:0]  second,       // 0-59
    output reg  [5:0]  minute,       // 0-59
    output reg  [4:0]  hour,         // 0-23
    output reg  [8:0]  day_of_year,  // 1-366
    output reg  [6:0]  year,         // 2-digit year 0-99
    output wire [3:0]  month,        // 1-12 (calendar month)
    output wire [4:0]  day,          // 1-31 (calendar day)
    output wire        is_leap,      // 1 = leap year
    output reg         time_valid,   // 1 = outputs are valid
    output reg         pps_out       // 1 pulse per second
);

    // -----------------------------------------------------------------------
    // Timing thresholds (in clock cycles)
    // -----------------------------------------------------------------------
    // Bit period: 10 ms = CLK_FREQ / 100
    // Pulse widths (nominal): 0 → 2 ms, 1 → 5 ms, Ref → 8 ms
    // Decision thresholds: midpoint between adjacent categories
    localparam THR_0_1   = CLK_FREQ * 35 / 10000; // 3.5 ms: separates '0' from '1'
    localparam THR_1_REF = CLK_FREQ * 65 / 10000; // 6.5 ms: separates '1' from reference

    // Reference-marker positions: 0, 9, 19, 29, 39, 49, 59, 69, 79, 99
    // (Checked via the is_ref_pos function below)

    // -----------------------------------------------------------------------
    // Edge detection and pulse-width measurement
    // -----------------------------------------------------------------------
    reg b_prev;
    wire rising_edge  = b_code_in & ~b_prev;
    wire falling_edge = ~b_code_in & b_prev;

    // Pulse-width counter: counts clock cycles while b_code_in is high
    reg [19:0] pulse_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            b_prev    <= 1'b0;
            pulse_cnt <= 20'd0;
        end else begin
            b_prev <= b_code_in;
            if (rising_edge)
                pulse_cnt <= 20'd0;
            else if (b_code_in)
                pulse_cnt <= pulse_cnt + 1'b1;
        end
    end

    // -----------------------------------------------------------------------
    // Bit decoding: classify pulse on falling edge
    // -----------------------------------------------------------------------
    // bit_type: 2'b00 = logic 0, 2'b01 = logic 1, 2'b10 = reference
    reg [1:0] bit_type;
    reg       bit_ready; // Pulses for one cycle when a new bit is decoded

    always @(posedge clk) begin
        if (!rst_n) begin
            bit_type  <= 2'd0;
            bit_ready <= 1'b0;
        end else begin
            bit_ready <= 1'b0;
            if (falling_edge) begin
                bit_ready <= 1'b1;
                if (pulse_cnt < THR_0_1)
                    bit_type <= 2'b00;          // Logic 0
                else if (pulse_cnt < THR_1_REF)
                    bit_type <= 2'b01;          // Logic 1
                else
                    bit_type <= 2'b10;          // Reference marker
            end
        end
    end

    // -----------------------------------------------------------------------
    // Frame synchronisation and bit storage
    // -----------------------------------------------------------------------
    reg [6:0]  bit_count;          // Current bit position within the frame (0-99)
    reg [99:0] frame_buf;          // Raw frame bit storage
    reg [3:0]  sync_count;         // Number of consecutive valid frames
    reg        synced;             // 1 when locked to a valid frame

    // Helper: is position N expected to be a reference?
    // The REF_MASK is indexed with bit 0 = position 0.
    function is_ref_pos;
        input [6:0] pos;
        begin
            is_ref_pos = (pos == 7'd0)  || (pos == 7'd9)  || (pos == 7'd19) ||
                         (pos == 7'd29) || (pos == 7'd39) || (pos == 7'd49) ||
                         (pos == 7'd59) || (pos == 7'd69) || (pos == 7'd79) ||
                         (pos == 7'd99);
        end
    endfunction

    // -----------------------------------------------------------------------
    // Time extraction registers (BCD)
    // -----------------------------------------------------------------------
    reg [5:0]  sec_bcd;
    reg [5:0]  min_bcd;
    reg [4:0]  hr_bcd;
    reg [8:0]  doy_bcd;
    reg [6:0]  yr_bcd;

    // -----------------------------------------------------------------------
    // Frame processing state machine
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            bit_count  <= 7'd0;
            frame_buf  <= 100'd0;
            sync_count <= 4'd0;
            synced     <= 1'b0;
            time_valid <= 1'b0;
            pps_out    <= 1'b0;
            second     <= 6'd0;
            minute     <= 6'd0;
            hour       <= 5'd0;
            day_of_year<= 9'd0;
            year       <= 7'd0;
        end else begin
            pps_out <= 1'b0;  // Default: de-assert

            if (bit_ready) begin
                // --------------------------------------------------------------
                // Check for frame sync violations
                // --------------------------------------------------------------
                if (bit_type == 2'b10) begin
                    // Received a reference marker
                    if (!is_ref_pos(bit_count)) begin
                        // Unexpected reference: re-sync from this position
                        bit_count  <= 7'd1;  // This reference becomes P0
                        frame_buf  <= 100'd0;
                        sync_count <= 4'd0;
                        synced     <= 1'b0;
                        time_valid <= 1'b0;
                    end else begin
                        frame_buf[bit_count] <= 1'b1; // Reference stored as 1
                        bit_count <= (bit_count == 7'd99) ? 7'd0 : bit_count + 1'b1;
                    end
                end else begin
                    // Received a data bit (0 or 1)
                    if (is_ref_pos(bit_count)) begin
                        // Expected a reference but got data: re-sync
                        bit_count  <= 7'd0;
                        frame_buf  <= 100'd0;
                        sync_count <= 4'd0;
                        synced     <= 1'b0;
                        time_valid <= 1'b0;
                    end else begin
                        frame_buf[bit_count] <= bit_type[0]; // Store data bit
                        bit_count <= bit_count + 1'b1;
                    end
                end

                // --------------------------------------------------------------
                // Complete frame received (just processed bit 99, P9 reference)
                // --------------------------------------------------------------
                if (bit_count == 7'd99 && bit_type == 2'b10) begin
                    // Increment sync confidence
                    if (sync_count < 4'd5)
                        sync_count <= sync_count + 1'b1;
                    else
                        synced <= 1'b1;

                    // --------------------------------------------------------
                    // Extract BCD time fields from the completed frame
                    // Seconds units (bits 1-4): weight 1,2,4,8
                    // Seconds tens  (bits 6-7): weight 10,20
                    // --------------------------------------------------------
                    sec_bcd = frame_buf[1]*6'd1  + frame_buf[2]*6'd2  +
                              frame_buf[3]*6'd4  + frame_buf[4]*6'd8  +
                              frame_buf[6]*6'd10 + frame_buf[7]*6'd20;

                    // Minutes units (bits 10-13) + tens (bits 15-17)
                    min_bcd = frame_buf[10]*6'd1  + frame_buf[11]*6'd2 +
                              frame_buf[12]*6'd4  + frame_buf[13]*6'd8 +
                              frame_buf[15]*6'd10 + frame_buf[16]*6'd20 +
                              frame_buf[17]*6'd40;

                    // Hours units (bits 20-23) + tens (bits 25-26)
                    hr_bcd  = frame_buf[20]*5'd1  + frame_buf[21]*5'd2 +
                              frame_buf[22]*5'd4  + frame_buf[23]*5'd8 +
                              frame_buf[25]*5'd10 + frame_buf[26]*5'd20;

                    // Day-of-year units (bits 30-33) + tens (35-38) + hundreds (40-41)
                    doy_bcd = frame_buf[30]*9'd1   + frame_buf[31]*9'd2   +
                              frame_buf[32]*9'd4   + frame_buf[33]*9'd8   +
                              frame_buf[35]*9'd10  + frame_buf[36]*9'd20  +
                              frame_buf[37]*9'd40  + frame_buf[38]*9'd80  +
                              frame_buf[40]*9'd100 + frame_buf[41]*9'd200;

                    // Year units (bits 60-63) + tens (bits 64-67)
                    yr_bcd  = frame_buf[60]*7'd1  + frame_buf[61]*7'd2  +
                              frame_buf[62]*7'd4  + frame_buf[63]*7'd8  +
                              frame_buf[64]*7'd10 + frame_buf[65]*7'd20 +
                              frame_buf[66]*7'd40 + frame_buf[67]*7'd80;

                    // Publish outputs only when synced
                    if (synced) begin
                        second      <= sec_bcd;
                        minute      <= min_bcd;
                        hour        <= hr_bcd[4:0];
                        day_of_year <= doy_bcd;
                        year        <= yr_bcd;
                        time_valid  <= 1'b1;
                        pps_out     <= 1'b1; // 1 PPS pulse
                    end

                    // Reset bit_count for the next frame (next bit will be P0)
                    bit_count <= 7'd0;
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // Derive calendar date from day-of-year using sub-modules
    // -----------------------------------------------------------------------
    leap_year u_leap_year (
        .year_2digit (year),
        .is_leap     (is_leap)
    );

    day_to_date u_day_to_date (
        .day_of_year (day_of_year),
        .is_leap     (is_leap),
        .month       (month),
        .day         (day)
    );

endmodule
