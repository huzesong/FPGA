//////////////////////////////////////////////////////////////////////////////
// Module: aurora_top_tb
// Description: Testbench for the dual Aurora 64B66B streaming mode design.
//              Only instantiates aurora_top. Provides differential clocks,
//              reset, and serial loopback (TX→RX) for Vivado simulation
//              with the real Aurora IP.
//////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module aurora_top_tb;

    //------------------------------------------------------------------------
    // Parameters
    //------------------------------------------------------------------------
    localparam GT_REFCLK_PERIOD = 6.4;     // 156.25 MHz
    localparam SYS_CLK_PERIOD  = 20.0;     // 50 MHz
    localparam RST_HOLD_TIME   = 500;      // Reset hold time (ns)
    localparam SIM_TIME        = 500000;   // Total simulation time (ns)

    //------------------------------------------------------------------------
    // Clock generation
    //------------------------------------------------------------------------
    reg gt_refclk_p;
    reg sys_clk_p;

    wire gt_refclk_n;
    wire sys_clk_n;

    assign gt_refclk_n = ~gt_refclk_p;
    assign sys_clk_n   = ~sys_clk_p;

    // 156.25 MHz GT reference clock
    initial gt_refclk_p = 1'b0;
    always #(GT_REFCLK_PERIOD / 2.0) gt_refclk_p = ~gt_refclk_p;

    // 50 MHz system clock
    initial sys_clk_p = 1'b0;
    always #(SYS_CLK_PERIOD / 2.0) sys_clk_p = ~sys_clk_p;

    //------------------------------------------------------------------------
    // Reset
    //------------------------------------------------------------------------
    reg sys_rst_n;

    initial begin
        sys_rst_n = 1'b0;
        #RST_HOLD_TIME;
        sys_rst_n = 1'b1;
    end

    //------------------------------------------------------------------------
    // DUT I/O
    //------------------------------------------------------------------------
    // Channel 0 serial
    wire [3:0] ch0_txp, ch0_txn;
    wire [3:0] ch0_rxp, ch0_rxn;
    // Channel 1 serial
    wire [3:0] ch1_txp, ch1_txn;
    wire [3:0] ch1_rxp, ch1_rxn;
    // Status
    wire [1:0] channel_up;
    wire [1:0] error_flag;

    //------------------------------------------------------------------------
    // Serial loopback: TX → RX for each channel
    //------------------------------------------------------------------------
    assign ch0_rxp = ch0_txp;
    assign ch0_rxn = ch0_txn;
    assign ch1_rxp = ch1_txp;
    assign ch1_rxn = ch1_txn;

    //------------------------------------------------------------------------
    // DUT: aurora_top (streaming mode)
    //------------------------------------------------------------------------
    aurora_top u_aurora_top (
        .sys_clk_p   (sys_clk_p),
        .sys_clk_n   (sys_clk_n),
        .gt_refclk_p (gt_refclk_p),
        .gt_refclk_n (gt_refclk_n),
        .sys_rst_n   (sys_rst_n),
        .ch0_rxp     (ch0_rxp),
        .ch0_rxn     (ch0_rxn),
        .ch0_txp     (ch0_txp),
        .ch0_txn     (ch0_txn),
        .ch1_rxp     (ch1_rxp),
        .ch1_rxn     (ch1_rxn),
        .ch1_txp     (ch1_txp),
        .ch1_txn     (ch1_txn),
        .channel_up  (channel_up),
        .error_flag  (error_flag)
    );

    //------------------------------------------------------------------------
    // Monitor
    //------------------------------------------------------------------------
    initial begin
        $display("============================================");
        $display("  Aurora 64B66B Dual Channel Testbench");
        $display("  Streaming Mode — Serial Loopback");
        $display("============================================");
    end

    always @(posedge channel_up[0])
        $display("[%0t] Channel 0: channel_up ASSERTED", $time);
    always @(negedge channel_up[0])
        $display("[%0t] Channel 0: channel_up DEASSERTED", $time);

    always @(posedge channel_up[1])
        $display("[%0t] Channel 1: channel_up ASSERTED", $time);
    always @(negedge channel_up[1])
        $display("[%0t] Channel 1: channel_up DEASSERTED", $time);

    always @(posedge error_flag[0])
        $display("[%0t] ERROR: Channel 0 data mismatch!", $time);
    always @(posedge error_flag[1])
        $display("[%0t] ERROR: Channel 1 data mismatch!", $time);

    //------------------------------------------------------------------------
    // Periodic status (every 50 us)
    //------------------------------------------------------------------------
    initial begin
        forever begin
            #50000;
            $display("[%0t] channel_up=%b  error_flag=%b",
                     $time, channel_up, error_flag);
        end
    end

    //------------------------------------------------------------------------
    // Link-up tracking
    //------------------------------------------------------------------------
    reg ch0_linked, ch1_linked;

    initial begin
        ch0_linked = 1'b0;
        ch1_linked = 1'b0;
    end

    always @(posedge channel_up[0]) ch0_linked = 1'b1;
    always @(posedge channel_up[1]) ch1_linked = 1'b1;

    //------------------------------------------------------------------------
    // Simulation end
    //------------------------------------------------------------------------
    initial begin
        #SIM_TIME;
        $display("");
        $display("============================================");
        $display("  Simulation Complete (%0d ns)", SIM_TIME);
        $display("  channel_up = %b  (linked: ch0=%b ch1=%b)",
                 channel_up, ch0_linked, ch1_linked);
        $display("  error_flag = %b", error_flag);
        if (ch0_linked && ch1_linked && channel_up == 2'b11 && error_flag == 2'b00)
            $display("  RESULT: *** PASS ***");
        else
            $display("  RESULT: *** FAIL ***");
        $display("============================================");
        $finish;
    end

endmodule
