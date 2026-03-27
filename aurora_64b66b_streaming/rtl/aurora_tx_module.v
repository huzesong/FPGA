//////////////////////////////////////////////////////////////////////////////
// Module: aurora_tx_module
// Description: TX module (发送模块) for Aurora 64B66B streaming mode.
//              In streaming mode, data flows continuously without frame
//              boundaries. The data generator output is directly driven
//              onto the AXI-Stream TX interface (tdata + tvalid + tready).
//              No frame assembly is required.
//////////////////////////////////////////////////////////////////////////////

module aurora_tx_module (
    input  wire         clk,
    input  wire         rst,
    input  wire         channel_up,
    // AXI-Stream TX to Aurora IP (streaming: no tkeep, no tlast)
    output wire [255:0] s_axi_tx_tdata,
    output wire         s_axi_tx_tvalid,
    input  wire         s_axi_tx_tready
);

    // Internal wires between data_gen and Aurora TX interface
    wire [255:0] gen_data;
    wire         gen_valid;

    // Data generator: produces 32-bit incrementing data
    aurora_data_gen u_data_gen (
        .clk        (clk),
        .rst        (rst),
        .enable     (channel_up),
        .data_ready (s_axi_tx_tready),
        .data_out   (gen_data),
        .data_valid (gen_valid)
    );

    // In streaming mode, data goes directly to Aurora TX interface
    assign s_axi_tx_tdata  = gen_data;
    assign s_axi_tx_tvalid = gen_valid;

endmodule
