// =============================================================================
// Module: leap_year
// Description: Combinational logic to determine if a given year is a leap year.
//
// Leap year rules:
//   1. Divisible by 4
//   2. If divisible by 100, must also be divisible by 400
//
// For 2-digit years (representing 2000-2099):
//   - Simply check if the 2-digit value is divisible by 4.
//   - This works because 2000 is a leap year (divisible by 400),
//     and 2100 (not divisible by 400) is outside the 0-99 range.
//
// Inputs:
//   year_2digit [6:0] - Two-digit year (0-99), representing 2000+year
//
// Outputs:
//   is_leap           - 1 when the year is a leap year, 0 otherwise
// =============================================================================
module leap_year (
    input  wire [6:0] year_2digit,   // 2-digit year, 0-99 (represents 2000-2099)
    output wire       is_leap        // 1 = leap year
);

    // A year in 2000-2099 is a leap year if and only if its 2-digit
    // representation is divisible by 4.
    // Divisibility by 4 is checked by inspecting the lowest 2 bits.
    assign is_leap = (year_2digit[1:0] == 2'b00);

endmodule
