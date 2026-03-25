//////////////////////////////////////////////////////////////////////////////
// Module: aurora_top_tb
// Description: Testbench for the dual Aurora 64B66B channel design.
//              Uses behavioral Aurora model (loopback) to verify:
//              - Data generation (32-bit incrementing pattern)
//              - Frame assembly and disassembly
//              - TX/RX data path
//              - Data integrity checking
//              Simulates both channels with shared clock.
//////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module aurora_top_tb;

    //------------------------------------------------------------------------
    // Parameters
    //------------------------------------------------------------------------
    localparam GT_REFCLK_PERIOD = 6.4;    // 156.25 MHz (ns)
    localparam USER_CLK_PERIOD  = 6.4;    // User clock ≈ 156.25 MHz
    localparam INIT_CLK_PERIOD  = 20.0;   // 50 MHz init clock (ns)
    localparam SIM_TIME         = 50000;  // Total simulation time (ns)
    localparam FRAME_PAYLOAD_BEATS = 32;

    //------------------------------------------------------------------------
    // Clock and reset
    //------------------------------------------------------------------------
    reg         user_clk;
    reg         init_clk;
    reg         sys_rst_n;

    // User clock generation (156.25 MHz)
    initial user_clk = 0;
    always #(USER_CLK_PERIOD / 2) user_clk = ~user_clk;

    // Init clock generation (50 MHz)
    initial init_clk = 0;
    always #(INIT_CLK_PERIOD / 2) init_clk = ~init_clk;

    //------------------------------------------------------------------------
    // DUT signals
    //------------------------------------------------------------------------
    wire        reset_pb;
    reg  [7:0]  rst_cnt;
    reg         rst_sync_r1, rst_sync_r2;
    reg         pma_init_r;

    // Channel 0 signals
    wire [255:0] ch0_s_axi_tx_tdata;
    wire [31:0]  ch0_s_axi_tx_tkeep;
    wire         ch0_s_axi_tx_tlast;
    wire         ch0_s_axi_tx_tvalid;
    wire         ch0_s_axi_tx_tready;
    wire [255:0] ch0_m_axi_rx_tdata;
    wire [31:0]  ch0_m_axi_rx_tkeep;
    wire         ch0_m_axi_rx_tlast;
    wire         ch0_m_axi_rx_tvalid;
    wire         ch0_channel_up;
    wire [3:0]   ch0_lane_up;
    wire         ch0_hard_err;
    wire         ch0_soft_err;
    wire         ch0_error_flag;
    wire [31:0]  ch0_error_count;
    wire [31:0]  ch0_frame_count;
    wire [31:0]  ch0_beat_count;

    // Channel 1 signals
    wire [255:0] ch1_s_axi_tx_tdata;
    wire [31:0]  ch1_s_axi_tx_tkeep;
    wire         ch1_s_axi_tx_tlast;
    wire         ch1_s_axi_tx_tvalid;
    wire         ch1_s_axi_tx_tready;
    wire [255:0] ch1_m_axi_rx_tdata;
    wire [31:0]  ch1_m_axi_rx_tkeep;
    wire         ch1_m_axi_rx_tlast;
    wire         ch1_m_axi_rx_tvalid;
    wire         ch1_channel_up;
    wire [3:0]   ch1_lane_up;
    wire         ch1_hard_err;
    wire         ch1_soft_err;
    wire         ch1_error_flag;
    wire [31:0]  ch1_error_count;
    wire [31:0]  ch1_frame_count;
    wire [31:0]  ch1_beat_count;

    // RX parsed signals for monitoring
    wire [255:0] ch0_rx_payload;
    wire         ch0_rx_payload_valid;
    wire         ch0_rx_payload_sof;
    wire         ch0_rx_payload_eof;
    wire [255:0] ch1_rx_payload;
    wire         ch1_rx_payload_valid;
    wire         ch1_rx_payload_sof;
    wire         ch1_rx_payload_eof;

    //------------------------------------------------------------------------
    // Reset generation
    //------------------------------------------------------------------------
    initial begin
        sys_rst_n   = 1'b0;
        rst_sync_r1 = 1'b1;
        rst_sync_r2 = 1'b1;
        rst_cnt     = 8'd0;
        pma_init_r  = 1'b1;
        #200;
        sys_rst_n = 1'b1;
    end

    always @(posedge init_clk) begin
        rst_sync_r1 <= ~sys_rst_n;
        rst_sync_r2 <= rst_sync_r1;
    end

    always @(posedge init_clk) begin
        if (rst_sync_r2) begin
            rst_cnt    <= 8'd0;
            pma_init_r <= 1'b1;
        end else if (rst_cnt < 8'd255) begin
            rst_cnt    <= rst_cnt + 8'd1;
            pma_init_r <= 1'b1;
        end else begin
            pma_init_r <= 1'b0;
        end
    end

    assign reset_pb = rst_sync_r2;

    //------------------------------------------------------------------------
    // Channel 0: TX Module
    //------------------------------------------------------------------------
    aurora_tx_module #(
        .FRAME_PAYLOAD_BEATS (FRAME_PAYLOAD_BEATS)
    ) u_ch0_tx (
        .clk              (user_clk),
        .rst              (reset_pb),
        .channel_up       (ch0_channel_up),
        .s_axi_tx_tdata   (ch0_s_axi_tx_tdata),
        .s_axi_tx_tkeep   (ch0_s_axi_tx_tkeep),
        .s_axi_tx_tlast   (ch0_s_axi_tx_tlast),
        .s_axi_tx_tvalid  (ch0_s_axi_tx_tvalid),
        .s_axi_tx_tready  (ch0_s_axi_tx_tready)
    );

    //------------------------------------------------------------------------
    // Channel 0: Aurora Behavioral Model (loopback)
    //------------------------------------------------------------------------
    aurora_64b66b_0 u_ch0_aurora (
        .rxp                          (4'b0),
        .rxn                          (4'b1),
        .txp                          (),
        .txn                          (),
        .refclk1_in                   (1'b0),
        .user_clk                     (user_clk),
        .sync_clk                     (user_clk),
        .reset_pb                     (reset_pb),
        .power_down                   (1'b0),
        .pma_init                     (pma_init_r),
        .loopback                     (3'b000),
        .hard_err                     (ch0_hard_err),
        .soft_err                     (ch0_soft_err),
        .channel_up                   (ch0_channel_up),
        .lane_up                      (ch0_lane_up),
        .tx_out_clk                   (),
        .gt_pll_lock                  (),
        .drp_clk_in                   (init_clk),
        .s_axi_tx_tdata               (ch0_s_axi_tx_tdata),
        .s_axi_tx_tkeep               (ch0_s_axi_tx_tkeep),
        .s_axi_tx_tlast               (ch0_s_axi_tx_tlast),
        .s_axi_tx_tvalid              (ch0_s_axi_tx_tvalid),
        .s_axi_tx_tready              (ch0_s_axi_tx_tready),
        .m_axi_rx_tdata               (ch0_m_axi_rx_tdata),
        .m_axi_rx_tkeep               (ch0_m_axi_rx_tkeep),
        .m_axi_rx_tlast               (ch0_m_axi_rx_tlast),
        .m_axi_rx_tvalid              (ch0_m_axi_rx_tvalid),
        .mmcm_not_locked              (1'b0),
        // AXI4-Lite DRP (unused)
        .s_axi_awaddr                 (32'd0),
        .s_axi_awvalid                (1'b0),
        .s_axi_awready                (),
        .s_axi_wdata                  (32'd0),
        .s_axi_wstrb                  (4'd0),
        .s_axi_wvalid                 (1'b0),
        .s_axi_wready                 (),
        .s_axi_bvalid                 (),
        .s_axi_bresp                  (),
        .s_axi_bready                 (1'b1),
        .s_axi_araddr                 (32'd0),
        .s_axi_arvalid                (1'b0),
        .s_axi_arready                (),
        .s_axi_rdata                  (),
        .s_axi_rvalid                 (),
        .s_axi_rresp                  (),
        .s_axi_rready                 (1'b1),
        .s_axi_awaddr_lane1           (32'd0),
        .s_axi_awvalid_lane1          (1'b0),
        .s_axi_awready_lane1          (),
        .s_axi_wdata_lane1            (32'd0),
        .s_axi_wstrb_lane1            (4'd0),
        .s_axi_wvalid_lane1           (1'b0),
        .s_axi_wready_lane1           (),
        .s_axi_bvalid_lane1           (),
        .s_axi_bresp_lane1            (),
        .s_axi_bready_lane1           (1'b1),
        .s_axi_araddr_lane1           (32'd0),
        .s_axi_arvalid_lane1          (1'b0),
        .s_axi_arready_lane1          (),
        .s_axi_rdata_lane1            (),
        .s_axi_rvalid_lane1           (),
        .s_axi_rresp_lane1            (),
        .s_axi_rready_lane1           (1'b1),
        .s_axi_awaddr_lane2           (32'd0),
        .s_axi_awvalid_lane2          (1'b0),
        .s_axi_awready_lane2          (),
        .s_axi_wdata_lane2            (32'd0),
        .s_axi_wstrb_lane2            (4'd0),
        .s_axi_wvalid_lane2           (1'b0),
        .s_axi_wready_lane2           (),
        .s_axi_bvalid_lane2           (),
        .s_axi_bresp_lane2            (),
        .s_axi_bready_lane2           (1'b1),
        .s_axi_araddr_lane2           (32'd0),
        .s_axi_arvalid_lane2          (1'b0),
        .s_axi_arready_lane2          (),
        .s_axi_rdata_lane2            (),
        .s_axi_rvalid_lane2           (),
        .s_axi_rresp_lane2            (),
        .s_axi_rready_lane2           (1'b1),
        .s_axi_awaddr_lane3           (32'd0),
        .s_axi_awvalid_lane3          (1'b0),
        .s_axi_awready_lane3          (),
        .s_axi_wdata_lane3            (32'd0),
        .s_axi_wstrb_lane3            (4'd0),
        .s_axi_wvalid_lane3           (1'b0),
        .s_axi_wready_lane3           (),
        .s_axi_bvalid_lane3           (),
        .s_axi_bresp_lane3            (),
        .s_axi_bready_lane3           (1'b1),
        .s_axi_araddr_lane3           (32'd0),
        .s_axi_arvalid_lane3          (1'b0),
        .s_axi_arready_lane3          (),
        .s_axi_rdata_lane3            (),
        .s_axi_rvalid_lane3           (),
        .s_axi_rresp_lane3            (),
        .s_axi_rready_lane3           (1'b1),
        .qpll_drpaddr_in              (8'd0),
        .qpll_drpdi_in                (16'd0),
        .qpll_drpdo_out               (),
        .qpll_drprdy_out              (),
        .qpll_drpen_in                (1'b0),
        .qpll_drpwe_in                (1'b0),
        .init_clk                     (init_clk),
        .link_reset_out               (),
        .gt_qpllclk_quad1_in          (1'b0),
        .gt_qpllrefclk_quad1_in       (1'b0),
        .gt_to_common_qpllreset_out   (),
        .gt_qplllock_in               (1'b1),
        .gt_qpllrefclklost_in         (1'b0),
        .gt_rxcdrovrden_in            (1'b0),
        .sys_reset_out                ()
    );

    //------------------------------------------------------------------------
    // Channel 0: RX Module
    //------------------------------------------------------------------------
    aurora_rx_module u_ch0_rx (
        .clk              (user_clk),
        .rst              (reset_pb),
        .channel_up       (ch0_channel_up),
        .m_axi_rx_tdata   (ch0_m_axi_rx_tdata),
        .m_axi_rx_tkeep   (ch0_m_axi_rx_tkeep),
        .m_axi_rx_tlast   (ch0_m_axi_rx_tlast),
        .m_axi_rx_tvalid  (ch0_m_axi_rx_tvalid),
        .rx_data          (ch0_rx_payload),
        .rx_data_valid    (ch0_rx_payload_valid),
        .rx_sof           (ch0_rx_payload_sof),
        .rx_eof           (ch0_rx_payload_eof)
    );

    //------------------------------------------------------------------------
    // Channel 0: Data Check
    //------------------------------------------------------------------------
    aurora_data_check u_ch0_data_check (
        .clk              (user_clk),
        .rst              (reset_pb),
        .rx_data          (ch0_rx_payload),
        .rx_data_valid    (ch0_rx_payload_valid),
        .rx_sof           (ch0_rx_payload_sof),
        .rx_eof           (ch0_rx_payload_eof),
        .error_flag       (ch0_error_flag),
        .error_count      (ch0_error_count),
        .frame_count      (ch0_frame_count),
        .beat_count       (ch0_beat_count)
    );

    //------------------------------------------------------------------------
    // Channel 1: TX Module
    //------------------------------------------------------------------------
    aurora_tx_module #(
        .FRAME_PAYLOAD_BEATS (FRAME_PAYLOAD_BEATS)
    ) u_ch1_tx (
        .clk              (user_clk),
        .rst              (reset_pb),
        .channel_up       (ch1_channel_up),
        .s_axi_tx_tdata   (ch1_s_axi_tx_tdata),
        .s_axi_tx_tkeep   (ch1_s_axi_tx_tkeep),
        .s_axi_tx_tlast   (ch1_s_axi_tx_tlast),
        .s_axi_tx_tvalid  (ch1_s_axi_tx_tvalid),
        .s_axi_tx_tready  (ch1_s_axi_tx_tready)
    );

    //------------------------------------------------------------------------
    // Channel 1: Aurora Behavioral Model (loopback)
    //------------------------------------------------------------------------
    aurora_64b66b_0 u_ch1_aurora (
        .rxp                          (4'b0),
        .rxn                          (4'b1),
        .txp                          (),
        .txn                          (),
        .refclk1_in                   (1'b0),
        .user_clk                     (user_clk),
        .sync_clk                     (user_clk),
        .reset_pb                     (reset_pb),
        .power_down                   (1'b0),
        .pma_init                     (pma_init_r),
        .loopback                     (3'b000),
        .hard_err                     (ch1_hard_err),
        .soft_err                     (ch1_soft_err),
        .channel_up                   (ch1_channel_up),
        .lane_up                      (ch1_lane_up),
        .tx_out_clk                   (),
        .gt_pll_lock                  (),
        .drp_clk_in                   (init_clk),
        .s_axi_tx_tdata               (ch1_s_axi_tx_tdata),
        .s_axi_tx_tkeep               (ch1_s_axi_tx_tkeep),
        .s_axi_tx_tlast               (ch1_s_axi_tx_tlast),
        .s_axi_tx_tvalid              (ch1_s_axi_tx_tvalid),
        .s_axi_tx_tready              (ch1_s_axi_tx_tready),
        .m_axi_rx_tdata               (ch1_m_axi_rx_tdata),
        .m_axi_rx_tkeep               (ch1_m_axi_rx_tkeep),
        .m_axi_rx_tlast               (ch1_m_axi_rx_tlast),
        .m_axi_rx_tvalid              (ch1_m_axi_rx_tvalid),
        .mmcm_not_locked              (1'b0),
        .s_axi_awaddr                 (32'd0),
        .s_axi_awvalid                (1'b0),
        .s_axi_awready                (),
        .s_axi_wdata                  (32'd0),
        .s_axi_wstrb                  (4'd0),
        .s_axi_wvalid                 (1'b0),
        .s_axi_wready                 (),
        .s_axi_bvalid                 (),
        .s_axi_bresp                  (),
        .s_axi_bready                 (1'b1),
        .s_axi_araddr                 (32'd0),
        .s_axi_arvalid                (1'b0),
        .s_axi_arready                (),
        .s_axi_rdata                  (),
        .s_axi_rvalid                 (),
        .s_axi_rresp                  (),
        .s_axi_rready                 (1'b1),
        .s_axi_awaddr_lane1           (32'd0),
        .s_axi_awvalid_lane1          (1'b0),
        .s_axi_awready_lane1          (),
        .s_axi_wdata_lane1            (32'd0),
        .s_axi_wstrb_lane1            (4'd0),
        .s_axi_wvalid_lane1           (1'b0),
        .s_axi_wready_lane1           (),
        .s_axi_bvalid_lane1           (),
        .s_axi_bresp_lane1            (),
        .s_axi_bready_lane1           (1'b1),
        .s_axi_araddr_lane1           (32'd0),
        .s_axi_arvalid_lane1          (1'b0),
        .s_axi_arready_lane1          (),
        .s_axi_rdata_lane1            (),
        .s_axi_rvalid_lane1           (),
        .s_axi_rresp_lane1            (),
        .s_axi_rready_lane1           (1'b1),
        .s_axi_awaddr_lane2           (32'd0),
        .s_axi_awvalid_lane2          (1'b0),
        .s_axi_awready_lane2          (),
        .s_axi_wdata_lane2            (32'd0),
        .s_axi_wstrb_lane2            (4'd0),
        .s_axi_wvalid_lane2           (1'b0),
        .s_axi_wready_lane2           (),
        .s_axi_bvalid_lane2           (),
        .s_axi_bresp_lane2            (),
        .s_axi_bready_lane2           (1'b1),
        .s_axi_araddr_lane2           (32'd0),
        .s_axi_arvalid_lane2          (1'b0),
        .s_axi_arready_lane2          (),
        .s_axi_rdata_lane2            (),
        .s_axi_rvalid_lane2           (),
        .s_axi_rresp_lane2            (),
        .s_axi_rready_lane2           (1'b1),
        .s_axi_awaddr_lane3           (32'd0),
        .s_axi_awvalid_lane3          (1'b0),
        .s_axi_awready_lane3          (),
        .s_axi_wdata_lane3            (32'd0),
        .s_axi_wstrb_lane3            (4'd0),
        .s_axi_wvalid_lane3           (1'b0),
        .s_axi_wready_lane3           (),
        .s_axi_bvalid_lane3           (),
        .s_axi_bresp_lane3            (),
        .s_axi_bready_lane3           (1'b1),
        .s_axi_araddr_lane3           (32'd0),
        .s_axi_arvalid_lane3          (1'b0),
        .s_axi_arready_lane3          (),
        .s_axi_rdata_lane3            (),
        .s_axi_rvalid_lane3           (),
        .s_axi_rresp_lane3            (),
        .s_axi_rready_lane3           (1'b1),
        .qpll_drpaddr_in              (8'd0),
        .qpll_drpdi_in                (16'd0),
        .qpll_drpdo_out               (),
        .qpll_drprdy_out              (),
        .qpll_drpen_in                (1'b0),
        .qpll_drpwe_in                (1'b0),
        .init_clk                     (init_clk),
        .link_reset_out               (),
        .gt_qpllclk_quad1_in          (1'b0),
        .gt_qpllrefclk_quad1_in       (1'b0),
        .gt_to_common_qpllreset_out   (),
        .gt_qplllock_in               (1'b1),
        .gt_qpllrefclklost_in         (1'b0),
        .gt_rxcdrovrden_in            (1'b0),
        .sys_reset_out                ()
    );

    //------------------------------------------------------------------------
    // Channel 1: RX Module
    //------------------------------------------------------------------------
    aurora_rx_module u_ch1_rx (
        .clk              (user_clk),
        .rst              (reset_pb),
        .channel_up       (ch1_channel_up),
        .m_axi_rx_tdata   (ch1_m_axi_rx_tdata),
        .m_axi_rx_tkeep   (ch1_m_axi_rx_tkeep),
        .m_axi_rx_tlast   (ch1_m_axi_rx_tlast),
        .m_axi_rx_tvalid  (ch1_m_axi_rx_tvalid),
        .rx_data          (ch1_rx_payload),
        .rx_data_valid    (ch1_rx_payload_valid),
        .rx_sof           (ch1_rx_payload_sof),
        .rx_eof           (ch1_rx_payload_eof)
    );

    //------------------------------------------------------------------------
    // Channel 1: Data Check
    //------------------------------------------------------------------------
    aurora_data_check u_ch1_data_check (
        .clk              (user_clk),
        .rst              (reset_pb),
        .rx_data          (ch1_rx_payload),
        .rx_data_valid    (ch1_rx_payload_valid),
        .rx_sof           (ch1_rx_payload_sof),
        .rx_eof           (ch1_rx_payload_eof),
        .error_flag       (ch1_error_flag),
        .error_count      (ch1_error_count),
        .frame_count      (ch1_frame_count),
        .beat_count       (ch1_beat_count)
    );

    //------------------------------------------------------------------------
    // Monitor and report
    //------------------------------------------------------------------------
    initial begin
        $display("============================================");
        $display("  Aurora 64B66B Framing Mode Testbench");
        $display("  Dual Channel Loopback Test");
        $display("============================================");
    end

    // Monitor channel up events
    always @(posedge ch0_channel_up)
        $display("[%0t] Channel 0: channel_up asserted", $time);
    always @(posedge ch1_channel_up)
        $display("[%0t] Channel 1: channel_up asserted", $time);

    // Periodic status report
    always @(posedge user_clk) begin
        if (ch0_frame_count > 0 && ch0_frame_count % 5 == 0 &&
            ch0_rx_payload_eof && ch0_rx_payload_valid) begin
            $display("[%0t] CH0 Status: frames=%0d, beats=%0d, errors=%0d",
                     $time, ch0_frame_count, ch0_beat_count, ch0_error_count);
        end
        if (ch1_frame_count > 0 && ch1_frame_count % 5 == 0 &&
            ch1_rx_payload_eof && ch1_rx_payload_valid) begin
            $display("[%0t] CH1 Status: frames=%0d, beats=%0d, errors=%0d",
                     $time, ch1_frame_count, ch1_beat_count, ch1_error_count);
        end
    end

    // Error detection
    always @(posedge user_clk) begin
        if (ch0_error_flag && ch0_error_count == 1)
            $display("[%0t] ERROR: Channel 0 data mismatch detected!", $time);
        if (ch1_error_flag && ch1_error_count == 1)
            $display("[%0t] ERROR: Channel 1 data mismatch detected!", $time);
    end

    //------------------------------------------------------------------------
    // Simulation control
    //------------------------------------------------------------------------
    initial begin
        #SIM_TIME;

        $display("");
        $display("============================================");
        $display("  Simulation Complete");
        $display("============================================");
        $display("  Channel 0:");
        $display("    Frames received: %0d", ch0_frame_count);
        $display("    Beats received:  %0d", ch0_beat_count);
        $display("    Error count:     %0d", ch0_error_count);
        $display("    Status:          %s",
                 (ch0_frame_count > 0 && ch0_error_count == 0) ? "PASS" : "FAIL");
        $display("");
        $display("  Channel 1:");
        $display("    Frames received: %0d", ch1_frame_count);
        $display("    Beats received:  %0d", ch1_beat_count);
        $display("    Error count:     %0d", ch1_error_count);
        $display("    Status:          %s",
                 (ch1_frame_count > 0 && ch1_error_count == 0) ? "PASS" : "FAIL");
        $display("============================================");

        if (ch0_frame_count > 0 && ch0_error_count == 0 &&
            ch1_frame_count > 0 && ch1_error_count == 0) begin
            $display("  OVERALL RESULT: *** PASS ***");
        end else begin
            $display("  OVERALL RESULT: *** FAIL ***");
        end
        $display("============================================");

        $finish;
    end

    // VCD dump for waveform viewing
    initial begin
        $dumpfile("aurora_top_tb.vcd");
        $dumpvars(0, aurora_top_tb);
    end

endmodule
