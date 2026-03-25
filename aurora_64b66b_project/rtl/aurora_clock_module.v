//////////////////////////////////////////////////////////////////////////////
// Module: aurora_clock_module
// Description: Clock management module for Aurora 64B66B.
//              Provides shared reference clock (IBUFDS_GTE2), generates
//              user_clk and sync_clk from tx_out_clk via BUFG, and provides
//              init_clk/drp_clk from the system clock.
//              Two Aurora IPs on adjacent GT quads share this clock module.
//////////////////////////////////////////////////////////////////////////////

module aurora_clock_module (
    // External differential reference clock (156.25 MHz)
    input  wire  gt_refclk_p,
    input  wire  gt_refclk_n,
    // System clock (50 MHz differential, for init_clk/drp_clk generation)
    input  wire  sys_clk_p,
    input  wire  sys_clk_n,
    // From Aurora IP
    input  wire  tx_out_clk,
    // Outputs
    output wire  gt_refclk,         // Single-ended GT reference clock
    output wire  user_clk,          // User clock for Aurora data path
    output wire  sync_clk,          // Sync clock (same as user_clk for 64B66B)
    output wire  init_clk,          // 50 MHz init clock
    output wire  drp_clk,           // 50 MHz DRP clock
    output wire  mmcm_not_locked    // MMCM lock status (active high = not locked)
);

    //------------------------------------------------------------------------
    // GT Reference Clock: IBUFDS_GTE2
    //------------------------------------------------------------------------
    IBUFDS_GTE2 u_ibufds_gte2 (
        .I     (gt_refclk_p),
        .IB    (gt_refclk_n),
        .O     (gt_refclk),
        .ODIV2 (),
        .CEB   (1'b0)
    );

    //------------------------------------------------------------------------
    // User Clock and Sync Clock: BUFG on tx_out_clk
    // For Aurora 64B66B, sync_clk must be the same as user_clk.
    //------------------------------------------------------------------------
    BUFG u_bufg_user_clk (
        .I (tx_out_clk),
        .O (user_clk)
    );

    assign sync_clk = user_clk;

    //------------------------------------------------------------------------
    // Init Clock / DRP Clock: from system clock via IBUFGDS + BUFG
    // No MMCM needed — sys_clk is already 50 MHz.
    //------------------------------------------------------------------------
    wire sys_clk_ibufg;

    IBUFGDS u_ibufgds_sys (
        .I  (sys_clk_p),
        .IB (sys_clk_n),
        .O  (sys_clk_ibufg)
    );

    BUFG u_bufg_init_clk (
        .I (sys_clk_ibufg),
        .O (init_clk)
    );

    assign drp_clk        = init_clk;
    assign mmcm_not_locked = 1'b0;   // No MMCM, always "locked"

endmodule
