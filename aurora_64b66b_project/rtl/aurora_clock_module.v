///////////////////////////////////////////////////////////////////////////////
// Module: aurora_clock_module
// Description: Shared clock and reset management for dual Aurora 64B66B cores.
//
// This module provides:
//   1. IBUFDS_GTE2 for differential GT reference clock
//   2. BUFG for user_clk and sync_clk generation from tx_out_clk
//   3. MMCM/BUFG for init_clk and drp_clk from system clock
//   4. Two GT Common (QPLL) wrappers, one per quad
//   5. Synchronized reset generation
//
// Clock sharing architecture:
//   - Single IBUFDS_GTE2 buffers the reference clock for both quads
//   - tx_out_clk from the first Aurora core drives user_clk via BUFG
//   - Both Aurora cores share the same user_clk and sync_clk
//   - Each quad has its own GTHE2_COMMON with QPLL
//
// Target: xc7vx690tffg1927-2L
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module aurora_clock_module (
    //=========================================================================
    // External clock inputs
    //=========================================================================
    input  wire         gt_refclk_p,        // GT reference clock positive
    input  wire         gt_refclk_n,        // GT reference clock negative
    input  wire         init_clk_in,        // Board clock for init/DRP (e.g., 50MHz or 100MHz)

    //=========================================================================
    // TX output clock from Aurora cores
    //=========================================================================
    input  wire         tx_out_clk_ch0,     // TX output clock from Aurora channel 0

    //=========================================================================
    // QPLL reset inputs (from Aurora cores)
    //=========================================================================
    input  wire         qpll_reset_ch0,     // QPLL reset from Aurora channel 0
    input  wire         qpll_reset_ch1,     // QPLL reset from Aurora channel 1

    //=========================================================================
    // Reset input
    //=========================================================================
    input  wire         sys_rst,            // Active-high system reset

    //=========================================================================
    // Generated clock outputs
    //=========================================================================
    output wire         gt_refclk,          // Buffered GT reference clock
    output wire         user_clk,           // Aurora user clock (shared)
    output wire         sync_clk,           // Aurora sync clock (shared, same as user_clk)
    output wire         init_clk,           // Initialization clock
    output wire         drp_clk,            // DRP clock

    //=========================================================================
    // QPLL outputs for Aurora channel 0 (GTHQ0)
    //=========================================================================
    output wire         qpll0_outclk,
    output wire         qpll0_outrefclk,
    output wire         qpll0_lock,
    output wire         qpll0_refclklost,

    //=========================================================================
    // QPLL outputs for Aurora channel 1 (GTHQ1)
    //=========================================================================
    output wire         qpll1_outclk,
    output wire         qpll1_outrefclk,
    output wire         qpll1_lock,
    output wire         qpll1_refclklost,

    //=========================================================================
    // Synchronized reset outputs
    //=========================================================================
    output wire         reset_pb,           // Synchronized reset for Aurora cores
    output wire         pma_init            // PMA initialization signal
);

    //=========================================================================
    // Internal signals
    //=========================================================================
    wire        gt_refclk_buf;              // IBUFDS_GTE2 output
    wire        user_clk_buf;               // BUFG output for user_clk
    reg  [7:0]  pma_init_cnt = 8'd0;        // PMA init counter
    reg         pma_init_reg = 1'b1;         // PMA init register
    reg  [3:0]  reset_sync = 4'hF;          // Reset synchronizer

    //=========================================================================
    // GT Reference Clock Buffer (IBUFDS_GTE2)
    //
    // Buffers the differential reference clock for GT transceivers.
    // The output connects to both GTHE2_COMMON instances.
    //=========================================================================
    IBUFDS_GTE2 ibufds_gte2_inst (
        .O                          (gt_refclk_buf),
        .ODIV2                      (),
        .CEB                        (1'b0),
        .I                          (gt_refclk_p),
        .IB                         (gt_refclk_n)
    );

    assign gt_refclk = gt_refclk_buf;

    //=========================================================================
    // User Clock Generation (BUFG)
    //
    // tx_out_clk from the first Aurora core is buffered by BUFG to generate
    // user_clk. This clock is shared between both Aurora cores.
    // sync_clk is the same as user_clk for Aurora 64B66B.
    //=========================================================================
    BUFG bufg_user_clk_inst (
        .I                          (tx_out_clk_ch0),
        .O                          (user_clk_buf)
    );

    assign user_clk = user_clk_buf;
    assign sync_clk = user_clk_buf;     // sync_clk = user_clk for 64B66B

    //=========================================================================
    // Init Clock and DRP Clock
    //
    // The initialization clock and DRP clock come from the board system clock.
    // Using BUFG to buffer the init_clk_in.
    //=========================================================================
    BUFG bufg_init_clk_inst (
        .I                          (init_clk_in),
        .O                          (init_clk)
    );

    assign drp_clk = init_clk;          // DRP clock uses the same init clock

    //=========================================================================
    // GT Common (QPLL) for Channel 0 - GTHQ0
    //=========================================================================
    aurora_gt_common_wrapper gt_common_ch0 (
        .gt_refclk                  (gt_refclk_buf),
        .qpll_reset                 (qpll_reset_ch0),
        .qpll_outclk                (qpll0_outclk),
        .qpll_outrefclk             (qpll0_outrefclk),
        .qpll_lock                  (qpll0_lock),
        .qpll_refclklost            (qpll0_refclklost),
        .drp_clk                    (init_clk),
        .drp_addr                   (8'd0),
        .drp_di                     (16'd0),
        .drp_do                     (),
        .drp_en                     (1'b0),
        .drp_rdy                    (),
        .drp_we                     (1'b0)
    );

    //=========================================================================
    // GT Common (QPLL) for Channel 1 - GTHQ1
    //
    // Uses the same reference clock from the single IBUFDS_GTE2,
    // routed through the GT clock routing network to the adjacent quad.
    //=========================================================================
    aurora_gt_common_wrapper gt_common_ch1 (
        .gt_refclk                  (gt_refclk_buf),
        .qpll_reset                 (qpll_reset_ch1),
        .qpll_outclk                (qpll1_outclk),
        .qpll_outrefclk             (qpll1_outrefclk),
        .qpll_lock                  (qpll1_lock),
        .qpll_refclklost            (qpll1_refclklost),
        .drp_clk                    (init_clk),
        .drp_addr                   (8'd0),
        .drp_di                     (16'd0),
        .drp_do                     (),
        .drp_en                     (1'b0),
        .drp_rdy                    (),
        .drp_we                     (1'b0)
    );

    //=========================================================================
    // PMA Initialization
    //
    // pma_init must be asserted for a minimum period after power-up
    // to allow GT transceivers to initialize properly.
    //=========================================================================
    always @(posedge init_clk) begin
        if (sys_rst) begin
            pma_init_cnt <= 8'd0;
            pma_init_reg <= 1'b1;
        end else begin
            if (pma_init_cnt < 8'hFF) begin
                pma_init_cnt <= pma_init_cnt + 8'd1;
                pma_init_reg <= 1'b1;
            end else begin
                pma_init_reg <= 1'b0;
            end
        end
    end

    assign pma_init = pma_init_reg;

    //=========================================================================
    // Reset Synchronization
    //
    // Synchronize system reset to user_clk domain for Aurora core reset.
    //=========================================================================
    always @(posedge user_clk_buf or posedge sys_rst) begin
        if (sys_rst) begin
            reset_sync <= 4'hF;
        end else begin
            reset_sync <= {reset_sync[2:0], 1'b0};
        end
    end

    assign reset_pb = reset_sync[3];

endmodule
