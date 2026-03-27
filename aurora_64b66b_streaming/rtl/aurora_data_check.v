//////////////////////////////////////////////////////////////////////////////
// Module: aurora_data_check
// Description: Data verification module (数据校验模块) for Aurora 64B66B
//              streaming mode. Checks received data against expected 32-bit
//              incrementing pattern. In streaming mode there are no frame
//              boundaries, so the checker synchronizes on the first valid
//              beat and then continuously verifies subsequent beats.
//////////////////////////////////////////////////////////////////////////////

module aurora_data_check (
    input  wire         clk,
    input  wire         rst,
    // Input from Aurora RX
    input  wire [255:0] rx_data,
    input  wire         rx_data_valid,
    // Status outputs
    output reg          error_flag,
    output reg  [31:0]  error_count,
    output reg  [31:0]  beat_count
);

    reg [31:0] expected_counter;  // Expected value of first 32-bit word
    reg        synced;            // Track whether we have synced to data

    // Expected data pattern
    wire [255:0] expected_data;
    assign expected_data = {expected_counter + 32'd7, expected_counter + 32'd6,
                            expected_counter + 32'd5, expected_counter + 32'd4,
                            expected_counter + 32'd3, expected_counter + 32'd2,
                            expected_counter + 32'd1, expected_counter};

    always @(posedge clk) begin
        if (rst) begin
            expected_counter <= 32'd0;
            error_flag       <= 1'b0;
            error_count      <= 32'd0;
            beat_count       <= 32'd0;
            synced           <= 1'b0;
        end else if (rx_data_valid) begin
            beat_count <= beat_count + 32'd1;

            if (!synced) begin
                // First valid beat: synchronize expected counter to received
                // data and verify internal consistency across all 8 words.
                // Even if internal check fails (error flagged), sync is
                // accepted because the data_gen pattern is deterministic.
                expected_counter <= rx_data[31:0] + 32'd8;
                synced           <= 1'b1;
                // Check data consistency within this beat
                if (rx_data[63:32]   != rx_data[31:0] + 32'd1 ||
                    rx_data[95:64]   != rx_data[31:0] + 32'd2 ||
                    rx_data[127:96]  != rx_data[31:0] + 32'd3 ||
                    rx_data[159:128] != rx_data[31:0] + 32'd4 ||
                    rx_data[191:160] != rx_data[31:0] + 32'd5 ||
                    rx_data[223:192] != rx_data[31:0] + 32'd6 ||
                    rx_data[255:224] != rx_data[31:0] + 32'd7) begin
                    error_flag  <= 1'b1;
                    error_count <= error_count + 32'd1;
                end
            end else begin
                // Subsequent beats: check against expected pattern
                if (rx_data != expected_data) begin
                    error_flag  <= 1'b1;
                    error_count <= error_count + 32'd1;
                end
                expected_counter <= expected_counter + 32'd8;
            end
        end
    end

endmodule
