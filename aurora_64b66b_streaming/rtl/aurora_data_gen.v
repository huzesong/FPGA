//////////////////////////////////////////////////////////////////////////////
// Module: aurora_data_gen
// Description: Data generation module for Aurora 64B66B streaming mode.
//              Generates 256-bit data where each 32-bit segment increments
//              sequentially. 8 x 32-bit words per clock cycle.
//              Beat 0: {7, 6, 5, 4, 3, 2, 1, 0}
//              Beat 1: {15, 14, 13, 12, 11, 10, 9, 8}
//              ...
//////////////////////////////////////////////////////////////////////////////

module aurora_data_gen (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,       // Enable data generation (channel_up)
    input  wire        data_ready,   // Downstream ready to accept data
    output wire [255:0] data_out,    // 256-bit data output (8 x 32-bit)
    output reg          data_valid   // Data valid
);

    reg [31:0] counter;

    // Counter increments by 8 each time data is consumed
    always @(posedge clk) begin
        if (rst) begin
            counter <= 32'd0;
        end else if (enable && data_valid && data_ready) begin
            counter <= counter + 32'd8;
        end
    end

    // Combinational data output: 8 consecutive 32-bit values
    assign data_out = {counter + 32'd7, counter + 32'd6,
                       counter + 32'd5, counter + 32'd4,
                       counter + 32'd3, counter + 32'd2,
                       counter + 32'd1, counter};

    // Valid signal: high when enabled
    always @(posedge clk) begin
        if (rst)
            data_valid <= 1'b0;
        else if (enable)
            data_valid <= 1'b1;
        else
            data_valid <= 1'b0;
    end

endmodule
