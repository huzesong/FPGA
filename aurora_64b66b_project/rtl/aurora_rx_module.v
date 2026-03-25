//////////////////////////////////////////////////////////////////////////////
// Module: aurora_rx_module
// Description: RX module (接收模块) for Aurora 64B66B framing mode.
//              Receives frames from Aurora IP RX AXI-Stream interface,
//              identifies frame header and payload, and outputs parsed data
//              to the data check module.
//////////////////////////////////////////////////////////////////////////////

module aurora_rx_module (
    input  wire         clk,
    input  wire         rst,
    input  wire         channel_up,
    // AXI-Stream RX from Aurora IP
    input  wire [255:0] m_axi_rx_tdata,
    input  wire [31:0]  m_axi_rx_tkeep,
    input  wire         m_axi_rx_tlast,
    input  wire         m_axi_rx_tvalid,
    // Output to data check module
    output reg  [255:0] rx_data,
    output reg          rx_data_valid,
    output reg          rx_sof,       // Start of frame (first payload beat)
    output reg          rx_eof        // End of frame (last payload beat)
);

    localparam SYNC_WORD = 32'hA5A5_5A5A;

    // State machine
    localparam S_IDLE    = 2'd0;
    localparam S_HEADER  = 2'd1;
    localparam S_PAYLOAD = 2'd2;

    reg [1:0]  state;
    reg        first_payload;  // Flag for first payload beat after header

    always @(posedge clk) begin
        if (rst || !channel_up) begin
            state         <= S_IDLE;
            rx_data       <= 256'd0;
            rx_data_valid <= 1'b0;
            rx_sof        <= 1'b0;
            rx_eof        <= 1'b0;
            first_payload <= 1'b0;
        end else begin
            // Default outputs
            rx_data_valid <= 1'b0;
            rx_sof        <= 1'b0;
            rx_eof        <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (channel_up)
                        state <= S_HEADER;
                end

                S_HEADER: begin
                    // Wait for header beat (identified by sync word)
                    if (m_axi_rx_tvalid) begin
                        if (m_axi_rx_tdata[255:224] == SYNC_WORD) begin
                            // Valid header received
                            state         <= S_PAYLOAD;
                            first_payload <= 1'b1;
                        end
                        // If not a valid header, stay and keep looking
                    end
                end

                S_PAYLOAD: begin
                    if (m_axi_rx_tvalid) begin
                        rx_data       <= m_axi_rx_tdata;
                        rx_data_valid <= 1'b1;
                        rx_sof        <= first_payload;
                        first_payload <= 1'b0;

                        if (m_axi_rx_tlast) begin
                            rx_eof <= 1'b1;
                            state  <= S_HEADER;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
