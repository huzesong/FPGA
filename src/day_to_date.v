// =============================================================================
// Module: day_to_date
// Description: Converts a day-of-year value (1-366) into calendar month (1-12)
//              and day-of-month (1-31), correctly handling leap years.
//
// Inputs:
//   day_of_year [8:0] - Day within the year (1-366)
//   is_leap           - 1 when the current year is a leap year
//
// Outputs:
//   month [3:0]       - Calendar month (1-12)
//   day   [4:0]       - Day of the month (1-31)
// =============================================================================
module day_to_date (
    input  wire [8:0] day_of_year,
    input  wire       is_leap,
    output reg  [3:0] month,
    output reg  [4:0] day
);

    // Leap year adds one day to February (and shifts all subsequent months).
    wire [8:0] adj = is_leap ? 9'd1 : 9'd0;

    // Intermediate 9-bit result before narrowing to 5 bits.
    // The maximum value for day-of-month is 31, which fits comfortably.
    reg [8:0] d9;

    // Cumulative day counts at the end of each month (non-leap year):
    //   Jan=31, Feb=59, Mar=90, Apr=120, May=151, Jun=181,
    //   Jul=212, Aug=243, Sep=273, Oct=304, Nov=334, Dec=365.
    // For leap years, add adj (= 1) to all thresholds from February onward.
    always @(*) begin
        if (day_of_year <= 9'd31) begin
            month = 4'd1;
            d9    = day_of_year;
        end else if (day_of_year <= 9'd59 + adj) begin
            month = 4'd2;
            d9    = day_of_year - 9'd31;
        end else if (day_of_year <= 9'd90 + adj) begin
            month = 4'd3;
            d9    = day_of_year - 9'd59 - adj;
        end else if (day_of_year <= 9'd120 + adj) begin
            month = 4'd4;
            d9    = day_of_year - 9'd90 - adj;
        end else if (day_of_year <= 9'd151 + adj) begin
            month = 4'd5;
            d9    = day_of_year - 9'd120 - adj;
        end else if (day_of_year <= 9'd181 + adj) begin
            month = 4'd6;
            d9    = day_of_year - 9'd151 - adj;
        end else if (day_of_year <= 9'd212 + adj) begin
            month = 4'd7;
            d9    = day_of_year - 9'd181 - adj;
        end else if (day_of_year <= 9'd243 + adj) begin
            month = 4'd8;
            d9    = day_of_year - 9'd212 - adj;
        end else if (day_of_year <= 9'd273 + adj) begin
            month = 4'd9;
            d9    = day_of_year - 9'd243 - adj;
        end else if (day_of_year <= 9'd304 + adj) begin
            month = 4'd10;
            d9    = day_of_year - 9'd273 - adj;
        end else if (day_of_year <= 9'd334 + adj) begin
            month = 4'd11;
            d9    = day_of_year - 9'd304 - adj;
        end else begin
            month = 4'd12;
            d9    = day_of_year - 9'd334 - adj;
        end

        // Narrow to 5 bits; d9 is always ≤ 31 so no data is lost.
        day = d9[4:0];
    end

endmodule
