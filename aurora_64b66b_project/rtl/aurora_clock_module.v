//////////////////////////////////////////////////////////////////////////////
// Module: aurora_clock_module
// Description: Clock management module for Aurora 64B66B.
//              Provides shared reference clock (IBUFDS_GTE2), generates
//              user_clk, sync_clk from tx_out_clk via MMCM, and produces
//              init_clk from system clock.
//              Two Aurora IPs on adjacent GT quads share this clock module.
//////////////////////////////////////////////////////////////////////////////

module aurora_clock_module (
    // External differential reference clock (156.25 MHz)
    input  wire  gt_refclk_p,
    input  wire  gt_refclk_n,
    // System clock (for init_clk generation)
    input  wire  sys_clk_p,
    input  wire  sys_clk_n,
    // From Aurora IP
    input  wire  tx_out_clk,
    // Outputs
    output wire  gt_refclk,         // Single-ended GT reference clock
    output wire  user_clk,          // User clock for Aurora data path
    output wire  sync_clk,          // Sync clock (half-rate of user_clk)
    output wire  init_clk,          // 50 MHz init clock
    output wire  drp_clk,           // 50 MHz DRP clock
    output wire  mmcm_not_locked    // MMCM lock status (active high = not locked)
);

    //------------------------------------------------------------------------
    // GT Reference Clock: IBUFDS_GTE2
    //------------------------------------------------------------------------
    wire gt_refclk_buf;

    IBUFDS_GTE2 u_ibufds_gte2 (
        .I     (gt_refclk_p),
        .IB    (gt_refclk_n),
        .O     (gt_refclk_buf),
        .ODIV2 (),
        .CEB   (1'b0)
    );

    assign gt_refclk = gt_refclk_buf;

    //------------------------------------------------------------------------
    // System Clock: IBUFGDS for init/drp clock source
    //------------------------------------------------------------------------
    wire sys_clk_ibufg;

    IBUFGDS u_ibufgds_sys (
        .I  (sys_clk_p),
        .IB (sys_clk_n),
        .O  (sys_clk_ibufg)
    );

    //------------------------------------------------------------------------
    // User Clock: BUFG on tx_out_clk
    // Aurora 64B66B at 10 Gbps with 64B66B encoding:
    // user_clk = line_rate / 66 * 64 / data_width(256) * 4(lanes)
    // ≈ 156.25 MHz (approx, depends on exact configuration)
    //------------------------------------------------------------------------
    wire user_clk_bufg;

    BUFG u_bufg_user_clk (
        .I (tx_out_clk),
        .O (user_clk_bufg)
    );

    assign user_clk = user_clk_bufg;

    //------------------------------------------------------------------------
    // MMCM: Generate sync_clk from user_clk
    // Also generate init_clk (50 MHz) from system clock
    //------------------------------------------------------------------------
    wire mmcm_locked;
    wire sync_clk_mmcm;
    wire init_clk_mmcm;
    wire mmcm_clkfb;

    MMCME2_ADV #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKOUT4_CASCADE    ("FALSE"),
        .COMPENSATION       ("ZHOLD"),
        .STARTUP_WAIT       ("FALSE"),
        .DIVCLK_DIVIDE      (1),
        .CLKFBOUT_MULT_F    (10.000),    // VCO = sys_clk * 10 = 500 MHz (if sys_clk=50MHz)
        .CLKFBOUT_PHASE     (0.000),
        .CLKOUT0_DIVIDE_F   (10.000),    // sync_clk = 50 MHz
        .CLKOUT0_PHASE      (0.000),
        .CLKOUT0_DUTY_CYCLE (0.500),
        .CLKOUT1_DIVIDE     (10),        // init_clk = 50 MHz
        .CLKOUT1_PHASE      (0.000),
        .CLKOUT1_DUTY_CYCLE (0.500),
        .CLKIN1_PERIOD       (20.000),   // 50 MHz system clock
        .REF_JITTER1         (0.010)
    ) u_mmcm (
        .CLKFBOUT    (mmcm_clkfb),
        .CLKFBOUTB   (),
        .CLKOUT0     (sync_clk_mmcm),
        .CLKOUT0B    (),
        .CLKOUT1     (init_clk_mmcm),
        .CLKOUT1B    (),
        .CLKOUT2     (),
        .CLKOUT2B    (),
        .CLKOUT3     (),
        .CLKOUT3B    (),
        .CLKOUT4     (),
        .CLKOUT5     (),
        .CLKOUT6     (),
        .CLKFBIN     (mmcm_clkfb),
        .CLKIN1      (sys_clk_ibufg),
        .CLKIN2      (1'b0),
        .CLKINSEL    (1'b1),
        .DADDR       (7'd0),
        .DCLK        (1'b0),
        .DEN         (1'b0),
        .DI          (16'd0),
        .DO          (),
        .DRDY        (),
        .DWE         (1'b0),
        .LOCKED      (mmcm_locked),
        .PSCLK       (1'b0),
        .PSEN        (1'b0),
        .PSINCDEC    (1'b0),
        .PSDONE      (),
        .PWRDWN      (1'b0),
        .RST         (1'b0)
    );

    BUFG u_bufg_sync_clk (
        .I (sync_clk_mmcm),
        .O (sync_clk)
    );

    BUFG u_bufg_init_clk (
        .I (init_clk_mmcm),
        .O (init_clk)
    );

    assign drp_clk        = init_clk;
    assign mmcm_not_locked = ~mmcm_locked;

endmodule
