//////////////////////////////////////////////////////////////////////////////
// Module: aurora_64b66b_0 (Behavioral Model)
// Description: Behavioral model of Aurora 64B66B IP core for simulation.
//              Implements TX-to-RX loopback with configurable latency.
//              Simulates channel_up/lane_up timing after reset.
//              This model replaces the actual Xilinx IP for simulation.
//////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module aurora_64b66b_0 (
    // GT Serial
    input  wire [0:3]   rxp,
    input  wire [0:3]   rxn,
    output wire [0:3]   txp,
    output wire [0:3]   txn,
    // Reference clock
    input  wire         refclk1_in,
    // User clock domain
    input  wire         user_clk,
    input  wire         sync_clk,
    input  wire         reset_pb,
    input  wire         power_down,
    input  wire         pma_init,
    input  wire [2:0]   loopback,
    // Status
    output reg          hard_err,
    output reg          soft_err,
    output reg          channel_up,
    output reg  [0:3]   lane_up,
    output wire         tx_out_clk,
    output wire         gt_pll_lock,
    // DRP clock
    input  wire         drp_clk_in,
    // AXI-Stream TX
    input  wire [0:255] s_axi_tx_tdata,
    input  wire [0:31]  s_axi_tx_tkeep,
    input  wire         s_axi_tx_tlast,
    input  wire         s_axi_tx_tvalid,
    output wire         s_axi_tx_tready,
    // AXI-Stream RX
    output wire [0:255] m_axi_rx_tdata,
    output wire [0:31]  m_axi_rx_tkeep,
    output wire         m_axi_rx_tlast,
    output wire         m_axi_rx_tvalid,
    // MMCM
    input  wire         mmcm_not_locked,
    // AXI4-Lite DRP - Lane 0
    input  wire [31:0]  s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire         s_axi_bvalid,
    output wire [1:0]   s_axi_bresp,
    input  wire         s_axi_bready,
    input  wire [31:0]  s_axi_araddr,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire         s_axi_rvalid,
    output wire [1:0]   s_axi_rresp,
    input  wire         s_axi_rready,
    // AXI4-Lite DRP - Lane 1
    input  wire [31:0]  s_axi_awaddr_lane1,
    input  wire         s_axi_awvalid_lane1,
    output wire         s_axi_awready_lane1,
    input  wire [31:0]  s_axi_wdata_lane1,
    input  wire [3:0]   s_axi_wstrb_lane1,
    input  wire         s_axi_wvalid_lane1,
    output wire         s_axi_wready_lane1,
    output wire         s_axi_bvalid_lane1,
    output wire [1:0]   s_axi_bresp_lane1,
    input  wire         s_axi_bready_lane1,
    input  wire [31:0]  s_axi_araddr_lane1,
    input  wire         s_axi_arvalid_lane1,
    output wire         s_axi_arready_lane1,
    output wire [31:0]  s_axi_rdata_lane1,
    output wire         s_axi_rvalid_lane1,
    output wire [1:0]   s_axi_rresp_lane1,
    input  wire         s_axi_rready_lane1,
    // AXI4-Lite DRP - Lane 2
    input  wire [31:0]  s_axi_awaddr_lane2,
    input  wire         s_axi_awvalid_lane2,
    output wire         s_axi_awready_lane2,
    input  wire [31:0]  s_axi_wdata_lane2,
    input  wire [3:0]   s_axi_wstrb_lane2,
    input  wire         s_axi_wvalid_lane2,
    output wire         s_axi_wready_lane2,
    output wire         s_axi_bvalid_lane2,
    output wire [1:0]   s_axi_bresp_lane2,
    input  wire         s_axi_bready_lane2,
    input  wire [31:0]  s_axi_araddr_lane2,
    input  wire         s_axi_arvalid_lane2,
    output wire         s_axi_arready_lane2,
    output wire [31:0]  s_axi_rdata_lane2,
    output wire         s_axi_rvalid_lane2,
    output wire [1:0]   s_axi_rresp_lane2,
    input  wire         s_axi_rready_lane2,
    // AXI4-Lite DRP - Lane 3
    input  wire [31:0]  s_axi_awaddr_lane3,
    input  wire         s_axi_awvalid_lane3,
    output wire         s_axi_awready_lane3,
    input  wire [31:0]  s_axi_wdata_lane3,
    input  wire [3:0]   s_axi_wstrb_lane3,
    input  wire         s_axi_wvalid_lane3,
    output wire         s_axi_wready_lane3,
    output wire         s_axi_bvalid_lane3,
    output wire [1:0]   s_axi_bresp_lane3,
    input  wire         s_axi_bready_lane3,
    input  wire [31:0]  s_axi_araddr_lane3,
    input  wire         s_axi_arvalid_lane3,
    output wire         s_axi_arready_lane3,
    output wire [31:0]  s_axi_rdata_lane3,
    output wire         s_axi_rvalid_lane3,
    output wire [1:0]   s_axi_rresp_lane3,
    input  wire         s_axi_rready_lane3,
    // QPLL DRP
    input  wire [7:0]   qpll_drpaddr_in,
    input  wire [15:0]  qpll_drpdi_in,
    output wire [15:0]  qpll_drpdo_out,
    output wire         qpll_drprdy_out,
    input  wire         qpll_drpen_in,
    input  wire         qpll_drpwe_in,
    // Init clock
    input  wire         init_clk,
    // Link reset
    output wire         link_reset_out,
    // QPLL interface
    input  wire         gt_qpllclk_quad1_in,
    input  wire         gt_qpllrefclk_quad1_in,
    output wire         gt_to_common_qpllreset_out,
    input  wire         gt_qplllock_in,
    input  wire         gt_qpllrefclklost_in,
    // CDR
    input  wire         gt_rxcdrovrden_in,
    // System reset
    output wire         sys_reset_out
);

    //------------------------------------------------------------------------
    // Parameters
    //------------------------------------------------------------------------
    localparam LOOPBACK_LATENCY = 4;   // Loopback pipeline stages
    localparam CHANNEL_UP_DELAY = 20;  // Cycles after reset for channel_up

    //------------------------------------------------------------------------
    // TX output clock: pass through user_clk
    //------------------------------------------------------------------------
    assign tx_out_clk = user_clk;

    //------------------------------------------------------------------------
    // GT PLL lock: assert after reset
    //------------------------------------------------------------------------
    reg gt_pll_lock_r;
    reg [7:0] pll_cnt;

    initial begin
        gt_pll_lock_r = 1'b0;
        pll_cnt       = 8'd0;
        ch_up_cnt     = 8'd0;
        channel_up    = 1'b0;
        lane_up       = 4'b0000;
        hard_err      = 1'b0;
        soft_err      = 1'b0;
    end

    always @(posedge init_clk) begin
        if (pma_init || reset_pb) begin
            pll_cnt       <= 8'd0;
            gt_pll_lock_r <= 1'b0;
        end else if (pll_cnt < 8'd10) begin
            pll_cnt       <= pll_cnt + 8'd1;
            gt_pll_lock_r <= 1'b0;
        end else begin
            gt_pll_lock_r <= 1'b1;
        end
    end

    assign gt_pll_lock = gt_pll_lock_r;

    //------------------------------------------------------------------------
    // Channel up / Lane up simulation
    //------------------------------------------------------------------------
    reg [7:0] ch_up_cnt;

    always @(posedge user_clk) begin
        if (reset_pb || pma_init || mmcm_not_locked) begin
            ch_up_cnt  <= 8'd0;
            channel_up <= 1'b0;
            lane_up    <= 4'b0000;
            hard_err   <= 1'b0;
            soft_err   <= 1'b0;
        end else if (ch_up_cnt < CHANNEL_UP_DELAY) begin
            ch_up_cnt  <= ch_up_cnt + 8'd1;
            channel_up <= 1'b0;
            lane_up    <= 4'b0000;
        end else begin
            channel_up <= 1'b1;
            lane_up    <= 4'b1111;
        end
    end

    //------------------------------------------------------------------------
    // TX Ready: always ready when channel is up
    //------------------------------------------------------------------------
    assign s_axi_tx_tready = channel_up;

    //------------------------------------------------------------------------
    // Loopback: TX data → RX data with pipeline delay
    //------------------------------------------------------------------------
    reg [255:0] lb_data  [0:LOOPBACK_LATENCY-1];
    reg [31:0]  lb_keep  [0:LOOPBACK_LATENCY-1];
    reg         lb_last  [0:LOOPBACK_LATENCY-1];
    reg         lb_valid [0:LOOPBACK_LATENCY-1];

    integer i;

    always @(posedge user_clk) begin
        if (reset_pb) begin
            for (i = 0; i < LOOPBACK_LATENCY; i = i + 1) begin
                lb_data[i]  <= 256'd0;
                lb_keep[i]  <= 32'd0;
                lb_last[i]  <= 1'b0;
                lb_valid[i] <= 1'b0;
            end
        end else begin
            // Stage 0: capture TX data
            lb_data[0]  <= s_axi_tx_tdata;
            lb_keep[0]  <= s_axi_tx_tkeep;
            lb_last[0]  <= s_axi_tx_tlast;
            lb_valid[0] <= s_axi_tx_tvalid & s_axi_tx_tready;
            // Pipeline stages
            for (i = 1; i < LOOPBACK_LATENCY; i = i + 1) begin
                lb_data[i]  <= lb_data[i-1];
                lb_keep[i]  <= lb_keep[i-1];
                lb_last[i]  <= lb_last[i-1];
                lb_valid[i] <= lb_valid[i-1];
            end
        end
    end

    // RX output from loopback pipeline
    assign m_axi_rx_tdata  = lb_data[LOOPBACK_LATENCY-1];
    assign m_axi_rx_tkeep  = lb_keep[LOOPBACK_LATENCY-1];
    assign m_axi_rx_tlast  = lb_last[LOOPBACK_LATENCY-1];
    assign m_axi_rx_tvalid = lb_valid[LOOPBACK_LATENCY-1];

    //------------------------------------------------------------------------
    // Unused outputs - tie off
    //------------------------------------------------------------------------
    assign gt_to_common_qpllreset_out = pma_init;
    assign link_reset_out             = 1'b0;
    assign sys_reset_out              = reset_pb;

    // GT Serial (unused in behavioral model)
    assign txp = 4'b0;
    assign txn = 4'b1;

    // AXI4-Lite DRP responses - tie off
    assign s_axi_awready       = 1'b0;
    assign s_axi_wready        = 1'b0;
    assign s_axi_bvalid        = 1'b0;
    assign s_axi_bresp         = 2'b00;
    assign s_axi_arready       = 1'b0;
    assign s_axi_rdata         = 32'd0;
    assign s_axi_rvalid        = 1'b0;
    assign s_axi_rresp         = 2'b00;

    assign s_axi_awready_lane1 = 1'b0;
    assign s_axi_wready_lane1  = 1'b0;
    assign s_axi_bvalid_lane1  = 1'b0;
    assign s_axi_bresp_lane1   = 2'b00;
    assign s_axi_arready_lane1 = 1'b0;
    assign s_axi_rdata_lane1   = 32'd0;
    assign s_axi_rvalid_lane1  = 1'b0;
    assign s_axi_rresp_lane1   = 2'b00;

    assign s_axi_awready_lane2 = 1'b0;
    assign s_axi_wready_lane2  = 1'b0;
    assign s_axi_bvalid_lane2  = 1'b0;
    assign s_axi_bresp_lane2   = 2'b00;
    assign s_axi_arready_lane2 = 1'b0;
    assign s_axi_rdata_lane2   = 32'd0;
    assign s_axi_rvalid_lane2  = 1'b0;
    assign s_axi_rresp_lane2   = 2'b00;

    assign s_axi_awready_lane3 = 1'b0;
    assign s_axi_wready_lane3  = 1'b0;
    assign s_axi_bvalid_lane3  = 1'b0;
    assign s_axi_bresp_lane3   = 2'b00;
    assign s_axi_arready_lane3 = 1'b0;
    assign s_axi_rdata_lane3   = 32'd0;
    assign s_axi_rvalid_lane3  = 1'b0;
    assign s_axi_rresp_lane3   = 2'b00;

    // QPLL DRP
    assign qpll_drpdo_out  = 16'd0;
    assign qpll_drprdy_out = 1'b0;

endmodule
