///////////////////////////////////////////////////////////////////////////////
// Module: aurora_channel
// Description: Single Aurora 64B66B channel wrapper.
//
// This module wraps a single Aurora 64B66B IP core instance together with
// TX and RX data modules. It provides a clean interface for the top-level
// module to instantiate multiple channels.
//
// The Aurora IP core (aurora_64b66b_0) is configured as:
//   - 4 lanes, v7gth transceivers
//   - AXI4-Stream user interface (256-bit data, 32-bit tkeep)
//   - Shared logic in example design (external QPLL and clock)
//   - Duplex operation
//
// Target: xc7vx690tffg1927-2L
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module aurora_channel #(
    parameter DATA_WIDTH = 256,                 // AXI4-Stream data width
    parameter KEEP_WIDTH = DATA_WIDTH / 8,      // tkeep width
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
    // User TX Data Interface
    //=========================================================================
    input  wire [DATA_WIDTH-1:0]    tx_din,             // TX data input
    input  wire [KEEP_WIDTH-1:0]    tx_din_keep,        // TX byte enables
    input  wire                     tx_din_last,        // TX end of frame
    input  wire                     tx_din_valid,       // TX data valid
    output wire                     tx_ready,           // TX ready (can accept data)

    //=========================================================================
    // User RX Data Interface
    //=========================================================================
    output wire [DATA_WIDTH-1:0]    rx_dout,            // RX data output
    output wire [KEEP_WIDTH-1:0]    rx_dout_keep,       // RX byte enables
    output wire                     rx_dout_last,       // RX end of frame
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
    output wire [31:0]              rx_count,           // RX frame counter
    output wire                     rx_error            // RX error flag
);

    //=========================================================================
    // Internal signals - AXI4-Stream between TX module and Aurora IP
    //=========================================================================
    wire [DATA_WIDTH-1:0]   s_axi_tx_tdata;
    wire [KEEP_WIDTH-1:0]   s_axi_tx_tkeep;
    wire                    s_axi_tx_tlast;
    wire                    s_axi_tx_tvalid;
    wire                    s_axi_tx_tready;

    //=========================================================================
    // Internal signals - AXI4-Stream between Aurora IP and RX module
    //=========================================================================
    wire [DATA_WIDTH-1:0]   m_axi_rx_tdata;
    wire [KEEP_WIDTH-1:0]   m_axi_rx_tkeep;
    wire                    m_axi_rx_tlast;
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
    // TX Module Instance
    //=========================================================================
    aurora_tx_module #(
        .DATA_WIDTH                 (DATA_WIDTH),
        .KEEP_WIDTH                 (KEEP_WIDTH)
    ) u_aurora_tx (
        .user_clk                   (user_clk),
        .reset                      (sys_reset_out),
        .tx_din                     (tx_din),
        .tx_din_keep                (tx_din_keep),
        .tx_din_last                (tx_din_last),
        .tx_din_valid               (tx_din_valid),
        .tx_ready                   (tx_ready),
        .channel_up                 (channel_up_i),
        .s_axi_tx_tdata             (s_axi_tx_tdata),
        .s_axi_tx_tkeep             (s_axi_tx_tkeep),
        .s_axi_tx_tlast             (s_axi_tx_tlast),
        .s_axi_tx_tvalid            (s_axi_tx_tvalid),
        .s_axi_tx_tready            (s_axi_tx_tready)
    );

    //=========================================================================
    // RX Module Instance
    //=========================================================================
    aurora_rx_module #(
        .DATA_WIDTH                 (DATA_WIDTH),
        .KEEP_WIDTH                 (KEEP_WIDTH)
    ) u_aurora_rx (
        .user_clk                   (user_clk),
        .reset                      (sys_reset_out),
        .channel_up                 (channel_up_i),
        .hard_err                   (hard_err_i),
        .soft_err                   (soft_err_i),
        .m_axi_rx_tdata             (m_axi_rx_tdata),
        .m_axi_rx_tkeep             (m_axi_rx_tkeep),
        .m_axi_rx_tlast             (m_axi_rx_tlast),
        .m_axi_rx_tvalid            (m_axi_rx_tvalid),
        .rx_dout                    (rx_dout),
        .rx_dout_keep               (rx_dout_keep),
        .rx_dout_last               (rx_dout_last),
        .rx_dout_valid              (rx_dout_valid),
        .rx_count                   (rx_count),
        .rx_error                   (rx_error)
    );

    //=========================================================================
    // Aurora 64B66B IP Core Instance
    //
    // This is the Vivado-generated Aurora 64B66B IP core.
    // Component name: aurora_64b66b_0
    // Configuration:
    //   - 4 lanes, v7gth, duplex
    //   - AXI4-Stream user interface
    //   - Shared logic in example design
    //   - GT Refclk1 from GTHQ0
    //
    // IMPORTANT: The aurora_64b66b_0 module is generated by Vivado IP
    // Customization. Ensure the IP is generated before synthesis.
    //=========================================================================
    aurora_64b66b_0 u_aurora_ip (
        // AXI4-Stream TX Interface
        .s_axi_tx_tdata             (s_axi_tx_tdata),
        .s_axi_tx_tkeep             (s_axi_tx_tkeep),
        .s_axi_tx_tlast             (s_axi_tx_tlast),
        .s_axi_tx_tvalid            (s_axi_tx_tvalid),
        .s_axi_tx_tready            (s_axi_tx_tready),

        // AXI4-Stream RX Interface
        .m_axi_rx_tdata             (m_axi_rx_tdata),
        .m_axi_rx_tkeep             (m_axi_rx_tkeep),
        .m_axi_rx_tlast             (m_axi_rx_tlast),
        .m_axi_rx_tvalid            (m_axi_rx_tvalid),

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

        // TX Output Clock (for clock generation)
        .tx_out_clk                 (tx_out_clk_i),

        // Resets
        .reset_pb                   (reset_pb),
        .pma_init                   (pma_init),
        .sys_reset_out              (sys_reset_out),
        .link_reset_out             (link_reset_out),

        // Status
        .channel_up                 (channel_up_i),
        .lane_up                    (lane_up_i),
        .hard_err                   (hard_err_i),
        .soft_err                   (soft_err_i),

        // Control
        .loopback                   (3'b000),       // Normal operation (no loopback)
        .power_down                 (1'b0),         // Normal operation (not powered down)

        // GT Common QPLL Interface
        .gt_qpllclk_quad1_in       (qpll_outclk),
        .gt_qpllrefclk_quad1_in    (qpll_outrefclk),
        .gt_qplllock_quad1_in      (qpll_lock),
        .gt_qpllrefclklost_quad1_in(qpll_refclklost),

        // QPLL reset output (to GT Common)
        .gt_qpllreset_quad1_out    (qpll_reset),

        // DRP and Init Clocks
        .drp_clk_in                 (drp_clk),
        .init_clk                   (init_clk),

        // DRP Interface (Active-Low, directly connect to 0 when not used)
        // When AXI-Lite DRP is enabled in the IP, these are replaced by
        // AXI-Lite interfaces. Tie off unused AXI-Lite DRP ports.

        // AXI-Lite DRP IF 0 (Lane 0)
        .s_axi_awaddr_lane0         (32'd0),
        .s_axi_awvalid_lane0        (1'b0),
        .s_axi_awready_lane0        (),
        .s_axi_wdata_lane0          (32'd0),
        .s_axi_wstrb_lane0          (4'd0),
        .s_axi_wvalid_lane0         (1'b0),
        .s_axi_wready_lane0         (),
        .s_axi_bresp_lane0          (),
        .s_axi_bvalid_lane0         (),
        .s_axi_bready_lane0         (1'b0),
        .s_axi_araddr_lane0         (32'd0),
        .s_axi_arvalid_lane0        (1'b0),
        .s_axi_arready_lane0        (),
        .s_axi_rdata_lane0          (),
        .s_axi_rresp_lane0          (),
        .s_axi_rvalid_lane0         (),
        .s_axi_rready_lane0         (1'b0),

        // AXI-Lite DRP IF 1 (Lane 1)
        .s_axi_awaddr_lane1         (32'd0),
        .s_axi_awvalid_lane1        (1'b0),
        .s_axi_awready_lane1        (),
        .s_axi_wdata_lane1          (32'd0),
        .s_axi_wstrb_lane1          (4'd0),
        .s_axi_wvalid_lane1         (1'b0),
        .s_axi_wready_lane1         (),
        .s_axi_bresp_lane1          (),
        .s_axi_bvalid_lane1         (),
        .s_axi_bready_lane1         (1'b0),
        .s_axi_araddr_lane1         (32'd0),
        .s_axi_arvalid_lane1        (1'b0),
        .s_axi_arready_lane1        (),
        .s_axi_rdata_lane1          (),
        .s_axi_rresp_lane1          (),
        .s_axi_rvalid_lane1         (),
        .s_axi_rready_lane1         (1'b0),

        // AXI-Lite DRP IF 2 (Lane 2)
        .s_axi_awaddr_lane2         (32'd0),
        .s_axi_awvalid_lane2        (1'b0),
        .s_axi_awready_lane2        (),
        .s_axi_wdata_lane2          (32'd0),
        .s_axi_wstrb_lane2          (4'd0),
        .s_axi_wvalid_lane2         (1'b0),
        .s_axi_wready_lane2         (),
        .s_axi_bresp_lane2          (),
        .s_axi_bvalid_lane2         (),
        .s_axi_bready_lane2         (1'b0),
        .s_axi_araddr_lane2         (32'd0),
        .s_axi_arvalid_lane2        (1'b0),
        .s_axi_arready_lane2        (),
        .s_axi_rdata_lane2          (),
        .s_axi_rresp_lane2          (),
        .s_axi_rvalid_lane2         (),
        .s_axi_rready_lane2         (1'b0),

        // AXI-Lite DRP IF 3 (Lane 3)
        .s_axi_awaddr_lane3         (32'd0),
        .s_axi_awvalid_lane3        (1'b0),
        .s_axi_awready_lane3        (),
        .s_axi_wdata_lane3          (32'd0),
        .s_axi_wstrb_lane3          (4'd0),
        .s_axi_wvalid_lane3         (1'b0),
        .s_axi_wready_lane3         (),
        .s_axi_bresp_lane3          (),
        .s_axi_bvalid_lane3         (),
        .s_axi_bready_lane3         (1'b0),
        .s_axi_araddr_lane3         (32'd0),
        .s_axi_arvalid_lane3        (1'b0),
        .s_axi_arready_lane3        (),
        .s_axi_rdata_lane3          (),
        .s_axi_rresp_lane3          (),
        .s_axi_rvalid_lane3         (),
        .s_axi_rready_lane3         (1'b0),

        // GT Common DRP Interface (tie off when not used)
        .s_axi_awaddr_gtcommon      (32'd0),
        .s_axi_awvalid_gtcommon     (1'b0),
        .s_axi_awready_gtcommon     (),
        .s_axi_wdata_gtcommon       (32'd0),
        .s_axi_wstrb_gtcommon       (4'd0),
        .s_axi_wvalid_gtcommon      (1'b0),
        .s_axi_wready_gtcommon      (),
        .s_axi_bresp_gtcommon       (),
        .s_axi_bvalid_gtcommon      (),
        .s_axi_bready_gtcommon      (1'b0),
        .s_axi_araddr_gtcommon      (32'd0),
        .s_axi_arvalid_gtcommon     (1'b0),
        .s_axi_arready_gtcommon     (),
        .s_axi_rdata_gtcommon       (),
        .s_axi_rresp_gtcommon       (),
        .s_axi_rvalid_gtcommon      (),
        .s_axi_rready_gtcommon      (1'b0)
    );

endmodule
