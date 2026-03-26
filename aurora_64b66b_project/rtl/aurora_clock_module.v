//////////////////////////////////////////////////////////////////////////////
// Module: aurora_clock_module
// Description: Clock management module for Aurora 64B66B.
//              Provides shared reference clock (IBUFDS_GTE2), generates
//              user_clk and sync_clk from tx_out_clk via MMCM, and provides
//              init_clk/drp_clk from the system clock.
//              Two Aurora IPs on adjacent GT quads share this clock module.
//
//              Matches the Xilinx-generated aurora_64b66b_0_CLOCK_MODULE for
//              7-series GTH, 4-lane, 10 Gbps line rate:
//                tx_out_clk = 312.5 MHz (from GT TXOUTCLK)
//                MMCM VCO   = 312.5 × 6/3 = 625 MHz
//                user_clk   = 625 / 4 = 156.25 MHz (CLKOUT0)
//                sync_clk   = 625 / 2 = 312.5 MHz  (CLKOUT1)
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
    input  wire  gt_pll_lock,     // QPLL lock status (from Aurora gt_pll_lock)
    // Outputs
    output wire  gt_refclk,         // Single-ended GT reference clock
    output wire  user_clk,          // User clock for Aurora data path (156.25 MHz)
    output wire  sync_clk,          // Sync clock for Aurora (312.5 MHz)
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
    // User Clock and Sync Clock: MMCM on tx_out_clk
    // Matches Xilinx-generated clock module parameters for 10 Gbps Aurora:
    //   tx_out_clk = 312.5 MHz → MMCM → user_clk=156.25 MHz, sync_clk=312.5 MHz
    //------------------------------------------------------------------------
    wire clk_in_i;      // tx_out_clk after BUFG
    wire user_clk_i;    // MMCM CLKOUT0 (before BUFG)
    wire sync_clk_i;    // MMCM CLKOUT1 (before BUFG)
    wire clkfbout;      // MMCM feedback
    wire locked_i;      // MMCM locked status

    // BUFG on tx_out_clk input to MMCM
    BUFG u_bufg_txout (
        .I (tx_out_clk),
        .O (clk_in_i)
    );

    MMCME2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKOUT4_CASCADE      ("FALSE"),
        .COMPENSATION         ("ZHOLD"),
        .STARTUP_WAIT         ("FALSE"),
        .DIVCLK_DIVIDE        (3),
        .CLKFBOUT_MULT_F      (6),
        .CLKFBOUT_PHASE       (0.000),
        .CLKFBOUT_USE_FINE_PS ("FALSE"),
        .CLKOUT0_DIVIDE_F     (4),           // user_clk = VCO/4 = 156.25 MHz
        .CLKOUT0_PHASE        (0.000),
        .CLKOUT0_DUTY_CYCLE   (0.500),
        .CLKOUT0_USE_FINE_PS  ("FALSE"),
        .CLKIN1_PERIOD        (3.200),       // 312.5 MHz
        .CLKOUT1_DIVIDE       (2),           // sync_clk = VCO/2 = 312.5 MHz
        .CLKOUT1_PHASE        (0.000),
        .CLKOUT1_DUTY_CYCLE   (0.500),
        .CLKOUT1_USE_FINE_PS  ("FALSE"),
        .REF_JITTER1          (0.010)
    ) u_mmcm (
        // Output clocks
        .CLKFBOUT     (clkfbout),
        .CLKFBOUTB    (),
        .CLKOUT0      (user_clk_i),
        .CLKOUT0B     (),
        .CLKOUT1      (sync_clk_i),
        .CLKOUT1B     (),
        .CLKOUT2      (),
        .CLKOUT2B     (),
        .CLKOUT3      (),
        .CLKOUT3B     (),
        .CLKOUT4      (),
        .CLKOUT5      (),
        .CLKOUT6      (),
        // Input clock control
        .CLKFBIN      (clkfbout),
        .CLKIN1       (clk_in_i),
        .CLKIN2       (1'b0),
        .CLKINSEL     (1'b1),
        // Ports for dynamic reconfiguration
        .DADDR        (7'h0),
        .DCLK         (1'b0),
        .DEN          (1'b0),
        .DI           (16'h0),
        .DO           (),
        .DRDY         (),
        .DWE          (1'b0),
        // Ports for dynamic phase shift
        .PSCLK        (1'b0),
        .PSEN         (1'b0),
        .PSINCDEC     (1'b0),
        .PSDONE       (),
        // Other control and status signals
        .LOCKED       (locked_i),
        .CLKINSTOPPED (),
        .CLKFBSTOPPED (),
        .PWRDWN       (1'b0),
        .RST          (~gt_pll_lock)          // Hold MMCM in reset until QPLL locks
    );

    // BUFGs on MMCM outputs
    BUFG u_bufg_user_clk (
        .I (user_clk_i),
        .O (user_clk)
    );

    BUFG u_bufg_sync_clk (
        .I (sync_clk_i),
        .O (sync_clk)
    );

    assign mmcm_not_locked = ~locked_i;       // 1 = not locked (Aurora convention)

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

    assign drp_clk = init_clk;

endmodule
