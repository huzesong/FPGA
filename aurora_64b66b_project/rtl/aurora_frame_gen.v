//////////////////////////////////////////////////////////////////////////////
// Module: aurora_frame_gen
// Description: Frame assembly module (组帧模块) for Aurora 64B66B framing mode.
//              Assembles frames with a header beat and payload beats.
//              Uses a prefetch pattern: data is loaded into the output
//              register one cycle ahead so that the AXI-Stream bus always
//              shows the correct data on the same cycle as tvalid.
//              Frame format:
//                Beat 0 (Header): {SYNC_WORD, FRAME_ID, PAYLOAD_LEN, 160'd0}
//                Beat 1..N (Payload): raw data from data generator
//                Last beat: tlast=1, tkeep=32'hFFFFFFFF
//////////////////////////////////////////////////////////////////////////////

module aurora_frame_gen #(
    parameter FRAME_PAYLOAD_BEATS = 32    // Number of payload beats per frame
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         channel_up,
    // Data input interface (from data generator)
    input  wire [255:0] data_in,
    input  wire         data_in_valid,
    output wire         data_in_ready,
    // AXI-Stream TX output (to Aurora IP via tx_module)
    output reg  [255:0] tx_tdata,
    output reg  [31:0]  tx_tkeep,
    output reg          tx_tlast,
    output reg          tx_tvalid,
    input  wire         tx_tready
);

    localparam SYNC_WORD = 32'hA5A5_5A5A;

    // State machine
    localparam S_IDLE    = 2'd0;
    localparam S_HEADER  = 2'd1;
    localparam S_PAYLOAD = 2'd2;

    reg [1:0]  state;
    reg [15:0] beat_cnt;       // Counts payload beats sent
    reg [31:0] frame_cnt;      // Frame ID counter

    // Data input ready: consume data when loading into TX pipeline
    //   - In S_HEADER: when header handshake completes, load first payload
    //   - In S_PAYLOAD: when current beat accepted (or no beat pending)
    assign data_in_ready = ((state == S_PAYLOAD) && (!tx_tvalid || tx_tready)) ||
                           ((state == S_HEADER) && tx_tvalid && tx_tready);

    always @(posedge clk) begin
        if (rst || !channel_up) begin
            state     <= S_IDLE;
            beat_cnt  <= 16'd0;
            frame_cnt <= 32'd0;
            tx_tdata  <= 256'd0;
            tx_tkeep  <= 32'd0;
            tx_tlast  <= 1'b0;
            tx_tvalid <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    // Wait for any pending beat to be consumed before
                    // loading the next frame header (prevents overwriting
                    // the last payload beat when tx_tready is low).
                    if (!tx_tvalid || tx_tready) begin
                        tx_tdata  <= {SYNC_WORD, frame_cnt,
                                      32'd0, 160'd0};
                        tx_tkeep  <= 32'hFFFF_FFFF;
                        tx_tlast  <= 1'b0;
                        tx_tvalid <= 1'b1;
                        beat_cnt  <= 16'd0;
                        state     <= S_HEADER;
                    end
                end

                S_HEADER: begin
                    // Wait for header handshake, then preload first payload
                    if (tx_tready && tx_tvalid) begin
                        if (data_in_valid) begin
                            // Load first payload beat immediately
                            tx_tdata  <= data_in;
                            tx_tkeep  <= 32'hFFFF_FFFF;
                            tx_tvalid <= 1'b1;
                            tx_tlast  <= (FRAME_PAYLOAD_BEATS == 1) ? 1'b1 : 1'b0;
                            beat_cnt  <= 16'd1;
                            if (FRAME_PAYLOAD_BEATS == 1) begin
                                frame_cnt <= frame_cnt + 32'd1;
                                state     <= S_IDLE;
                            end else begin
                                state     <= S_PAYLOAD;
                            end
                        end else begin
                            // No data available yet, wait in payload state
                            tx_tvalid <= 1'b0;
                            tx_tlast  <= 1'b0;
                            beat_cnt  <= 16'd0;
                            state     <= S_PAYLOAD;
                        end
                    end
                end

                S_PAYLOAD: begin
                    if (!tx_tvalid || tx_tready) begin
                        if (data_in_valid) begin
                            tx_tdata  <= data_in;
                            tx_tkeep  <= 32'hFFFF_FFFF;
                            tx_tvalid <= 1'b1;
                            if (beat_cnt == FRAME_PAYLOAD_BEATS - 1) begin
                                tx_tlast  <= 1'b1;
                                frame_cnt <= frame_cnt + 32'd1;
                                state     <= S_IDLE;
                            end else begin
                                tx_tlast  <= 1'b0;
                            end
                            beat_cnt <= beat_cnt + 16'd1;
                        end else begin
                            tx_tvalid <= 1'b0;
                            tx_tlast  <= 1'b0;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
