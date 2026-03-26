//////////////////////////////////////////////////////////////////////////////
// Module: aurora_top
// Description: Top-level module for dual Aurora 64B66B channel design.
//              Two Aurora IP cores on adjacent GT quads (Quad 0 and Quad 1)
//              sharing a common reference clock. Each channel includes
//              data generation, frame assembly, TX/RX, and data verification.
//              Target: xc7vx690tffg1927-2L
//              Aurora IP: Aurora 64B66B (11.2) - Framing mode
//////////////////////////////////////////////////////////////////////////////

module aurora_top (
    // System clock (50 MHz differential)
    input  wire        sys_clk_p,
    input  wire        sys_clk_n,
    // GT Reference clock (156.25 MHz differential)
    input  wire        gt_refclk_p,
    input  wire        gt_refclk_n,
    // System reset (active low)
    input  wire        sys_rst_n,
    // Channel 0 GT Serial (Quad 0)
    input  wire [3:0]  ch0_rxp,
    input  wire [3:0]  ch0_rxn,
    output wire [3:0]  ch0_txp,
    output wire [3:0]  ch0_txn,
    // Channel 1 GT Serial (Quad 1)
    input  wire [3:0]  ch1_rxp,
    input  wire [3:0]  ch1_rxn,
    output wire [3:0]  ch1_txp,
    output wire [3:0]  ch1_txn,
    // Status outputs
    output wire [1:0]  channel_up,
    output wire [1:0]  error_flag
);

    //------------------------------------------------------------------------
    // Parameters
    //------------------------------------------------------------------------
    localparam FRAME_PAYLOAD_BEATS = 32;

    //------------------------------------------------------------------------
    // Internal signals
    //------------------------------------------------------------------------
    wire        gt_refclk;
    wire        user_clk;
    wire        sync_clk;
    wire        init_clk;
    wire        drp_clk;
    wire        mmcm_not_locked;
    wire        reset_pb;
    wire        pma_init;

    // Channel 0 signals
    wire        ch0_tx_out_clk;
    wire        ch0_channel_up;
    wire [3:0]  ch0_lane_up;
    wire        ch0_hard_err;
    wire        ch0_soft_err;
    wire        ch0_gt_pll_lock;
    wire        ch0_link_reset_out;
    wire        ch0_sys_reset_out;
    wire        ch0_error_flag;
    wire [31:0] ch0_error_count;
    wire [31:0] ch0_frame_count;
    wire [31:0] ch0_beat_count;

    // Channel 1 signals
    wire        ch1_tx_out_clk;
    wire        ch1_channel_up;
    wire [3:0]  ch1_lane_up;
    wire        ch1_hard_err;
    wire        ch1_soft_err;
    wire        ch1_gt_pll_lock;
    wire        ch1_link_reset_out;
    wire        ch1_sys_reset_out;
    wire        ch1_error_flag;
    wire [31:0] ch1_error_count;
    wire [31:0] ch1_frame_count;
    wire [31:0] ch1_beat_count;

    // QPLL signals - Quad 0
    wire        q0_qpllclk;
    wire        q0_qpllrefclk;
    wire        q0_qplllock;
    wire        q0_qpllrefclklost;
    wire        q0_qpllreset;

    // QPLL signals - Quad 1
    wire        q1_qpllclk;
    wire        q1_qpllrefclk;
    wire        q1_qplllock;
    wire        q1_qpllrefclklost;
    wire        q1_qpllreset;

    //------------------------------------------------------------------------
    // Reset generation
    //------------------------------------------------------------------------
    reg [7:0] rst_cnt;
    reg       rst_sync_r1, rst_sync_r2;
    reg       pma_init_r;

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

    assign pma_init = pma_init_r;

    //------------------------------------------------------------------------
    // Protocol reset (reset_pb) — generated in user_clk domain
    //------------------------------------------------------------------------
    // Follows the Xilinx Aurora example-design reset pattern:
    //  • Held HIGH while pma_init is active (reset bridge synchroniser
    //    provides clean deassertion on a user_clk edge).
    //  • After user_clk starts, held HIGH for 256 user_clk cycles so the
    //    Aurora core sees a clean, long reset after GT initialisation.
    //  • Re-triggered whenever either channel asserts link_reset_out,
    //    providing the retry mechanism the Aurora core needs when the
    //    initial handshake fails (e.g. CDR not yet locked on first try).
    //------------------------------------------------------------------------

    // Reset bridge: synchronise pma_init_r deassertion to user_clk domain.
    // Assertion is asynchronous (immediate); deassertion is synchronous.
    (* ASYNC_REG = "true" *) reg pma_init_user_r1;
    (* ASYNC_REG = "true" *) reg pma_init_user_r2;

    always @(posedge user_clk or posedge pma_init_r) begin
        if (pma_init_r) begin
            pma_init_user_r1 <= 1'b1;
            pma_init_user_r2 <= 1'b1;
        end else begin
            pma_init_user_r1 <= 1'b0;
            pma_init_user_r2 <= pma_init_user_r1;
        end
    end

    reg [7:0] pb_reset_cnt;
    reg       reset_pb_int;
    reg       pb_hold_done;

    always @(posedge user_clk or posedge pma_init_user_r2) begin
        if (pma_init_user_r2) begin
            pb_reset_cnt <= 8'd0;
            reset_pb_int <= 1'b1;
            pb_hold_done <= 1'b0;
        end else if (!pb_hold_done) begin
            // Hold phase: count 256 user_clk cycles with reset_pb asserted
            if (pb_reset_cnt < 8'd255) begin
                pb_reset_cnt <= pb_reset_cnt + 8'd1;
                reset_pb_int <= 1'b1;
            end else begin
                reset_pb_int <= 1'b0;
                pb_hold_done <= 1'b1;
            end
        end else if (ch0_link_reset_out || ch1_link_reset_out) begin
            // Link-reset feedback: Aurora IP could not establish the link;
            // re-assert protocol reset and try again.
            pb_reset_cnt <= 8'd0;
            reset_pb_int <= 1'b1;
            pb_hold_done <= 1'b0;
        end else begin
            reset_pb_int <= 1'b0;
        end
    end

    assign reset_pb = reset_pb_int;

    //------------------------------------------------------------------------
    // Status outputs
    //------------------------------------------------------------------------
    assign channel_up  = {ch1_channel_up, ch0_channel_up};
    assign error_flag  = {ch1_error_flag, ch0_error_flag};

    //------------------------------------------------------------------------
    // Clock Module (shared between both channels)
    //------------------------------------------------------------------------
    aurora_clock_module u_clock_module (
        .gt_refclk_p    (gt_refclk_p),
        .gt_refclk_n    (gt_refclk_n),
        .sys_clk_p      (sys_clk_p),
        .sys_clk_n      (sys_clk_n),
        .tx_out_clk     (ch0_tx_out_clk),
        .gt_pll_lock    (ch0_gt_pll_lock),
        .gt_refclk      (gt_refclk),
        .user_clk       (user_clk),
        .sync_clk       (sync_clk),
        .init_clk       (init_clk),
        .drp_clk        (drp_clk),
        .mmcm_not_locked(mmcm_not_locked)
    );

    //------------------------------------------------------------------------
    // Channel 0 (GT Quad 0)
    //------------------------------------------------------------------------
    aurora_channel #(
        .CHANNEL_ID          (0),
        .FRAME_PAYLOAD_BEATS (FRAME_PAYLOAD_BEATS)
    ) u_channel_0 (
        .user_clk                   (user_clk),
        .sync_clk                   (sync_clk),
        .reset_pb                   (reset_pb),
        .init_clk                   (init_clk),
        .drp_clk                    (drp_clk),
        .pma_init                   (pma_init),
        .mmcm_not_locked            (mmcm_not_locked),
        .rxp                        (ch0_rxp),
        .rxn                        (ch0_rxn),
        .txp                        (ch0_txp),
        .txn                        (ch0_txn),
        .refclk1_in                 (gt_refclk),
        .gt_qpllclk_quad_in         (q0_qpllclk),
        .gt_qpllrefclk_quad_in      (q0_qpllrefclk),
        .gt_to_common_qpllreset_out (q0_qpllreset),
        .gt_qplllock_in             (q0_qplllock),
        .gt_qpllrefclklost_in       (q0_qpllrefclklost),
        .channel_up                 (ch0_channel_up),
        .lane_up                    (ch0_lane_up),
        .hard_err                   (ch0_hard_err),
        .soft_err                   (ch0_soft_err),
        .tx_out_clk                 (ch0_tx_out_clk),
        .gt_pll_lock                (ch0_gt_pll_lock),
        .link_reset_out             (ch0_link_reset_out),
        .sys_reset_out              (ch0_sys_reset_out),
        .error_flag                 (ch0_error_flag),
        .error_count                (ch0_error_count),
        .frame_count                (ch0_frame_count),
        .beat_count                 (ch0_beat_count)
    );

    //------------------------------------------------------------------------
    // Channel 1 (GT Quad 1)
    //------------------------------------------------------------------------
    aurora_channel #(
        .CHANNEL_ID          (1),
        .FRAME_PAYLOAD_BEATS (FRAME_PAYLOAD_BEATS)
    ) u_channel_1 (
        .user_clk                   (user_clk),
        .sync_clk                   (sync_clk),
        .reset_pb                   (reset_pb),
        .init_clk                   (init_clk),
        .drp_clk                    (drp_clk),
        .pma_init                   (pma_init),
        .mmcm_not_locked            (mmcm_not_locked),
        .rxp                        (ch1_rxp),
        .rxn                        (ch1_rxn),
        .txp                        (ch1_txp),
        .txn                        (ch1_txn),
        .refclk1_in                 (gt_refclk),
        .gt_qpllclk_quad_in         (q1_qpllclk),
        .gt_qpllrefclk_quad_in      (q1_qpllrefclk),
        .gt_to_common_qpllreset_out (q1_qpllreset),
        .gt_qplllock_in             (q1_qplllock),
        .gt_qpllrefclklost_in       (q1_qpllrefclklost),
        .channel_up                 (ch1_channel_up),
        .lane_up                    (ch1_lane_up),
        .hard_err                   (ch1_hard_err),
        .soft_err                   (ch1_soft_err),
        .tx_out_clk                 (ch1_tx_out_clk),
        .gt_pll_lock                (ch1_gt_pll_lock),
        .link_reset_out             (ch1_link_reset_out),
        .sys_reset_out              (ch1_sys_reset_out),
        .error_flag                 (ch1_error_flag),
        .error_count                (ch1_error_count),
        .frame_count                (ch1_frame_count),
        .beat_count                 (ch1_beat_count)
    );

    //------------------------------------------------------------------------
    // GTHE2_COMMON for Quad 0
    // Parameters matched to Xilinx-generated gt_common_wrapper for
    // Aurora 64B66B on 7-series GTH, 10 Gbps, 156.25 MHz refclk.
    //------------------------------------------------------------------------
    GTHE2_COMMON #(
        .SIM_RESET_SPEEDUP   ("TRUE"),
        .SIM_QPLLREFCLK_SEL  (3'b001),
        .SIM_VERSION         ("2.0"),
        .BIAS_CFG            (64'h0000040000001050),
        .COMMON_CFG          (32'h0000001C),
        .QPLL_CFG            (27'h04801C7),
        .QPLL_CLKOUT_CFG     (4'b1111),
        .QPLL_COARSE_FREQ_OVRD       (6'b010000),
        .QPLL_COARSE_FREQ_OVRD_EN    (1'b0),
        .QPLL_CP              (10'b0000011111),
        .QPLL_CP_MONITOR_EN   (1'b0),
        .QPLL_DMONITOR_SEL    (1'b0),
        .QPLL_FBDIV           (10'b0011100000),  // FBDIV=64 → VCO 10 GHz (GTH encoding)
        .QPLL_FBDIV_MONITOR_EN (1'b0),
        .QPLL_FBDIV_RATIO     (1'b1),            // 1'b1 for FBDIV != 66
        .QPLL_INIT_CFG        (24'h000006),
        .QPLL_LOCK_CFG        (16'h05E8),
        .QPLL_LPF             (4'b1111),
        .QPLL_REFCLK_DIV      (1),
        .RSVD_ATTR0           (16'h0000),
        .RSVD_ATTR1           (16'h0000),
        .QPLL_RP_COMP         (1'b0),
        .QPLL_VTRL_RESET      (2'b00),
        .RCAL_CFG             (2'b00)
    ) u_gthe2_common_q0 (
        .QPLLOUTCLK          (q0_qpllclk),
        .QPLLOUTREFCLK       (q0_qpllrefclk),
        .QPLLLOCK            (q0_qplllock),
        .QPLLLOCKDETCLK      (init_clk),
        .QPLLLOCKEN          (1'b1),
        .QPLLOUTRESET        (1'b0),
        .QPLLPD              (1'b0),
        .QPLLREFCLKLOST      (q0_qpllrefclklost),
        .QPLLREFCLKSEL       (3'b001),
        .QPLLRESET           (q0_qpllreset),
        .QPLLRSVD1           (16'b0),
        .QPLLRSVD2           (5'b11111),
        .QPLLDMONITOR        (),
        .QPLLFBCLKLOST       (),
        .REFCLKOUTMONITOR    (),
        .PMARSVDOUT          (),
        // Bandgap
        .BGBYPASSB           (1'b1),
        .BGMONITORENB        (1'b1),
        .BGPDB               (1'b1),
        .BGRCALOVRD          (5'b11111),
        .BGRCALOVRDENB       (1'b1),
        .RCALENB             (1'b1),
        // DRP (tied off — not used)
        .DRPADDR             (8'd0),
        .DRPCLK              (drp_clk),
        .DRPDI               (16'd0),
        .DRPDO               (),
        .DRPEN               (1'b0),
        .DRPRDY              (),
        .DRPWE               (1'b0),
        // Reference clocks
        .GTGREFCLK           (1'b0),
        .GTNORTHREFCLK0      (1'b0),
        .GTNORTHREFCLK1      (1'b0),
        .GTREFCLK0           (gt_refclk),
        .GTREFCLK1           (1'b0),
        .GTSOUTHREFCLK0      (1'b0),
        .GTSOUTHREFCLK1      (1'b0),
        .PMARSVD             (8'b0)
    );

    //------------------------------------------------------------------------
    // GTHE2_COMMON for Quad 1
    // Parameters matched to Xilinx-generated gt_common_wrapper for
    // Aurora 64B66B on 7-series GTH, 10 Gbps, 156.25 MHz refclk.
    //------------------------------------------------------------------------
    GTHE2_COMMON #(
        .SIM_RESET_SPEEDUP   ("TRUE"),
        .SIM_QPLLREFCLK_SEL  (3'b001),
        .SIM_VERSION         ("2.0"),
        .BIAS_CFG            (64'h0000040000001050),
        .COMMON_CFG          (32'h0000001C),
        .QPLL_CFG            (27'h04801C7),
        .QPLL_CLKOUT_CFG     (4'b1111),
        .QPLL_COARSE_FREQ_OVRD       (6'b010000),
        .QPLL_COARSE_FREQ_OVRD_EN    (1'b0),
        .QPLL_CP              (10'b0000011111),
        .QPLL_CP_MONITOR_EN   (1'b0),
        .QPLL_DMONITOR_SEL    (1'b0),
        .QPLL_FBDIV           (10'b0011100000),  // FBDIV=64 → VCO 10 GHz (GTH encoding)
        .QPLL_FBDIV_MONITOR_EN (1'b0),
        .QPLL_FBDIV_RATIO     (1'b1),            // 1'b1 for FBDIV != 66
        .QPLL_INIT_CFG        (24'h000006),
        .QPLL_LOCK_CFG        (16'h05E8),
        .QPLL_LPF             (4'b1111),
        .QPLL_REFCLK_DIV      (1),
        .RSVD_ATTR0           (16'h0000),
        .RSVD_ATTR1           (16'h0000),
        .QPLL_RP_COMP         (1'b0),
        .QPLL_VTRL_RESET      (2'b00),
        .RCAL_CFG             (2'b00)
    ) u_gthe2_common_q1 (
        .QPLLOUTCLK          (q1_qpllclk),
        .QPLLOUTREFCLK       (q1_qpllrefclk),
        .QPLLLOCK            (q1_qplllock),
        .QPLLLOCKDETCLK      (init_clk),
        .QPLLLOCKEN          (1'b1),
        .QPLLOUTRESET        (1'b0),
        .QPLLPD              (1'b0),
        .QPLLREFCLKLOST      (q1_qpllrefclklost),
        .QPLLREFCLKSEL       (3'b001),
        .QPLLRESET           (q1_qpllreset),
        .QPLLRSVD1           (16'b0),
        .QPLLRSVD2           (5'b11111),
        .QPLLDMONITOR        (),
        .QPLLFBCLKLOST       (),
        .REFCLKOUTMONITOR    (),
        .PMARSVDOUT          (),
        // Bandgap
        .BGBYPASSB           (1'b1),
        .BGMONITORENB        (1'b1),
        .BGPDB               (1'b1),
        .BGRCALOVRD          (5'b11111),
        .BGRCALOVRDENB       (1'b1),
        .RCALENB             (1'b1),
        // DRP (tied off — not used)
        .DRPADDR             (8'd0),
        .DRPCLK              (drp_clk),
        .DRPDI               (16'd0),
        .DRPDO               (),
        .DRPEN               (1'b0),
        .DRPRDY              (),
        .DRPWE               (1'b0),
        // Reference clocks
        .GTGREFCLK           (1'b0),
        .GTNORTHREFCLK0      (1'b0),
        .GTNORTHREFCLK1      (1'b0),
        .GTREFCLK0           (gt_refclk),
        .GTREFCLK1           (1'b0),
        .GTSOUTHREFCLK0      (1'b0),
        .GTSOUTHREFCLK1      (1'b0),
        .PMARSVD             (8'b0)
    );

endmodule
