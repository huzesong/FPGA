///////////////////////////////////////////////////////////////////////////////
// Module: aurora_channel
// Description: Single Aurora 64B66B channel wrapper (Streaming mode).
//
// This module wraps a single Aurora 64B66B IP core instance together with
// TX and RX data modules. It provides a clean interface for the top-level
// module to instantiate multiple channels.
//
// The Aurora IP core (aurora_64b66b_0) is configured as:
//   - 4 lanes, v7gth transceivers
//   - Line Rate: 10 Gbps, GT Refclk: 156.25 MHz
//   - AXI4-Stream Streaming user interface (256-bit data, no tkeep/tlast)
//   - Shared logic in example design (external QPLL and clock)
//   - Duplex operation, Flow Control: None
//   - DRP Mode: AXI4 Lite (per-lane), QPLL DRP: Native
//
// Target: xc7vx690tffg1927-2L
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module aurora_channel #(
    parameter DATA_WIDTH = 256,                 // AXI4-Stream data width
    parameter LANE_NUM   = 4                    // Number of GT lanes
) (
    //=========================================================================
    // Clock and Reset
    //=========================================================================
    input  wire                     user_clk,           // Aurora user clock (shared)
    input  wire                     sync_clk,           // Aurora sync clock (shared)
    input  wire                     init_clk,           // Initialization clock
    input  wire                     drp_clk,            // DRP clock
    input  wire                     gt_refclk,          // GT reference clock (from IBUFDS_GTE2)
    input  wire                     reset_pb,           // Core reset (active high)
    input  wire                     pma_init,           // PMA initialization

    //=========================================================================
    // QPLL Interface (from GT Common)
    //=========================================================================
    input  wire                     qpll_outclk,        // QPLL output clock
    input  wire                     qpll_outrefclk,     // QPLL output reference clock
    input  wire                     qpll_lock,          // QPLL lock indicator
    input  wire                     qpll_refclklost,    // QPLL reference clock lost
    output wire                     qpll_reset,         // QPLL reset request (to GT Common)

    //=========================================================================
    // GT Serial Interface
    //=========================================================================
    input  wire [LANE_NUM-1:0]      rxp,                // Serial RX positive
    input  wire [LANE_NUM-1:0]      rxn,                // Serial RX negative
    output wire [LANE_NUM-1:0]      txp,                // Serial TX positive
    output wire [LANE_NUM-1:0]      txn,                // Serial TX negative

    //=========================================================================
    // User TX Data Interface (Streaming mode)
    //=========================================================================
    input  wire [DATA_WIDTH-1:0]    tx_din,             // TX data input
    input  wire                     tx_din_valid,       // TX data valid
    output wire                     tx_ready,           // TX ready (can accept data)

    //=========================================================================
    // User RX Data Interface (Streaming mode)
    //=========================================================================
    output wire [DATA_WIDTH-1:0]    rx_dout,            // RX data output
    output wire                     rx_dout_valid,      // RX data valid

    //=========================================================================
    // Status
    //=========================================================================
    output wire                     channel_up,         // Aurora channel up
    output wire [LANE_NUM-1:0]      lane_up,            // Per-lane link up
    output wire                     hard_err,           // Hard error
    output wire                     soft_err,           // Soft error
    output wire                     tx_out_clk,         // TX output clock (for clock sharing)

    //=========================================================================
    // Diagnostics
    //=========================================================================
    output wire [31:0]              rx_count,           // RX beat counter
    output wire                     rx_error            // RX error flag
);

    //=========================================================================
    // Internal signals - AXI4-Stream between TX module and Aurora IP
    //=========================================================================
    wire [DATA_WIDTH-1:0]   s_axi_tx_tdata;
    wire                    s_axi_tx_tvalid;
    wire                    s_axi_tx_tready;

    //=========================================================================
    // Internal signals - AXI4-Stream between Aurora IP and RX module
    //=========================================================================
    wire [DATA_WIDTH-1:0]   m_axi_rx_tdata;
    wire                    m_axi_rx_tvalid;

    //=========================================================================
    // Internal signals - Aurora status and control
    //=========================================================================
    wire                    sys_reset_out;
    wire                    link_reset_out;
    wire                    channel_up_i;
    wire [LANE_NUM-1:0]     lane_up_i;
    wire                    hard_err_i;
    wire                    soft_err_i;
    wire                    tx_out_clk_i;

    //=========================================================================
    // Status output assignments
    //=========================================================================
    assign channel_up  = channel_up_i;
    assign lane_up     = lane_up_i;
    assign hard_err    = hard_err_i;
    assign soft_err    = soft_err_i;
    assign tx_out_clk  = tx_out_clk_i;

    //=========================================================================
    // TX Module Instance (Streaming mode)
    //=========================================================================
    aurora_tx_module #(
        .DATA_WIDTH                 (DATA_WIDTH)
    ) u_aurora_tx (
        .user_clk                   (user_clk),
        .reset                      (sys_reset_out),
        .tx_din                     (tx_din),
        .tx_din_valid               (tx_din_valid),
        .tx_ready                   (tx_ready),
        .channel_up                 (channel_up_i),
        .s_axi_tx_tdata             (s_axi_tx_tdata),
        .s_axi_tx_tvalid            (s_axi_tx_tvalid),
        .s_axi_tx_tready            (s_axi_tx_tready)
    );

    //=========================================================================
    // RX Module Instance (Streaming mode)
    //=========================================================================
    aurora_rx_module #(
        .DATA_WIDTH                 (DATA_WIDTH)
    ) u_aurora_rx (
        .user_clk                   (user_clk),
        .reset                      (sys_reset_out),
        .channel_up                 (channel_up_i),
        .hard_err                   (hard_err_i),
        .soft_err                   (soft_err_i),
        .m_axi_rx_tdata             (m_axi_rx_tdata),
        .m_axi_rx_tvalid            (m_axi_rx_tvalid),
        .rx_dout                    (rx_dout),
        .rx_dout_valid              (rx_dout_valid),
        .rx_count                   (rx_count),
        .rx_error                   (rx_error)
    );

    //=========================================================================
    // Aurora 64B66B IP Core Instance (Streaming mode)
    //
    // Component name: aurora_64b66b_0
    // Configuration (from Vivado IP Customization):
    //   - Line Rate: 10 Gbps, GT Refclk: 156.25 MHz
    //   - Init clk: 50 MHz, DRP clk: 50 MHz
    //   - 4 lanes, v7gth, Duplex, Streaming, Flow Control: None
    //   - DRP Mode: AXI4 Lite (per-lane), QPLL DRP: Native
    //   - Shared logic in example design
    //
    // Port list matches the IP instantiation template generated by Vivado.
    //=========================================================================
    aurora_64b66b_0 u_aurora_ip (
        // GT Serial Interface
        .rxp                        (rxp),
        .rxn                        (rxn),
        .txp                        (txp),
        .txn                        (txn),

        // GT Reference Clock
        .refclk1_in                 (gt_refclk),

        // User Clock and Sync Clock
        .user_clk                   (user_clk),
        .sync_clk                   (sync_clk),

        // Resets
        .reset_pb                   (reset_pb),
        .power_down                 (1'b0),
        .pma_init                   (pma_init),

        // Control
        .loopback                   (3'b000),

        // TX Output Clock
        .tx_out_clk                 (tx_out_clk_i),

        // DRP and Init Clocks
        .drp_clk_in                 (drp_clk),
        .init_clk                   (init_clk),

        // Status
        .hard_err                   (hard_err_i),
        .soft_err                   (soft_err_i),
        .channel_up                 (channel_up_i),
        .lane_up                    (lane_up_i),
        .gt_pll_lock                (),

        // Reset outputs
        .sys_reset_out              (sys_reset_out),
        .link_reset_out             (link_reset_out),

        // AXI4-Stream TX Interface (Streaming: no tkeep, no tlast)
        .s_axi_tx_tdata             (s_axi_tx_tdata),
        .s_axi_tx_tvalid            (s_axi_tx_tvalid),
        .s_axi_tx_tready            (s_axi_tx_tready),

        // AXI4-Stream RX Interface (Streaming: no tkeep, no tlast)
        .m_axi_rx_tdata             (m_axi_rx_tdata),
        .m_axi_rx_tvalid            (m_axi_rx_tvalid),

        // MMCM lock status (no MMCM used, tie to 0 = locked)
        .mmcm_not_locked            (1'b0),

        // AXI-Lite DRP IF - Lane 0 (no _lane0 suffix)
        .s_axi_awaddr               (32'd0),
        .s_axi_awvalid              (1'b0),
        .s_axi_awready              (),
        .s_axi_wdata                (32'd0),
        .s_axi_wstrb                (4'd0),
        .s_axi_wvalid               (1'b0),
        .s_axi_wready               (),
        .s_axi_bvalid               (),
        .s_axi_bresp                (),
        .s_axi_bready               (1'b0),
        .s_axi_araddr               (32'd0),
        .s_axi_arvalid              (1'b0),
        .s_axi_arready              (),
        .s_axi_rdata                (),
        .s_axi_rresp                (),
        .s_axi_rvalid               (),
        .s_axi_rready               (1'b0),

        // AXI-Lite DRP IF - Lane 1
        .s_axi_awaddr_lane1         (32'd0),
        .s_axi_awvalid_lane1        (1'b0),
        .s_axi_awready_lane1        (),
        .s_axi_wdata_lane1          (32'd0),
        .s_axi_wstrb_lane1          (4'd0),
        .s_axi_wvalid_lane1         (1'b0),
        .s_axi_wready_lane1         (),
        .s_axi_bvalid_lane1         (),
        .s_axi_bresp_lane1          (),
        .s_axi_bready_lane1         (1'b0),
        .s_axi_araddr_lane1         (32'd0),
        .s_axi_arvalid_lane1        (1'b0),
        .s_axi_arready_lane1        (),
        .s_axi_rdata_lane1          (),
        .s_axi_rresp_lane1          (),
        .s_axi_rvalid_lane1         (),
        .s_axi_rready_lane1         (1'b0),

        // AXI-Lite DRP IF - Lane 2
        .s_axi_awaddr_lane2         (32'd0),
        .s_axi_awvalid_lane2        (1'b0),
        .s_axi_awready_lane2        (),
        .s_axi_wdata_lane2          (32'd0),
        .s_axi_wstrb_lane2          (4'd0),
        .s_axi_wvalid_lane2         (1'b0),
        .s_axi_wready_lane2         (),
        .s_axi_bvalid_lane2         (),
        .s_axi_bresp_lane2          (),
        .s_axi_bready_lane2         (1'b0),
        .s_axi_araddr_lane2         (32'd0),
        .s_axi_arvalid_lane2        (1'b0),
        .s_axi_arready_lane2        (),
        .s_axi_rdata_lane2          (),
        .s_axi_rresp_lane2          (),
        .s_axi_rvalid_lane2         (),
        .s_axi_rready_lane2         (1'b0),

        // AXI-Lite DRP IF - Lane 3
        .s_axi_awaddr_lane3         (32'd0),
        .s_axi_awvalid_lane3        (1'b0),
        .s_axi_awready_lane3        (),
        .s_axi_wdata_lane3          (32'd0),
        .s_axi_wstrb_lane3          (4'd0),
        .s_axi_wvalid_lane3         (1'b0),
        .s_axi_wready_lane3         (),
        .s_axi_bvalid_lane3         (),
        .s_axi_bresp_lane3          (),
        .s_axi_bready_lane3         (1'b0),
        .s_axi_araddr_lane3         (32'd0),
        .s_axi_arvalid_lane3        (1'b0),
        .s_axi_arready_lane3        (),
        .s_axi_rdata_lane3          (),
        .s_axi_rresp_lane3          (),
        .s_axi_rvalid_lane3         (),
        .s_axi_rready_lane3         (1'b0),

        // QPLL Native DRP Interface (tie off when not used)
        .qpll_drpaddr_in            (8'd0),
        .qpll_drpdi_in              (16'd0),
        .qpll_drpen_in              (1'b0),
        .qpll_drpwe_in              (1'b0),
        .qpll_drprdy_out            (),
        .qpll_drpdo_out             (),

        // GT Common QPLL Interface
        .gt_qpllclk_quad1_in        (qpll_outclk),
        .gt_qpllrefclk_quad1_in     (qpll_outrefclk),
        .gt_qplllock_in             (qpll_lock),
        .gt_qpllrefclklost_in       (qpll_refclklost),
        .gt_to_common_qpllreset_out (qpll_reset),

        // GT CDR override (normal operation)
        .gt_rxcdrovrden_in          (1'b0)
    );

endmodule
