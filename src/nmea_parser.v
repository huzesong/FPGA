// =============================================================================
// Module: nmea_parser
// Description: Unified NMEA-0183 sentence parser for multi-constellation GNSS.
//
// Receives ASCII bytes from a UART receiver, buffers complete NMEA sentences,
// validates the XOR checksum, identifies the constellation (GPS / BeiDou /
// Galileo) and sentence type (RMC / GGA), extracts time and date information,
// and drives separate output registers for each constellation.
//
// Supported talker IDs:
//   "GP"        -> GPS         (constellation = 2'b00)
//   "GB" / "BD" -> BeiDou      (constellation = 2'b01)
//   "GA"        -> Galileo     (constellation = 2'b10)
//   "GN"        -> Multi-GNSS  (treated as GPS, constellation = 2'b11)
//
// Supported sentence types (sentence_type encoding):
//   "RMC" -> 3'b000   Contains: time (HHMMSS.sss), status, date (DDMMYY)
//   "GGA" -> 3'b001   Contains: time (HHMMSS.sss), fix quality
//   "GSV" -> 3'b010   Satellites in view
//   "GSA" -> 3'b011   DOP and active satellites
//   "VTG" -> 3'b100   Velocity made good
//   other -> 3'b111   Unknown / unsupported (sentence buffered, no time parsed)
//
// NMEA sentence frame:
//   $<TalkerID(2)><Type(3)>,<F1>,...,<FN>*<HH><CR><LF>
//   XOR checksum covers all bytes from (not including) '$' to (not including) '*'
//
// Key field indices (0-based after the sentence-ID field):
//   Field 1 : UTC time  HHMMSS.sss    (present in RMC and GGA)
//   Field 2 : Status    A/V            (RMC only)
//   Field 9 : UTC date  DDMMYY         (RMC only)
//
// Parameters:
//   MAX_SENTENCE_LEN  Maximum bytes to buffer per sentence (>= 82 per spec).
//
// Inputs / Outputs: see port list below.
// =============================================================================
module nmea_parser #(
    parameter MAX_SENTENCE_LEN = 96
)(
    input  wire        clk,
    input  wire        rst_n,

    // Byte stream from uart_rx
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    // -----------------------------------------------------------------------
    // GPS outputs  (talker GP or GN)
    // -----------------------------------------------------------------------
    output reg  [2:0]  gps_sentence_type,
    output reg  [MAX_SENTENCE_LEN*8-1:0] gps_sentence_raw,
    output reg  [6:0]  gps_sentence_len,
    output reg         gps_sentence_valid,   // One-cycle pulse per valid sentence

    output reg  [5:0]  gps_hour,
    output reg  [5:0]  gps_minute,
    output reg  [5:0]  gps_second,
    output reg         gps_time_valid,

    output reg  [4:0]  gps_day,
    output reg  [3:0]  gps_month,
    output reg  [6:0]  gps_year,
    output reg         gps_date_valid,
    output wire        gps_is_leap,
    output reg         gps_status,           // 1 = Active (A), 0 = Void (V)

    // -----------------------------------------------------------------------
    // BeiDou outputs  (talker GB or BD)
    // -----------------------------------------------------------------------
    output reg  [2:0]  bd_sentence_type,
    output reg  [MAX_SENTENCE_LEN*8-1:0] bd_sentence_raw,
    output reg  [6:0]  bd_sentence_len,
    output reg         bd_sentence_valid,

    output reg  [5:0]  bd_hour,
    output reg  [5:0]  bd_minute,
    output reg  [5:0]  bd_second,
    output reg         bd_time_valid,

    output reg  [4:0]  bd_day,
    output reg  [3:0]  bd_month,
    output reg  [6:0]  bd_year,
    output reg         bd_date_valid,
    output wire        bd_is_leap,
    output reg         bd_status,

    // -----------------------------------------------------------------------
    // Galileo outputs  (talker GA)
    // -----------------------------------------------------------------------
    output reg  [2:0]  ga_sentence_type,
    output reg  [MAX_SENTENCE_LEN*8-1:0] ga_sentence_raw,
    output reg  [6:0]  ga_sentence_len,
    output reg         ga_sentence_valid,

    output reg  [5:0]  ga_hour,
    output reg  [5:0]  ga_minute,
    output reg  [5:0]  ga_second,
    output reg         ga_time_valid,

    output reg  [4:0]  ga_day,
    output reg  [3:0]  ga_month,
    output reg  [6:0]  ga_year,
    output reg         ga_date_valid,
    output wire        ga_is_leap,
    output reg         ga_status
);

    // -----------------------------------------------------------------------
    // Leap-year sub-modules (combinational, one per constellation)
    // -----------------------------------------------------------------------
    leap_year u_leap_gps (.year_2digit(gps_year), .is_leap(gps_is_leap));
    leap_year u_leap_bd  (.year_2digit(bd_year),  .is_leap(bd_is_leap));
    leap_year u_leap_ga  (.year_2digit(ga_year),  .is_leap(ga_is_leap));

    // -----------------------------------------------------------------------
    // Constellation identifiers
    // -----------------------------------------------------------------------
    localparam CONST_GPS = 2'b00;
    localparam CONST_BD  = 2'b01;
    localparam CONST_GA  = 2'b10;
    localparam CONST_GN  = 2'b11;  // Multi-constellation: dispatched as GPS

    // -----------------------------------------------------------------------
    // Sentence-type identifiers
    // -----------------------------------------------------------------------
    localparam TYPE_RMC = 3'b000;
    localparam TYPE_GGA = 3'b001;
    localparam TYPE_GSV = 3'b010;
    localparam TYPE_GSA = 3'b011;
    localparam TYPE_VTG = 3'b100;
    localparam TYPE_UNK = 3'b111;

    // -----------------------------------------------------------------------
    // Parser states
    // -----------------------------------------------------------------------
    localparam ST_IDLE   = 3'd0;  // Waiting for '$'
    localparam ST_HEADER = 3'd1;  // Reading 5-char header (TT+SSS) + comma
    localparam ST_FIELD  = 3'd2;  // Reading field data characters
    localparam ST_CKSUM1 = 3'd3;  // Reading first checksum hex digit
    localparam ST_CKSUM2 = 3'd4;  // Reading second checksum hex digit + dispatch

    reg [2:0] state;

    // -----------------------------------------------------------------------
    // Sentence buffer
    // -----------------------------------------------------------------------
    reg [7:0]  buf_data [0:MAX_SENTENCE_LEN-1];
    reg [6:0]  buf_len;

    // -----------------------------------------------------------------------
    // Internal working registers
    // -----------------------------------------------------------------------
    reg [1:0]  constellation;    // Decoded talker
    reg [2:0]  stype;            // Decoded sentence type

    // Header counter (0-5): talker[0], talker[1], type[0], type[1], type[2], ','
    reg [2:0]  hdr_cnt;

    // Talker storage (only first char needed to disambiguate with second char rx_data)
    reg [7:0]  talker0, talker1;
    // Type storage
    reg [7:0]  type0, type1;     // type[2] = rx_data when hdr_cnt==4

    // Field parser
    reg [3:0]  field_cnt;        // Which field we are in (0 = after first comma)
    reg [3:0]  fchar_idx;        // Character index within current field

    // Running XOR checksum
    reg [7:0]  calc_cksum;

    // Captured raw digit pairs for time and date
    reg [3:0]  dh0, dh1;        // Hour: tens, units
    reg [3:0]  dm0, dm1;        // Minute: tens, units
    reg [3:0]  ds0, ds1;        // Second: tens, units
    reg [3:0]  dd0, dd1;        // Day: tens, units
    reg [3:0]  dmo0, dmo1;      // Month: tens, units
    reg [3:0]  dy0, dy1;        // Year: tens, units

    // Flags set during field parsing
    reg        got_time;         // At least 6 time digits received
    reg        got_date;         // At least 6 date digits received
    reg        cur_status;       // RMC status: 1=A (active), 0=V (void)

    // Received checksum nibble storage
    reg [3:0]  ck_hi;            // High nibble (first hex digit)

    // -----------------------------------------------------------------------
    // Helper functions
    // -----------------------------------------------------------------------

    // ASCII '0'-'9' -> 4-bit binary value; non-digits map to 0
    function [3:0] ascii_digit;
        input [7:0] ch;
        begin
            if (ch >= 8'h30 && ch <= 8'h39)
                ascii_digit = ch[3:0];  // Lower nibble of '0'-'9' is 0-9
            else
                ascii_digit = 4'd0;
        end
    endfunction

    // ASCII hex digit -> 4-bit nibble
    function [3:0] hex_nibble;
        input [7:0] ch;
        begin
            if      (ch >= 8'h30 && ch <= 8'h39) hex_nibble = ch - 8'h30;       // '0'-'9'
            else if (ch >= 8'h41 && ch <= 8'h46) hex_nibble = ch - 8'h37;       // 'A'-'F'
            else if (ch >= 8'h61 && ch <= 8'h66) hex_nibble = ch - 8'h57;       // 'a'-'f'
            else                                  hex_nibble = 4'h0;
        end
    endfunction

    // -----------------------------------------------------------------------
    // Dispatch task: publish results to the correct constellation outputs
    // -----------------------------------------------------------------------
    // (Inlined below in ST_CKSUM2 to avoid SystemVerilog task complexity)

    // -----------------------------------------------------------------------
    // Main state machine
    // -----------------------------------------------------------------------
    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            buf_len            <= 7'd0;
            calc_cksum         <= 8'd0;
            field_cnt          <= 4'd0;
            fchar_idx          <= 4'd0;
            hdr_cnt            <= 3'd0;
            got_time           <= 1'b0;
            got_date           <= 1'b0;
            cur_status         <= 1'b0;
            constellation      <= CONST_GPS;
            stype              <= TYPE_UNK;

            // Clear constellation outputs
            gps_sentence_valid <= 1'b0;
            bd_sentence_valid  <= 1'b0;
            ga_sentence_valid  <= 1'b0;
            gps_time_valid     <= 1'b0;
            bd_time_valid      <= 1'b0;
            ga_time_valid      <= 1'b0;
            gps_date_valid     <= 1'b0;
            bd_date_valid      <= 1'b0;
            ga_date_valid      <= 1'b0;
            gps_status         <= 1'b0;
            bd_status          <= 1'b0;
            ga_status          <= 1'b0;

            for (i = 0; i < MAX_SENTENCE_LEN; i = i + 1)
                buf_data[i] <= 8'd0;

            {dh0,dh1,dm0,dm1,ds0,ds1} <= 24'd0;
            {dd0,dd1,dmo0,dmo1,dy0,dy1} <= 24'd0;
            ck_hi <= 4'd0;

        end else begin
            // De-assert one-cycle strobes every clock
            gps_sentence_valid <= 1'b0;
            bd_sentence_valid  <= 1'b0;
            ga_sentence_valid  <= 1'b0;

            if (rx_valid) begin
                case (state)

                    // --------------------------------------------------------
                    // IDLE: wait for '$'
                    // --------------------------------------------------------
                    ST_IDLE: begin
                        if (rx_data == 8'h24) begin   // '$'
                            // Initialise for a new sentence
                            buf_data[0] <= rx_data;
                            buf_len     <= 7'd1;
                            calc_cksum  <= 8'd0;
                            got_time    <= 1'b0;
                            got_date    <= 1'b0;
                            cur_status  <= 1'b0;
                            hdr_cnt     <= 3'd0;
                            state       <= ST_HEADER;
                        end
                    end

                    // --------------------------------------------------------
                    // HEADER: process chars 0-5 of the sentence ID field
                    //   hdr_cnt 0 : talker[0]   (e.g. 'G')
                    //   hdr_cnt 1 : talker[1]   (e.g. 'P')  -> decode constellation
                    //   hdr_cnt 2 : type[0]     (e.g. 'R')
                    //   hdr_cnt 3 : type[1]     (e.g. 'M')
                    //   hdr_cnt 4 : type[2]     (e.g. 'C')  -> decode sentence type
                    //   hdr_cnt 5 : ','  (must be comma or abort)
                    // --------------------------------------------------------
                    ST_HEADER: begin
                        if (buf_len < MAX_SENTENCE_LEN) begin
                            buf_data[buf_len] <= rx_data;
                        end
                        buf_len    <= buf_len + 1'b1;
                        calc_cksum <= calc_cksum ^ rx_data;

                        case (hdr_cnt)
                            3'd0: begin   // talker[0]
                                talker0 <= rx_data;
                                hdr_cnt <= 3'd1;
                            end
                            3'd1: begin   // talker[1] -> decode constellation now
                                talker1 <= rx_data;
                                if (talker0 == "G" && rx_data == "P")
                                    constellation <= CONST_GPS;
                                else if ((talker0 == "G" && rx_data == "B") ||
                                         (talker0 == "B" && rx_data == "D"))
                                    constellation <= CONST_BD;
                                else if (talker0 == "G" && rx_data == "A")
                                    constellation <= CONST_GA;
                                else
                                    constellation <= CONST_GN;
                                hdr_cnt <= 3'd2;
                            end
                            3'd2: begin   // type[0]
                                type0   <= rx_data;
                                hdr_cnt <= 3'd3;
                            end
                            3'd3: begin   // type[1]
                                type1   <= rx_data;
                                hdr_cnt <= 3'd4;
                            end
                            3'd4: begin   // type[2] (rx_data) -> decode sentence type
                                if      (type0=="R" && type1=="M" && rx_data=="C") stype <= TYPE_RMC;
                                else if (type0=="G" && type1=="G" && rx_data=="A") stype <= TYPE_GGA;
                                else if (type0=="G" && type1=="S" && rx_data=="V") stype <= TYPE_GSV;
                                else if (type0=="G" && type1=="S" && rx_data=="A") stype <= TYPE_GSA;
                                else if (type0=="V" && type1=="T" && rx_data=="G") stype <= TYPE_VTG;
                                else                                                stype <= TYPE_UNK;
                                hdr_cnt <= 3'd5;
                            end
                            3'd5: begin   // First comma after sentence ID
                                if (rx_data == 8'h2C) begin   // ','
                                    field_cnt <= 4'd0;   // We are entering field 1
                                    fchar_idx <= 4'd0;
                                    state     <= ST_FIELD;
                                end else begin
                                    state <= ST_IDLE;     // Malformed: abort
                                end
                            end
                            default: state <= ST_IDLE;
                        endcase
                    end

                    // --------------------------------------------------------
                    // FIELD: stream through data fields, extract time/date
                    // --------------------------------------------------------
                    ST_FIELD: begin
                        if (rx_data == 8'h2A) begin
                            // '*' ends the data portion; do NOT XOR '*' into checksum
                            if (buf_len < MAX_SENTENCE_LEN)
                                buf_data[buf_len] <= rx_data;
                            buf_len <= buf_len + 1'b1;
                            state   <= ST_CKSUM1;

                        end else if (rx_data == 8'h0D || rx_data == 8'h0A) begin
                            // CR/LF without checksum: discard sentence
                            state <= ST_IDLE;

                        end else begin
                            if (buf_len < MAX_SENTENCE_LEN)
                                buf_data[buf_len] <= rx_data;
                            buf_len    <= buf_len + 1'b1;
                            calc_cksum <= calc_cksum ^ rx_data;

                            if (rx_data == 8'h2C) begin
                                // Comma: move to next field
                                field_cnt <= field_cnt + 1'b1;
                                fchar_idx <= 4'd0;
                            end else begin
                                // Data character: extract relevant fields
                                // --------------------------------------------
                                // Field 0 (first data field): UTC time HHMMSS.sss
                                // Present in both RMC and GGA.
                                // --------------------------------------------
                                if (field_cnt == 4'd0 &&
                                    (stype == TYPE_RMC || stype == TYPE_GGA)) begin
                                    case (fchar_idx)
                                        4'd0: dh0 <= ascii_digit(rx_data);  // H tens
                                        4'd1: dh1 <= ascii_digit(rx_data);  // H units
                                        4'd2: dm0 <= ascii_digit(rx_data);  // M tens
                                        4'd3: dm1 <= ascii_digit(rx_data);  // M units
                                        4'd4: ds0 <= ascii_digit(rx_data);  // S tens
                                        4'd5: begin
                                            ds1      <= ascii_digit(rx_data);
                                            got_time <= 1'b1;
                                        end
                                        default: ;  // Ignore fractional seconds
                                    endcase
                                end

                                // --------------------------------------------
                                // Field 1: RMC status A/V (second data field)
                                // --------------------------------------------
                                if (field_cnt == 4'd1 && stype == TYPE_RMC &&
                                    fchar_idx == 4'd0) begin
                                    cur_status <= (rx_data == 8'h41);  // 'A'
                                end

                                // --------------------------------------------
                                // Field 8: RMC date DDMMYY (ninth data field)
                                // --------------------------------------------
                                if (field_cnt == 4'd8 && stype == TYPE_RMC) begin
                                    case (fchar_idx)
                                        4'd0: dd0  <= ascii_digit(rx_data);  // D tens
                                        4'd1: dd1  <= ascii_digit(rx_data);  // D units
                                        4'd2: dmo0 <= ascii_digit(rx_data);  // Mo tens
                                        4'd3: dmo1 <= ascii_digit(rx_data);  // Mo units
                                        4'd4: dy0  <= ascii_digit(rx_data);  // Y tens
                                        4'd5: begin
                                            dy1      <= ascii_digit(rx_data);
                                            got_date <= 1'b1;
                                        end
                                        default: ;
                                    endcase
                                end

                                fchar_idx <= fchar_idx + 1'b1;
                            end
                        end
                    end

                    // --------------------------------------------------------
                    // CKSUM1: receive first checksum hex digit
                    // --------------------------------------------------------
                    ST_CKSUM1: begin
                        if (buf_len < MAX_SENTENCE_LEN)
                            buf_data[buf_len] <= rx_data;
                        buf_len <= buf_len + 1'b1;
                        ck_hi   <= hex_nibble(rx_data);
                        state   <= ST_CKSUM2;
                    end

                    // --------------------------------------------------------
                    // CKSUM2: receive second checksum hex digit, validate,
                    //         and dispatch outputs for the correct constellation
                    // --------------------------------------------------------
                    ST_CKSUM2: begin
                        if (buf_len < MAX_SENTENCE_LEN)
                            buf_data[buf_len] <= rx_data;
                        buf_len <= buf_len + 1'b1;
                        state   <= ST_IDLE;

                        if (calc_cksum == {ck_hi, hex_nibble(rx_data)}) begin
                            // Checksum valid: build outputs
                            // Compute time and date values from digit pairs
                            // (multiplication by constant → small LUT chain)

                            // Dispatch to appropriate constellation outputs
                            case (constellation)

                                // ------------------------------------------------
                                // GPS (or GN multi-constellation → treated as GPS)
                                // ------------------------------------------------
                                CONST_GPS, CONST_GN: begin
                                    gps_sentence_type  <= stype;
                                    gps_sentence_len   <= buf_len + 1'b1;
                                    gps_sentence_valid <= 1'b1;
                                    begin : gps_buf_copy
                                        integer j;
                                        for (j = 0; j < MAX_SENTENCE_LEN; j = j + 1)
                                            gps_sentence_raw[(MAX_SENTENCE_LEN-1-j)*8 +: 8]
                                                <= (j < buf_len + 1) ? buf_data[j] : 8'd0;
                                    end
                                    if (got_time) begin
                                        gps_hour       <= dh0 * 6'd10 + {2'b00, dh1};
                                        gps_minute     <= dm0 * 6'd10 + {2'b00, dm1};
                                        gps_second     <= ds0 * 6'd10 + {2'b00, ds1};
                                        gps_time_valid <= 1'b1;
                                    end
                                    if (got_date && stype == TYPE_RMC) begin
                                        gps_day        <= dd0  * 5'd10 + {1'b0,   dd1};
                                        gps_month      <= dmo0 * 4'd10 + dmo1;
                                        gps_year       <= dy0  * 7'd10 + {3'b000, dy1};
                                        gps_date_valid <= 1'b1;
                                    end
                                    if (stype == TYPE_RMC)
                                        gps_status <= cur_status;
                                end

                                // ------------------------------------------------
                                // BeiDou
                                // ------------------------------------------------
                                CONST_BD: begin
                                    bd_sentence_type  <= stype;
                                    bd_sentence_len   <= buf_len + 1'b1;
                                    bd_sentence_valid <= 1'b1;
                                    begin : bd_buf_copy
                                        integer j;
                                        for (j = 0; j < MAX_SENTENCE_LEN; j = j + 1)
                                            bd_sentence_raw[(MAX_SENTENCE_LEN-1-j)*8 +: 8]
                                                <= (j < buf_len + 1) ? buf_data[j] : 8'd0;
                                    end
                                    if (got_time) begin
                                        bd_hour       <= dh0 * 6'd10 + {2'b00, dh1};
                                        bd_minute     <= dm0 * 6'd10 + {2'b00, dm1};
                                        bd_second     <= ds0 * 6'd10 + {2'b00, ds1};
                                        bd_time_valid <= 1'b1;
                                    end
                                    if (got_date && stype == TYPE_RMC) begin
                                        bd_day        <= dd0  * 5'd10 + {1'b0,   dd1};
                                        bd_month      <= dmo0 * 4'd10 + dmo1;
                                        bd_year       <= dy0  * 7'd10 + {3'b000, dy1};
                                        bd_date_valid <= 1'b1;
                                    end
                                    if (stype == TYPE_RMC)
                                        bd_status <= cur_status;
                                end

                                // ------------------------------------------------
                                // Galileo
                                // ------------------------------------------------
                                CONST_GA: begin
                                    ga_sentence_type  <= stype;
                                    ga_sentence_len   <= buf_len + 1'b1;
                                    ga_sentence_valid <= 1'b1;
                                    begin : ga_buf_copy
                                        integer j;
                                        for (j = 0; j < MAX_SENTENCE_LEN; j = j + 1)
                                            ga_sentence_raw[(MAX_SENTENCE_LEN-1-j)*8 +: 8]
                                                <= (j < buf_len + 1) ? buf_data[j] : 8'd0;
                                    end
                                    if (got_time) begin
                                        ga_hour       <= dh0 * 6'd10 + {2'b00, dh1};
                                        ga_minute     <= dm0 * 6'd10 + {2'b00, dm1};
                                        ga_second     <= ds0 * 6'd10 + {2'b00, ds1};
                                        ga_time_valid <= 1'b1;
                                    end
                                    if (got_date && stype == TYPE_RMC) begin
                                        ga_day        <= dd0  * 5'd10 + {1'b0,   dd1};
                                        ga_month      <= dmo0 * 4'd10 + dmo1;
                                        ga_year       <= dy0  * 7'd10 + {3'b000, dy1};
                                        ga_date_valid <= 1'b1;
                                    end
                                    if (stype == TYPE_RMC)
                                        ga_status <= cur_status;
                                end

                                default: ;  // Unknown talker: discard
                            endcase
                        end
                        // else: checksum mismatch -> discard silently
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
