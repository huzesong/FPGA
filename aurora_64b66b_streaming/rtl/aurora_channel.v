//////////////////////////////////////////////////////////////////////////////
// Module: aurora_channel
// Description: Single Aurora 64B66B channel wrapper for streaming mode.
//              Instantiates one Aurora IP core along with TX module (data
//              generation) and data check module. In streaming mode, the
//              AXI-Stream interface has no tkeep or tlast signals, and data
//              flows continuously without frame boundaries.
//              Each channel has 4 lanes with 256-bit streaming AXI-Stream.
//////////////////////////////////////////////////////////////////////////////

module aurora_channel #(
    parameter CHANNEL_ID = 0
)(
    // Clock and reset
    input  wire         user_clk,
    input  wire         sync_clk,
    input  wire         reset_pb,
    input  wire         init_clk,
    input  wire         drp_clk,
    input  wire         pma_init,
    input  wire         mmcm_not_locked,
    // GT Serial
    input  wire [3:0]   rxp,
    input  wire [3:0]   rxn,
    output wire [3:0]   txp,
    output wire [3:0]   txn,
    // Reference clock
    input  wire         refclk1_in,
    // QPLL interface
    input  wire         gt_qpllclk_quad_in,
    input  wire         gt_qpllrefclk_quad_in,
    output wire         gt_to_common_qpllreset_out,
    input  wire         gt_qplllock_in,
    input  wire         gt_qpllrefclklost_in,
    // Status
    output wire         channel_up,
    output wire [3:0]   lane_up,
    output wire         hard_err,
    output wire         soft_err,
    output wire         tx_out_clk,
    output wire         gt_pll_lock,
    output wire         link_reset_out,
    output wire         sys_reset_out,
    // Data check status
    output wire         error_flag,
    output wire [31:0]  error_count,
    output wire [31:0]  beat_count
);

    //------------------------------------------------------------------------
    // Internal wires - AXI-Stream TX (streaming: no tkeep, no tlast)
    //------------------------------------------------------------------------
    wire [255:0] s_axi_tx_tdata;
    wire         s_axi_tx_tvalid;
    wire         s_axi_tx_tready;

    //------------------------------------------------------------------------
    // Internal wires - AXI-Stream RX (streaming: no tkeep, no tlast)
    //------------------------------------------------------------------------
    wire [255:0] m_axi_rx_tdata;
    wire         m_axi_rx_tvalid;

    //------------------------------------------------------------------------
    // Internal wires - AXI4-Lite DRP (tie off unused)
    //------------------------------------------------------------------------
    wire [1:0]   s_axi_rresp, s_axi_rresp_lane1, s_axi_rresp_lane2, s_axi_rresp_lane3;
    wire [1:0]   s_axi_bresp, s_axi_bresp_lane1, s_axi_bresp_lane2, s_axi_bresp_lane3;
    wire [31:0]  s_axi_rdata, s_axi_rdata_lane1, s_axi_rdata_lane2, s_axi_rdata_lane3;
    wire         s_axi_awready, s_axi_awready_lane1, s_axi_awready_lane2, s_axi_awready_lane3;
    wire         s_axi_wready, s_axi_wready_lane1, s_axi_wready_lane2, s_axi_wready_lane3;
    wire         s_axi_bvalid, s_axi_bvalid_lane1, s_axi_bvalid_lane2, s_axi_bvalid_lane3;
    wire         s_axi_arready, s_axi_arready_lane1, s_axi_arready_lane2, s_axi_arready_lane3;
    wire         s_axi_rvalid, s_axi_rvalid_lane1, s_axi_rvalid_lane2, s_axi_rvalid_lane3;

    //------------------------------------------------------------------------
    // TX Module: data generation → Aurora TX (no frame assembly)
    // (Reset from Aurora IP sys_reset_out, matching Xilinx example design)
    //------------------------------------------------------------------------
    aurora_tx_module u_tx_module (
        .clk              (user_clk),
        .rst              (sys_reset_out),
        .channel_up       (channel_up),
        .s_axi_tx_tdata   (s_axi_tx_tdata),
        .s_axi_tx_tvalid  (s_axi_tx_tvalid),
        .s_axi_tx_tready  (s_axi_tx_tready)
    );

    //------------------------------------------------------------------------
    // Data Check Module: verify received data (directly from Aurora RX)
    // In streaming mode, there is no RX frame parser — Aurora RX data goes
    // directly to the checker.
    //------------------------------------------------------------------------
    aurora_data_check u_data_check (
        .clk              (user_clk),
        .rst              (sys_reset_out),
        .rx_data          (m_axi_rx_tdata),
        .rx_data_valid    (m_axi_rx_tvalid),
        .error_flag       (error_flag),
        .error_count      (error_count),
        .beat_count       (beat_count)
    );

    //------------------------------------------------------------------------
    // Aurora 64B66B IP Core Instance (Streaming Mode)
    // In streaming mode the IP does NOT expose tkeep or tlast ports.
    //------------------------------------------------------------------------
    aurora_64b66b_0 u_aurora_core (
        // GT Serial
        .rxp                          (rxp),
        .rxn                          (rxn),
        .txp                          (txp),
        .txn                          (txn),
        // Reference clock
        .refclk1_in                   (refclk1_in),
        // User clock domain
        .user_clk                     (user_clk),
        .sync_clk                     (sync_clk),
        .reset_pb                     (reset_pb),
        .power_down                   (1'b0),
        .pma_init                     (pma_init),
        .loopback                     (3'b000),
        // Status
        .hard_err                     (hard_err),
        .soft_err                     (soft_err),
        .channel_up                   (channel_up),
        .lane_up                      (lane_up),
        .tx_out_clk                   (tx_out_clk),
        .gt_pll_lock                  (gt_pll_lock),
        // DRP clock
        .drp_clk_in                   (drp_clk),
        // AXI-Stream TX (streaming: no tkeep, no tlast)
        .s_axi_tx_tdata               (s_axi_tx_tdata),
        .s_axi_tx_tvalid              (s_axi_tx_tvalid),
        .s_axi_tx_tready              (s_axi_tx_tready),
        // AXI-Stream RX (streaming: no tkeep, no tlast)
        .m_axi_rx_tdata               (m_axi_rx_tdata),
        .m_axi_rx_tvalid              (m_axi_rx_tvalid),
        // MMCM
        .mmcm_not_locked              (mmcm_not_locked),
        // AXI4-Lite DRP - Lane 0 (tie off)
        .s_axi_awaddr                 (32'd0),
        .s_axi_awvalid                (1'b0),
        .s_axi_awready                (s_axi_awready),
        .s_axi_wdata                  (32'd0),
        .s_axi_wstrb                  (4'd0),
        .s_axi_wvalid                 (1'b0),
        .s_axi_wready                 (s_axi_wready),
        .s_axi_bvalid                 (s_axi_bvalid),
        .s_axi_bresp                  (s_axi_bresp),
        .s_axi_bready                 (1'b1),
        .s_axi_araddr                 (32'd0),
        .s_axi_arvalid                (1'b0),
        .s_axi_arready                (s_axi_arready),
        .s_axi_rdata                  (s_axi_rdata),
        .s_axi_rvalid                 (s_axi_rvalid),
        .s_axi_rresp                  (s_axi_rresp),
        .s_axi_rready                 (1'b1),
        // AXI4-Lite DRP - Lane 1
        .s_axi_awaddr_lane1           (32'd0),
        .s_axi_awvalid_lane1          (1'b0),
        .s_axi_awready_lane1          (s_axi_awready_lane1),
        .s_axi_wdata_lane1            (32'd0),
        .s_axi_wstrb_lane1            (4'd0),
        .s_axi_wvalid_lane1           (1'b0),
        .s_axi_wready_lane1           (s_axi_wready_lane1),
        .s_axi_bvalid_lane1           (s_axi_bvalid_lane1),
        .s_axi_bresp_lane1            (s_axi_bresp_lane1),
        .s_axi_bready_lane1           (1'b1),
        .s_axi_araddr_lane1           (32'd0),
        .s_axi_arvalid_lane1          (1'b0),
        .s_axi_arready_lane1          (s_axi_arready_lane1),
        .s_axi_rdata_lane1            (s_axi_rdata_lane1),
        .s_axi_rvalid_lane1           (s_axi_rvalid_lane1),
        .s_axi_rresp_lane1            (s_axi_rresp_lane1),
        .s_axi_rready_lane1           (1'b1),
        // AXI4-Lite DRP - Lane 2
        .s_axi_awaddr_lane2           (32'd0),
        .s_axi_awvalid_lane2          (1'b0),
        .s_axi_awready_lane2          (s_axi_awready_lane2),
        .s_axi_wdata_lane2            (32'd0),
        .s_axi_wstrb_lane2            (4'd0),
        .s_axi_wvalid_lane2           (1'b0),
        .s_axi_wready_lane2           (s_axi_wready_lane2),
        .s_axi_bvalid_lane2           (s_axi_bvalid_lane2),
        .s_axi_bresp_lane2            (s_axi_bresp_lane2),
        .s_axi_bready_lane2           (1'b1),
        .s_axi_araddr_lane2           (32'd0),
        .s_axi_arvalid_lane2          (1'b0),
        .s_axi_arready_lane2          (s_axi_arready_lane2),
        .s_axi_rdata_lane2            (s_axi_rdata_lane2),
        .s_axi_rvalid_lane2           (s_axi_rvalid_lane2),
        .s_axi_rresp_lane2            (s_axi_rresp_lane2),
        .s_axi_rready_lane2           (1'b1),
        // AXI4-Lite DRP - Lane 3
        .s_axi_awaddr_lane3           (32'd0),
        .s_axi_awvalid_lane3          (1'b0),
        .s_axi_awready_lane3          (s_axi_awready_lane3),
        .s_axi_wdata_lane3            (32'd0),
        .s_axi_wstrb_lane3            (4'd0),
        .s_axi_wvalid_lane3           (1'b0),
        .s_axi_wready_lane3           (s_axi_wready_lane3),
        .s_axi_bvalid_lane3           (s_axi_bvalid_lane3),
        .s_axi_bresp_lane3            (s_axi_bresp_lane3),
        .s_axi_bready_lane3           (1'b1),
        .s_axi_araddr_lane3           (32'd0),
        .s_axi_arvalid_lane3          (1'b0),
        .s_axi_arready_lane3          (s_axi_arready_lane3),
        .s_axi_rdata_lane3            (s_axi_rdata_lane3),
        .s_axi_rvalid_lane3           (s_axi_rvalid_lane3),
        .s_axi_rresp_lane3            (s_axi_rresp_lane3),
        .s_axi_rready_lane3           (1'b1),
        // QPLL DRP (directly tied off — not used in normal operation)
        .qpll_drpaddr_in              (8'd0),
        .qpll_drpdi_in                (16'd0),
        .qpll_drpdo_out               (),
        .qpll_drprdy_out              (),
        .qpll_drpen_in                (1'b0),
        .qpll_drpwe_in                (1'b0),
        // Init and control clocks
        .init_clk                     (init_clk),
        // QPLL interface (port names use 'quad1' suffix — fixed by the IP generator,
        // the actual quad is determined by the external GTHE2_COMMON connection)
        .gt_qpllclk_quad1_in          (gt_qpllclk_quad_in),
        .gt_qpllrefclk_quad1_in       (gt_qpllrefclk_quad_in),
        .gt_to_common_qpllreset_out   (gt_to_common_qpllreset_out),
        .gt_qplllock_in               (gt_qplllock_in),
        .gt_qpllrefclklost_in         (gt_qpllrefclklost_in),
        // CDR
        .gt_rxcdrovrden_in            (1'b0),
        // System reset
        .link_reset_out               (link_reset_out),
        .sys_reset_out                (sys_reset_out)
    );

endmodule
