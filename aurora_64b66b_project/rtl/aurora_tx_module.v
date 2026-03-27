//////////////////////////////////////////////////////////////////////////////
// Module: aurora_tx_module
// Description: TX module (发送模块) for Aurora 64B66B framing mode.
//              Integrates data generator and frame generator, managing
//              the AXI-Stream TX interface to the Aurora IP core.
//////////////////////////////////////////////////////////////////////////////

module aurora_tx_module #(
    parameter FRAME_PAYLOAD_BEATS = 32
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         channel_up,
    // AXI-Stream TX to Aurora IP
    output wire [255:0] s_axi_tx_tdata,
    output wire [31:0]  s_axi_tx_tkeep,
    output wire         s_axi_tx_tlast,
    output wire         s_axi_tx_tvalid,
    input  wire         s_axi_tx_tready
);

    // Internal wires between data_gen and frame_gen
    wire [255:0] gen_data;
    wire         gen_valid;
    wire         gen_ready;

    // Data generator: produces 32-bit incrementing data
    aurora_data_gen u_data_gen (
        .clk        (clk),
        .rst        (rst),
        .enable     (channel_up),
        .data_ready (gen_ready),
        .data_out   (gen_data),
        .data_valid (gen_valid)
    );

    // Frame generator: assembles data into frames
    aurora_frame_gen #(
        .FRAME_PAYLOAD_BEATS (FRAME_PAYLOAD_BEATS)
    ) u_frame_gen (
        .clk           (clk),
        .rst           (rst),
        .channel_up    (channel_up),
        .data_in       (gen_data),
        .data_in_valid (gen_valid),
        .data_in_ready (gen_ready),
        .tx_tdata      (s_axi_tx_tdata),
        .tx_tkeep      (s_axi_tx_tkeep),
        .tx_tlast      (s_axi_tx_tlast),
        .tx_tvalid     (s_axi_tx_tvalid),
        .tx_tready     (s_axi_tx_tready)
    );

endmodule
