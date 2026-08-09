// SPDX-License-Identifier: BSD-2-Clause-Views
/*
 * Copyright (c) 2019-2023 The Regents of the University of California
 */

// Language: Verilog 2001
/*
 * Modified by Le Sun, 2026 for the FPGA AES-GCM / experimental MACsec prototype.
 * Modifications Copyright (c) 2026 Le Sun.
 * Changes: MACsec TX/RX inline protect datapath integration (wrappers, tag
 *           append/strip, AES-GCM HLS IP wiring, PN/IV/AAD assembly).
 * See patches/corundum/fpga_k35_macsec.patch for the exact diff.
 */

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * FPGA top-level module
 */
module fpga #
(
      // FW and board IDs
    parameter FPGA_ID = 32'h3823093,
    parameter FW_ID = 32'h00000000,
    parameter FW_VER = 32'h00_00_01_00,
    parameter BOARD_ID = 32'h1ce4_0003,
    parameter BOARD_VER = 32'h01_00_00_00,
    parameter BUILD_DATE = 32'd602976000,
    parameter GIT_HASH = 32'hdce357bf,
    parameter RELEASE_INFO = 32'h00000000,


    // Board configuration
    parameter TDMA_BER_ENABLE = 0,

    // Structural configuration
    parameter IF_COUNT = 1,
    parameter PORTS_PER_IF = 1,
    parameter SCHED_PER_IF = PORTS_PER_IF,
    parameter PORT_MASK = 0,
    parameter SFP_COUNT_125US = 125000/6.4,

    // Clock configuration
    parameter CLK_PERIOD_NS_NUM = 4,
    parameter CLK_PERIOD_NS_DENOM = 1,

    // PTP configuration
    parameter PTP_CLOCK_PIPELINE = 0,
    parameter PTP_CLOCK_CDC_PIPELINE = 0,
    parameter PTP_PORT_CDC_PIPELINE = 0,
    parameter PTP_PEROUT_ENABLE = 1,
    parameter PTP_PEROUT_COUNT = 1,

    // Queue manager configuration
    parameter EVENT_QUEUE_OP_TABLE_SIZE = 32,
    parameter TX_QUEUE_OP_TABLE_SIZE = 32,
    parameter RX_QUEUE_OP_TABLE_SIZE = 32,
    parameter CQ_OP_TABLE_SIZE = 32,
    parameter EQN_WIDTH = 5,
    parameter TX_QUEUE_INDEX_WIDTH = 11,
    parameter RX_QUEUE_INDEX_WIDTH = 8,
    parameter CQN_WIDTH = (TX_QUEUE_INDEX_WIDTH > RX_QUEUE_INDEX_WIDTH ? TX_QUEUE_INDEX_WIDTH : RX_QUEUE_INDEX_WIDTH) + 1,
    parameter EQ_PIPELINE = 3,
    parameter TX_QUEUE_PIPELINE = 3+(TX_QUEUE_INDEX_WIDTH > 12 ? TX_QUEUE_INDEX_WIDTH-12 : 0),
    parameter RX_QUEUE_PIPELINE = 3+(RX_QUEUE_INDEX_WIDTH > 12 ? RX_QUEUE_INDEX_WIDTH-12 : 0),
    parameter CQ_PIPELINE = 3+(CQN_WIDTH > 12 ? CQN_WIDTH-12 : 0),

    // TX and RX engine configuration
    parameter TX_DESC_TABLE_SIZE = 32,
    parameter RX_DESC_TABLE_SIZE = 32,
    parameter RX_INDIR_TBL_ADDR_WIDTH = RX_QUEUE_INDEX_WIDTH > 8 ? 8 : RX_QUEUE_INDEX_WIDTH,

    // Scheduler configuration
    parameter TX_SCHEDULER_OP_TABLE_SIZE = TX_DESC_TABLE_SIZE,
    parameter TX_SCHEDULER_PIPELINE = TX_QUEUE_PIPELINE,
    parameter TDMA_INDEX_WIDTH = 6,

    // Interface configuration
    parameter PTP_TS_ENABLE = 1,
    parameter TX_CPL_FIFO_DEPTH = 32,
    parameter TX_CHECKSUM_ENABLE = 1,
    parameter RX_HASH_ENABLE = 1,
    parameter RX_CHECKSUM_ENABLE = 1,
    parameter ENABLE_PADDING = 1,
    parameter ENABLE_DIC = 1,
    parameter MIN_FRAME_LENGTH = 64,
    parameter TX_FIFO_DEPTH = 32768,
    parameter RX_FIFO_DEPTH = 32768,
    parameter MAX_TX_SIZE = 9214,
    parameter MAX_RX_SIZE = 9214,
    parameter TX_RAM_SIZE = 32768,
    parameter RX_RAM_SIZE = 32768,

    // RAM configuration
    parameter DDR_CH = 1,
    parameter DDR_ENABLE = 0,
    parameter AXI_DDR_DATA_WIDTH = 512,
    parameter AXI_DDR_ADDR_WIDTH = 31,
    parameter AXI_DDR_ID_WIDTH = 8,
    parameter AXI_DDR_MAX_BURST_LEN = 256,
    parameter AXI_DDR_NARROW_BURST = 0,

    // Application block configuration
    parameter APP_ID = 32'h00000000,
    parameter APP_ENABLE = 0,
    parameter APP_CTRL_ENABLE = 1,
    parameter APP_DMA_ENABLE = 1,
    parameter APP_AXIS_DIRECT_ENABLE = 1,
    parameter APP_AXIS_SYNC_ENABLE = 1,
    parameter APP_AXIS_IF_ENABLE = 1,
    parameter APP_STAT_ENABLE = 1,

    // DMA interface configuration
    parameter DMA_IMM_ENABLE = 0,
    parameter DMA_IMM_WIDTH = 32,
    parameter DMA_LEN_WIDTH = 16,
    parameter DMA_TAG_WIDTH = 16,
    parameter RAM_ADDR_WIDTH = $clog2(TX_RAM_SIZE > RX_RAM_SIZE ? TX_RAM_SIZE : RX_RAM_SIZE),
    parameter RAM_PIPELINE = 3,                 //2

    // PCIe interface configuration
    parameter AXIS_PCIE_DATA_WIDTH = 256,
    parameter PF_COUNT = 1,
    parameter VF_COUNT = 0,

    // Interrupt configuration
    parameter IRQ_INDEX_WIDTH = EQN_WIDTH,

    // AXI lite interface configuration (control)
    parameter AXIL_CTRL_DATA_WIDTH = 32,
    parameter AXIL_CTRL_ADDR_WIDTH = 24,

    // AXI lite interface configuration (application control)
    parameter AXIL_APP_CTRL_DATA_WIDTH = AXIL_CTRL_DATA_WIDTH,
    parameter AXIL_APP_CTRL_ADDR_WIDTH = 24,

    // Ethernet interface configuration
    parameter AXIS_ETH_TX_PIPELINE = 3,   //0
    parameter AXIS_ETH_TX_FIFO_PIPELINE = 3,   //2
    parameter AXIS_ETH_TX_TS_PIPELINE = 3,   //0
    parameter AXIS_ETH_RX_PIPELINE = 3,         //0
    parameter AXIS_ETH_RX_FIFO_PIPELINE = 3,      //2

    // Statistics counter subsystem
    parameter STAT_ENABLE = 1,
    parameter STAT_DMA_ENABLE = 1,
    parameter STAT_PCIE_ENABLE = 1,
    parameter STAT_INC_WIDTH = 24,
    parameter STAT_ID_WIDTH = 12
)
(
    /*
     * Clock: 100MHz LVDS
     * Reset: Push button, active HIGH
     */
    input  wire         clk_300mhz_p,
    input  wire         clk_300mhz_n,
     input  wire         reset,

    /*
     * PCI express
     */
    input  wire [7:0]   pcie_rx_p,
    input  wire [7:0]   pcie_rx_n,
    output wire [7:0]   pcie_tx_p,
    output wire [7:0]   pcie_tx_n,
    input  wire         pcie_mgt_refclk_p,
    input  wire         pcie_mgt_refclk_n,
    input  wire         pcie_reset_n,

    /*
     * Ethernet: SFP+
     */
    input  wire         sfp0_rx_p,
    input  wire         sfp0_rx_n,
    output wire         sfp0_tx_p,
    output wire         sfp0_tx_n,

    input  wire         sfp_mgt_refclk_0_p,
    input  wire         sfp_mgt_refclk_0_n,

    output wire gtrefclk_out_p,
    output wire gtrefclk_out_n,

    output    wire    sfp_1_led,
    output     wire    sfp_2_led,
    output wire mmcm_locked_led,
    output wire pcie_lnk_up_led,
    output wire clk_100mhz_ibufg_led,
    /*
     * I2C for board management
     */
    inout  wire         i2c_scl,
    output wire         i2c_rst_n,
   inout  wire         i2c_sda


);
    wire         btnu;
    wire         btnl;
    wire         btnd;
    wire         btnr;
    wire         btnc;
    wire [7:0]   sw;
    wire [7:0]   led;
     wire         sfp1_rx_p;
     wire         sfp1_rx_n;
   wire         sfp1_tx_p;
     wire         sfp1_tx_n;


    wire i2c_scl_i;
    wire i2c_scl_o;
    wire i2c_scl_t;
    wire i2c_sda_i;
    wire i2c_sda_o;
    wire i2c_sda_t;
    wire btnu_int;
    wire btnl_int;
    wire btnd_int;
    wire btnr_int;
    wire btnc_int;
    wire [7:0] sw_int;
    reg i2c_scl_o_reg;
    reg i2c_scl_t_reg;
    reg i2c_sda_o_reg;
    reg i2c_sda_t_reg;
    wire         sfp0_tx_disable_b;
    wire         sfp1_tx_disable_b;
    assign i2c_rst_n=1'b1;
    debounce_switch #(
    .WIDTH(13),
    .N(4),
    .RATE(250000)
    )
    debounce_switch_inst (
        .clk(pcie_user_clk),
        .rst(pcie_user_reset),
        .in({btnu,
        btnl,
        btnd,
        btnr,
        btnc,
        sw}),
        .out({btnu_int,
        btnl_int,
        btnd_int,
        btnr_int,
        btnc_int,
        sw_int})
    );


    reg  [25:0] clk_100mhz_heartbeat=  26'd0;


    always @(posedge clk_100mhz_ibufg) begin

        clk_100mhz_heartbeat <= clk_100mhz_heartbeat + 1'b1;
    end
    assign clk_100mhz_ibufg_led = clk_100mhz_heartbeat[25];

    always @(posedge pcie_user_clk) begin
        i2c_scl_o_reg <= i2c_scl_o;
        i2c_scl_t_reg <= i2c_scl_t;
        i2c_sda_o_reg <= i2c_sda_o;
        i2c_sda_t_reg <= i2c_sda_t;
    end

    sync_signal #(
    .WIDTH(2),
    .N(2)
    )
    sync_signal_inst (
        .clk(pcie_user_clk),
        .in({       i2c_scl, i2c_sda}),
        .out({     i2c_scl_i, i2c_sda_i})
    );

    assign i2c_scl = i2c_scl_t_reg ? 1'bz : i2c_scl_o_reg;
    assign i2c_sda = i2c_sda_t_reg ? 1'bz : i2c_sda_o_reg;



    wire         sfp_1_npres;
    wire         sfp_2_npres;
    wire         sfp_1_los;
    wire         sfp_2_los;
    wire         sfp_1_rs;
    wire         sfp_2_rs;

    //      wire         sfp_i2c_scl;
    //      wire         sfp_1_i2c_sda;
    wire         sfp_2_i2c_sda;

    wire         eeprom_i2c_scl;
    wire         eeprom_i2c_sda;

    /*
     * GPIO
     */

    wire    sma_led;

    wire         sma_in;
    wire         sma_out;
    wire         sma_out_en;
    wire         sma_term_en;


    // PTP configuration
    parameter PTP_CLK_PERIOD_NS_NUM = 1024;
    parameter PTP_CLK_PERIOD_NS_DENOM = 165;
    parameter PTP_TS_WIDTH = 96;
    parameter IF_PTP_PERIOD_NS = 6'h6;
    parameter IF_PTP_PERIOD_FNS = 16'h6666;

    // Interface configuration
    parameter TX_TAG_WIDTH = 16;
    parameter AXI_DDR_STRB_WIDTH = (AXI_DDR_DATA_WIDTH/8);
    // PCIe interface configuration
    parameter AXIS_PCIE_KEEP_WIDTH = (AXIS_PCIE_DATA_WIDTH/32);
    parameter AXIS_PCIE_RC_USER_WIDTH = 75;
    parameter AXIS_PCIE_RQ_USER_WIDTH = 60;
    parameter AXIS_PCIE_CQ_USER_WIDTH = 85;
    parameter AXIS_PCIE_CC_USER_WIDTH = 33;
    parameter RC_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 256;
    parameter RQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512;
    parameter CQ_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512;
    parameter CC_STRADDLE = AXIS_PCIE_DATA_WIDTH >= 512;
    parameter RQ_SEQ_NUM_WIDTH = 4;
    parameter PCIE_TAG_COUNT = 64;

    // Ethernet interface configuration
    parameter XGMII_DATA_WIDTH = 64;
    parameter XGMII_CTRL_WIDTH = XGMII_DATA_WIDTH/8;
    parameter AXIS_ETH_DATA_WIDTH = XGMII_DATA_WIDTH;
    parameter AXIS_ETH_KEEP_WIDTH = AXIS_ETH_DATA_WIDTH/8;
    parameter AXIS_ETH_SYNC_DATA_WIDTH = AXIS_ETH_DATA_WIDTH;
    parameter AXIS_ETH_TX_USER_WIDTH = TX_TAG_WIDTH + 1;
    parameter AXIS_ETH_RX_USER_WIDTH = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1;

    /*
     * BPI Flash
     */
    wire [15:0]  flash_dq;
    wire [22:0]  flash_addr;
    wire         flash_region;
    wire         flash_ce_n;
    wire         flash_oe_n;
    wire         flash_we_n;
    wire         flash_adv_n;
    // Clock and reset
    wire pcie_user_clk;
    wire pcie_user_reset;

    wire clk_100mhz_ibufg;
    wire clk_125mhz_mmcm_out;

    // Internal 125 MHz clock
    wire clk_125mhz_int;
    wire rst_125mhz_int;

    wire mmcm_rst = pcie_user_reset;
    wire mmcm_locked;
    wire mmcm_clkfb;

    assign mmcm_locked_led = mmcm_locked;
    //IBUFGDS #(
    //   .DIFF_TERM("FALSE"),
    //   .IBUF_LOW_PWR("FALSE")   
    //)
    //clk_100mhz_ibufg_inst (
    //   .O   (clk_100mhz_ibufg),
    //   .I   (clk_100mhz_p),
    //   .IB  (clk_100mhz_n) 
    //);
    wire gtrefclk_out;

    clk_wiz_0 clk
    (
        // Clock out ports
        .clk_out1(clk_100mhz_ibufg), // output clk_out1
        .clk_out2(clk_125mhz_mmcm_out),
        .clk_out3(gtrefclk_out),
        // Status and control signals
        .locked(mmcm_locked), // output locked
        // Clock in ports
        .clk_in1_p(clk_300mhz_p), // input clk_in1_p
        .clk_in1_n(clk_300mhz_n)); // input clk_in1_n

    OBUFDS gtrefclkbuf (
        .O(gtrefclk_out_p), // 1-bit output: Diff_p output (connect directly to top-level port)
        .OB(gtrefclk_out_n), // 1-bit output: Diff_n output (connect directly to top-level port)
        .I(gtrefclk_out) // 1-bit input: Buffer input
    );


    //BUFG
    //clk_125mhz_bufg_inst (
    //    .I(clk_125mhz_mmcm_out),
    //    .O(clk_125mhz_int)
    //);
    assign clk_125mhz_int = clk_125mhz_mmcm_out;
    sync_reset #(
    .N(4)
    )
    sync_reset_125mhz_inst (
        .clk(clk_125mhz_int),
        .rst(reset || ~mmcm_locked),
        .out(rst_125mhz_int)
    );

    // GPIO
    wire sfp_1_npres_int;
    wire sfp_2_npres_int;
    wire sfp_1_los_int;
    wire sfp_2_los_int;
    wire sfp_i2c_scl_i;
    wire sfp_i2c_scl_o;
    wire sfp_i2c_scl_t;
    wire sfp_1_i2c_sda_i;
    wire sfp_1_i2c_sda_o;
    wire sfp_1_i2c_sda_t;
    wire sfp_2_i2c_sda_i;
    wire sfp_2_i2c_sda_o;
    wire sfp_2_i2c_sda_t;
    wire eeprom_i2c_scl_i;
    wire eeprom_i2c_scl_o;
    wire eeprom_i2c_scl_t;
    wire eeprom_i2c_sda_i;
    wire eeprom_i2c_sda_o;
    wire eeprom_i2c_sda_t;

    reg sfp_i2c_scl_o_reg;
    reg sfp_i2c_scl_t_reg;
    reg sfp_1_i2c_sda_o_reg;
    reg sfp_1_i2c_sda_t_reg;
    reg sfp_2_i2c_sda_o_reg;
    reg sfp_2_i2c_sda_t_reg;
    reg eeprom_i2c_scl_o_reg;
    reg eeprom_i2c_scl_t_reg;
    reg eeprom_i2c_sda_o_reg;
    reg eeprom_i2c_sda_t_reg;

    always @(posedge pcie_user_clk) begin
        sfp_i2c_scl_o_reg <= sfp_i2c_scl_o;
        sfp_i2c_scl_t_reg <= sfp_i2c_scl_t;
        sfp_1_i2c_sda_o_reg <= sfp_1_i2c_sda_o;
        sfp_1_i2c_sda_t_reg <= sfp_1_i2c_sda_t;
        sfp_2_i2c_sda_o_reg <= sfp_2_i2c_sda_o;
        sfp_2_i2c_sda_t_reg <= sfp_2_i2c_sda_t;
        eeprom_i2c_scl_o_reg <= eeprom_i2c_scl_o;
        eeprom_i2c_scl_t_reg <= eeprom_i2c_scl_t;
        eeprom_i2c_sda_o_reg <= eeprom_i2c_sda_o;
        eeprom_i2c_sda_t_reg <= eeprom_i2c_sda_t;
    end

    //sync_signal #(
    //    .WIDTH(9),
    //    .N(2)
    //)
    //sync_signal_inst_sfp (
    //    .clk(pcie_user_clk),
    //    .in({sfp_1_npres, sfp_2_npres, sfp_1_los, sfp_2_los,
    //        sfp_i2c_scl, sfp_1_i2c_sda, sfp_2_i2c_sda,
    //        eeprom_i2c_scl, eeprom_i2c_sda}),
    //    .out({sfp_1_npres_int, sfp_2_npres_int, sfp_1_los_int, sfp_2_los_int,
    //        sfp_i2c_scl_i, sfp_1_i2c_sda_i, sfp_2_i2c_sda_i,
    //        eeprom_i2c_scl_i, eeprom_i2c_sda_i})
    //);

    //assign sfp_i2c_scl = sfp_i2c_scl_t_reg ? 1'bz : sfp_i2c_scl_o_reg;
    //assign sfp_1_i2c_sda = sfp_1_i2c_sda_t_reg ? 1'bz : sfp_1_i2c_sda_o_reg;
    //assign sfp_2_i2c_sda = sfp_2_i2c_sda_t_reg ? 1'bz : sfp_2_i2c_sda_o_reg;
    //assign eeprom_i2c_scl = eeprom_i2c_scl_t_reg ? 1'bz : eeprom_i2c_scl_o_reg;
    //assign eeprom_i2c_sda = eeprom_i2c_sda_t_reg ? 1'bz : eeprom_i2c_sda_o_reg;

    // Flash
    wire [15:0] flash_dq_i_int;
    wire [15:0] flash_dq_o_int;
    wire flash_dq_oe_int;
    wire [22:0] flash_addr_int;
    wire flash_region_int;
    wire flash_region_oe_int;
    wire flash_ce_n_int;
    wire flash_oe_n_int;
    wire flash_we_n_int;
    wire flash_adv_n_int;

    reg [15:0] flash_dq_o_reg;
    reg flash_dq_oe_reg;
    reg [22:0] flash_addr_reg;
    reg flash_region_reg;
    reg flash_region_oe_reg;
    reg flash_ce_n_reg;
    reg flash_oe_n_reg;
    reg flash_we_n_reg;
    reg flash_adv_n_reg;

    always @(posedge pcie_user_clk) begin
        flash_dq_o_reg <= flash_dq_o_int;
        flash_dq_oe_reg <= flash_dq_oe_int;
        flash_addr_reg <= flash_addr_int;
        flash_region_reg <= flash_region_int;
        flash_region_oe_reg <= flash_region_oe_int;
        flash_ce_n_reg <= flash_ce_n_int;
        flash_oe_n_reg <= flash_oe_n_int;
        flash_we_n_reg <= flash_we_n_int;
        flash_adv_n_reg <= flash_adv_n_int;
    end

    assign flash_dq = flash_dq_oe_reg ? flash_dq_o_reg : 16'hzzzz;
    assign flash_addr = flash_addr_reg;
    assign flash_region = flash_region_oe_reg ? flash_region_reg : 1'bz;
    assign flash_ce_n = flash_ce_n_reg;
    assign flash_oe_n = flash_oe_n_reg;
    assign flash_we_n = flash_we_n_reg;
    assign flash_adv_n = flash_adv_n_reg;

    sync_signal #(
    .WIDTH(16),
    .N(2)
    )
    flash_sync_signal_inst (
        .clk(pcie_user_clk),
        .in(flash_dq),
        .out(flash_dq_i_int)
    );

    // FPGA boot
    wire fpga_boot;

    reg fpga_boot_sync_reg_0 = 1'b0;
    reg fpga_boot_sync_reg_1 = 1'b0;
    reg fpga_boot_sync_reg_2 = 1'b0;

    wire icap_avail;
    reg [2:0] icap_state = 0;
    reg icap_csib_reg = 1'b1;
    reg icap_rdwrb_reg = 1'b0;
    reg [31:0] icap_di_reg = 32'hffffffff;

    wire [31:0] icap_di_rev;

    assign icap_di_rev[ 7] = icap_di_reg[ 0];
    assign icap_di_rev[ 6] = icap_di_reg[ 1];
    assign icap_di_rev[ 5] = icap_di_reg[ 2];
    assign icap_di_rev[ 4] = icap_di_reg[ 3];
    assign icap_di_rev[ 3] = icap_di_reg[ 4];
    assign icap_di_rev[ 2] = icap_di_reg[ 5];
    assign icap_di_rev[ 1] = icap_di_reg[ 6];
    assign icap_di_rev[ 0] = icap_di_reg[ 7];

    assign icap_di_rev[15] = icap_di_reg[ 8];
    assign icap_di_rev[14] = icap_di_reg[ 9];
    assign icap_di_rev[13] = icap_di_reg[10];
    assign icap_di_rev[12] = icap_di_reg[11];
    assign icap_di_rev[11] = icap_di_reg[12];
    assign icap_di_rev[10] = icap_di_reg[13];
    assign icap_di_rev[ 9] = icap_di_reg[14];
    assign icap_di_rev[ 8] = icap_di_reg[15];

    assign icap_di_rev[23] = icap_di_reg[16];
    assign icap_di_rev[22] = icap_di_reg[17];
    assign icap_di_rev[21] = icap_di_reg[18];
    assign icap_di_rev[20] = icap_di_reg[19];
    assign icap_di_rev[19] = icap_di_reg[20];
    assign icap_di_rev[18] = icap_di_reg[21];
    assign icap_di_rev[17] = icap_di_reg[22];
    assign icap_di_rev[16] = icap_di_reg[23];

    assign icap_di_rev[31] = icap_di_reg[24];
    assign icap_di_rev[30] = icap_di_reg[25];
    assign icap_di_rev[29] = icap_di_reg[26];
    assign icap_di_rev[28] = icap_di_reg[27];
    assign icap_di_rev[27] = icap_di_reg[28];
    assign icap_di_rev[26] = icap_di_reg[29];
    assign icap_di_rev[25] = icap_di_reg[30];
    assign icap_di_rev[24] = icap_di_reg[31];

    always @(posedge clk_125mhz_int) begin
        case (icap_state)
            0: begin
                icap_state <= 0;
                icap_csib_reg <= 1'b1;
                icap_rdwrb_reg <= 1'b0;
                icap_di_reg <= 32'hffffffff; // dummy word

                if (fpga_boot_sync_reg_2 && icap_avail) begin
                    icap_state <= 1;
                    icap_csib_reg <= 1'b0;
                    icap_rdwrb_reg <= 1'b0;
                    icap_di_reg <= 32'hffffffff; // dummy word
                end
            end
            1: begin
                icap_state <= 2;
                icap_csib_reg <= 1'b0;
                icap_rdwrb_reg <= 1'b0;
                icap_di_reg <= 32'hAA995566; // sync word
            end
            2: begin
                icap_state <= 3;
                icap_csib_reg <= 1'b0;
                icap_rdwrb_reg <= 1'b0;
                icap_di_reg <= 32'h20000000; // type 1 noop
            end
            3: begin
                icap_state <= 4;
                icap_csib_reg <= 1'b0;
                icap_rdwrb_reg <= 1'b0;
                icap_di_reg <= 32'h30008001; // write 1 word to CMD
            end
            4: begin
                icap_state <= 5;
                icap_csib_reg <= 1'b0;
                icap_rdwrb_reg <= 1'b0;
                icap_di_reg <= 32'h0000000F; // IPROG
            end
            5: begin
                icap_state <= 0;
                icap_csib_reg <= 1'b0;
                icap_rdwrb_reg <= 1'b0;
                icap_di_reg <= 32'h20000000; // type 1 noop
            end
        endcase

        fpga_boot_sync_reg_0 <= fpga_boot;
        fpga_boot_sync_reg_1 <= fpga_boot_sync_reg_0;
        fpga_boot_sync_reg_2 <= fpga_boot_sync_reg_1;
    end

    ICAPE3
    icape3_inst (
        .AVAIL(icap_avail),
        .CLK(clk_125mhz_int),
        .CSIB(icap_csib_reg),
        .I(icap_di_rev),
        .O(),
        .PRDONE(),
        .PRERROR(),
        .RDWRB(icap_rdwrb_reg)
    );

    // PCIe
    wire pcie_sys_clk;
    wire pcie_sys_clk_gt;

    IBUFDS_GTE3 #(
    .REFCLK_HROW_CK_SEL(2'b00)
    )
    ibufds_gte3_pcie_mgt_refclk_inst (
        .I             (pcie_mgt_refclk_p),
        .IB            (pcie_mgt_refclk_n),
        .CEB           (1'b0),
        .O             (pcie_sys_clk_gt),
        .ODIV2         (pcie_sys_clk)
    );

    wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_rq_tdata;
    wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_rq_tkeep;
    wire                               axis_rq_tlast;
    wire                               axis_rq_tready;
    wire [AXIS_PCIE_RQ_USER_WIDTH-1:0] axis_rq_tuser;
    wire                               axis_rq_tvalid;

    wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_rc_tdata;
    wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_rc_tkeep;
    wire                               axis_rc_tlast;
    wire                               axis_rc_tready;
    wire [AXIS_PCIE_RC_USER_WIDTH-1:0] axis_rc_tuser;
    wire                               axis_rc_tvalid;

    wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_cq_tdata;
    wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_cq_tkeep;
    wire                               axis_cq_tlast;
    wire                               axis_cq_tready;
    wire [AXIS_PCIE_CQ_USER_WIDTH-1:0] axis_cq_tuser;
    wire                               axis_cq_tvalid;

    wire [AXIS_PCIE_DATA_WIDTH-1:0]    axis_cc_tdata;
    wire [AXIS_PCIE_KEEP_WIDTH-1:0]    axis_cc_tkeep;
    wire                               axis_cc_tlast;
    wire                               axis_cc_tready;
    wire [AXIS_PCIE_CC_USER_WIDTH-1:0] axis_cc_tuser;
    wire                               axis_cc_tvalid;

    wire [RQ_SEQ_NUM_WIDTH-1:0]        pcie_rq_seq_num;
    wire                               pcie_rq_seq_num_vld;

    wire [1:0] pcie_tfc_nph_av;
    wire [1:0] pcie_tfc_npd_av;

    wire [2:0] cfg_max_payload;
    wire [2:0] cfg_max_read_req;
    wire [3:0] cfg_rcb_status;

    wire [18:0] cfg_mgmt_addr;
    wire        cfg_mgmt_write;
    wire [31:0] cfg_mgmt_write_data;
    wire [3:0]  cfg_mgmt_byte_enable;
    wire        cfg_mgmt_read;
    wire [31:0] cfg_mgmt_read_data;
    wire        cfg_mgmt_read_write_done;

    wire [7:0]  cfg_fc_ph;
    wire [11:0] cfg_fc_pd;
    wire [7:0]  cfg_fc_nph;
    wire [11:0] cfg_fc_npd;
    wire [7:0]  cfg_fc_cplh;
    wire [11:0] cfg_fc_cpld;
    wire [2:0]  cfg_fc_sel;

    wire [1:0]  cfg_interrupt_msix_enable;
    wire [1:0]  cfg_interrupt_msix_mask;
    wire [7:0]  cfg_interrupt_msix_vf_enable;
    wire [7:0]  cfg_interrupt_msix_vf_mask;
    wire [63:0] cfg_interrupt_msix_address;
    wire [31:0] cfg_interrupt_msix_data;
    wire        cfg_interrupt_msix_int;
    wire        cfg_interrupt_msix_sent;
    wire        cfg_interrupt_msix_fail;
    wire [3:0]  cfg_interrupt_msi_function_number;

    wire status_error_cor;
    wire status_error_uncor;

    // extra register for pcie_user_reset signal
    wire pcie_user_reset_int;
    (* shreg_extract = "no" *)
    reg pcie_user_reset_reg_1 = 1'b1;
    (* shreg_extract = "no" *)
    reg pcie_user_reset_reg_2 = 1'b1;

    always @(posedge pcie_user_clk) begin
        pcie_user_reset_reg_1 <= pcie_user_reset_int;
        pcie_user_reset_reg_2 <= pcie_user_reset_reg_1;
    end

    BUFG
    pcie_user_reset_bufg_inst (
        .I(pcie_user_reset_reg_2),
        .O(pcie_user_reset)
    );

    pcie3_ultrascale_0
    pcie3_ultrascale_inst (
        .pci_exp_txn(pcie_tx_n),
        .pci_exp_txp(pcie_tx_p),
        .pci_exp_rxn(pcie_rx_n),
        .pci_exp_rxp(pcie_rx_p),
        .user_clk(pcie_user_clk),
        .user_reset(pcie_user_reset_int),
        .user_lnk_up(pcie_lnk_up_led),

        .s_axis_rq_tdata(axis_rq_tdata),
        .s_axis_rq_tkeep(axis_rq_tkeep),
        .s_axis_rq_tlast(axis_rq_tlast),
        .s_axis_rq_tready(axis_rq_tready),
        .s_axis_rq_tuser(axis_rq_tuser),
        .s_axis_rq_tvalid(axis_rq_tvalid),

        .m_axis_rc_tdata(axis_rc_tdata),
        .m_axis_rc_tkeep(axis_rc_tkeep),
        .m_axis_rc_tlast(axis_rc_tlast),
        .m_axis_rc_tready(axis_rc_tready),
        .m_axis_rc_tuser(axis_rc_tuser),
        .m_axis_rc_tvalid(axis_rc_tvalid),

        .m_axis_cq_tdata(axis_cq_tdata),
        .m_axis_cq_tkeep(axis_cq_tkeep),
        .m_axis_cq_tlast(axis_cq_tlast),
        .m_axis_cq_tready(axis_cq_tready),
        .m_axis_cq_tuser(axis_cq_tuser),
        .m_axis_cq_tvalid(axis_cq_tvalid),

        .s_axis_cc_tdata(axis_cc_tdata),
        .s_axis_cc_tkeep(axis_cc_tkeep),
        .s_axis_cc_tlast(axis_cc_tlast),
        .s_axis_cc_tready(axis_cc_tready),
        .s_axis_cc_tuser(axis_cc_tuser),
        .s_axis_cc_tvalid(axis_cc_tvalid),

        .pcie_rq_seq_num(pcie_rq_seq_num),
        .pcie_rq_seq_num_vld(pcie_rq_seq_num_vld),
        .pcie_rq_tag(),
        .pcie_rq_tag_av(),
        .pcie_rq_tag_vld(),

        .pcie_tfc_nph_av(pcie_tfc_nph_av),
        .pcie_tfc_npd_av(pcie_tfc_npd_av),

        .pcie_cq_np_req(1'b1),
        .pcie_cq_np_req_count(),

        .cfg_phy_link_down(),
        .cfg_phy_link_status(),
        .cfg_negotiated_width(),
        .cfg_current_speed(),
        .cfg_max_payload(cfg_max_payload),
        .cfg_max_read_req(cfg_max_read_req),
        .cfg_function_status(),
        .cfg_function_power_state(),
        .cfg_vf_status(),
        .cfg_vf_power_state(),
        .cfg_link_power_state(),

        .cfg_mgmt_addr(cfg_mgmt_addr),
        .cfg_mgmt_write(cfg_mgmt_write),
        .cfg_mgmt_write_data(cfg_mgmt_write_data),
        .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
        .cfg_mgmt_read(cfg_mgmt_read),
        .cfg_mgmt_read_data(cfg_mgmt_read_data),
        .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done),
        .cfg_mgmt_type1_cfg_reg_access(1'b0),

        .cfg_err_cor_out(),
        .cfg_err_nonfatal_out(),
        .cfg_err_fatal_out(),
        .cfg_local_error(),
        .cfg_ltr_enable(),
        .cfg_ltssm_state(),
        .cfg_rcb_status(cfg_rcb_status),
        .cfg_dpa_substate_change(),
        .cfg_obff_enable(),
        .cfg_pl_status_change(),
        .cfg_tph_requester_enable(),
        .cfg_tph_st_mode(),
        .cfg_vf_tph_requester_enable(),
        .cfg_vf_tph_st_mode(),

        .cfg_msg_received(),
        .cfg_msg_received_data(),
        .cfg_msg_received_type(),
        .cfg_msg_transmit(1'b0),
        .cfg_msg_transmit_type(3'd0),
        .cfg_msg_transmit_data(32'd0),
        .cfg_msg_transmit_done(),

        .cfg_fc_ph(cfg_fc_ph),
        .cfg_fc_pd(cfg_fc_pd),
        .cfg_fc_nph(cfg_fc_nph),
        .cfg_fc_npd(cfg_fc_npd),
        .cfg_fc_cplh(cfg_fc_cplh),
        .cfg_fc_cpld(cfg_fc_cpld),
        .cfg_fc_sel(cfg_fc_sel),

        .cfg_per_func_status_control(3'd0),
        .cfg_per_func_status_data(),
        .cfg_per_function_number(4'd0),
        .cfg_per_function_output_request(1'b0),
        .cfg_per_function_update_done(),

        .cfg_dsn(64'd0),

        .cfg_power_state_change_ack(1'b1),
        .cfg_power_state_change_interrupt(),

        .cfg_err_cor_in(status_error_cor),
        .cfg_err_uncor_in(status_error_uncor),
        .cfg_flr_in_process(),
        .cfg_flr_done(4'd0),
        .cfg_vf_flr_in_process(),
        .cfg_vf_flr_done(8'd0),

        .cfg_link_training_enable(1'b1),

        .cfg_interrupt_int(4'd0),
        .cfg_interrupt_pending(4'd0),
        .cfg_interrupt_sent(),
        .cfg_interrupt_msix_enable(cfg_interrupt_msix_enable),
        .cfg_interrupt_msix_mask(cfg_interrupt_msix_mask),
        .cfg_interrupt_msix_vf_enable(cfg_interrupt_msix_vf_enable),
        .cfg_interrupt_msix_vf_mask(cfg_interrupt_msix_vf_mask),
        .cfg_interrupt_msix_address(cfg_interrupt_msix_address),
        .cfg_interrupt_msix_data(cfg_interrupt_msix_data),
        .cfg_interrupt_msix_int(cfg_interrupt_msix_int),
        .cfg_interrupt_msix_sent(cfg_interrupt_msix_sent),
        .cfg_interrupt_msix_fail(cfg_interrupt_msix_fail),
        .cfg_interrupt_msi_function_number(cfg_interrupt_msi_function_number),

        .cfg_hot_reset_out(),

        .cfg_config_space_enable(1'b1),
        .cfg_req_pm_transition_l23_ready(1'b0),
        .cfg_hot_reset_in(1'b0),

        .cfg_ds_port_number(8'd0),
        .cfg_ds_bus_number(8'd0),
        .cfg_ds_device_number(5'd0),
        .cfg_ds_function_number(3'd0),

        .cfg_subsys_vend_id(BOARD_ID >> 16),

        .sys_clk(pcie_sys_clk),
        .sys_clk_gt(pcie_sys_clk_gt),
        .sys_reset(pcie_reset_n),
        .pcie_perstn1_in(1'b0),
        .pcie_perstn0_out(),
        .pcie_perstn1_out(),

        .int_qpll1lock_out(),
        .int_qpll1outrefclk_out(),
        .int_qpll1outclk_out(),
        .phy_rdy_out()
    );

    // XGMII 10G PHY
    wire                         sfp0_tx_clk_int;
    wire                         sfp0_tx_rst_int;
    wire [XGMII_DATA_WIDTH-1:0]  sfp0_txd_int;
    wire [XGMII_CTRL_WIDTH-1:0]  sfp0_txc_int;
    wire                         sfp0_cfg_tx_prbs31_enable_int;
    wire                         sfp0_rx_clk_int;
    wire                         sfp0_rx_rst_int;
    wire [XGMII_DATA_WIDTH-1:0]  sfp0_rxd_int;
    wire [XGMII_CTRL_WIDTH-1:0]  sfp0_rxc_int;
    wire                         sfp0_cfg_rx_prbs31_enable_int;
    wire [6:0]                   sfp0_rx_error_count_int;

    wire                         sfp1_tx_clk_int;
    wire                         sfp1_tx_rst_int;
    wire [XGMII_DATA_WIDTH-1:0]  sfp1_txd_int;
    wire [XGMII_CTRL_WIDTH-1:0]  sfp1_txc_int;
    wire                         sfp1_cfg_tx_prbs31_enable_int;
    wire                         sfp1_rx_clk_int;
    wire                         sfp1_rx_rst_int;
    wire [XGMII_DATA_WIDTH-1:0]  sfp1_rxd_int;
    wire [XGMII_CTRL_WIDTH-1:0]  sfp1_rxc_int;
    wire                         sfp1_cfg_rx_prbs31_enable_int;
    wire [6:0]                   sfp1_rx_error_count_int;

    wire        sfp_drp_clk = clk_125mhz_int;
    wire        sfp_drp_rst = rst_125mhz_int;
    wire [23:0] sfp_drp_addr;
    wire [15:0] sfp_drp_di;
    wire        sfp_drp_en;
    wire        sfp_drp_we;
    wire [15:0] sfp_drp_do;
    wire        sfp_drp_rdy;

    wire sfp0_rx_block_lock;
    wire sfp0_rx_status;
    wire sfp1_rx_block_lock;
    wire sfp1_rx_status;

    wire sfp_gtpowergood;

    wire sfp_mgt_refclk;
    wire sfp_mgt_refclk_int;
    wire sfp_mgt_refclk_bufg;

    IBUFDS_GTE3 ibufds_gte3_sfp_mgt_refclk_inst (
        .I     (sfp_mgt_refclk_0_p),
        .IB    (sfp_mgt_refclk_0_n),
        .CEB   (1'b0),
        .O     (sfp_mgt_refclk),
        .ODIV2 (sfp_mgt_refclk_int)
    );

    BUFG_GT bufg_gt_sfp_mgt_refclk_inst (
        .CE      (sfp_gtpowergood),
        .CEMASK  (1'b1),
        .CLR     (1'b0),
        .CLRMASK (1'b1),
        .DIV     (3'd0),
        .I       (sfp_mgt_refclk_int),
        .O       (sfp_mgt_refclk_bufg)
    );

    wire sfp_rst;

    sync_reset #(
    .N(4)
    )
    sfp_sync_reset_inst (
        .clk(sfp_mgt_refclk_bufg),
        .rst(rst_125mhz_int),
        .out(sfp_rst)
    );


    eth_xcvr_phy_10g_gty_quad_wrapper #(
    .COUNT(1),
    .GT_GTH(1),
    .PRBS31_ENABLE(1),
    .COUNT_125US(SFP_COUNT_125US)
    )
    sfp_phy_quad_inst (
        .xcvr_ctrl_clk(clk_125mhz_int),
        .xcvr_ctrl_rst(sfp_rst),

        /*
         * Common
         */
        .xcvr_gtpowergood_out(sfp_gtpowergood),
        .xcvr_gtrefclk00_in(sfp_mgt_refclk),
        .xcvr_qpll0pd_in(1'b0),
        .xcvr_qpll0reset_in(1'b0),
        .xcvr_qpll0pcierate_in(3'd0),
        .xcvr_qpll0lock_out(),
        .xcvr_qpll0clk_out(),
        .xcvr_qpll0refclk_out(),
        .xcvr_gtrefclk01_in(sfp_mgt_refclk),
        .xcvr_qpll1pd_in(1'b0),
        .xcvr_qpll1reset_in(1'b0),
        .xcvr_qpll1pcierate_in(3'd0),
        .xcvr_qpll1lock_out(),
        .xcvr_qpll1clk_out(),
        .xcvr_qpll1refclk_out(),

        /*
         * DRP
         */
        .drp_clk(sfp_drp_clk),
        .drp_rst(sfp_drp_rst),
        .drp_addr(sfp_drp_addr),
        .drp_di(sfp_drp_di),
        .drp_en(sfp_drp_en),
        .drp_we(sfp_drp_we),
        .drp_do(sfp_drp_do),
        .drp_rdy(sfp_drp_rdy),

        /*
         * Serial data
         */
        .xcvr_txp({sfp1_tx_p, sfp0_tx_p}),
        .xcvr_txn({sfp1_tx_n, sfp0_tx_n}),
        .xcvr_rxp({sfp1_rx_p, sfp0_rx_p}),
        .xcvr_rxn({sfp1_rx_n, sfp0_rx_n}),

        /*
         * PHY connections
         */
        .phy_1_tx_clk(sfp0_tx_clk_int),
        .phy_1_tx_rst(sfp0_tx_rst_int),
        .phy_1_xgmii_txd(sfp0_txd_int),
        .phy_1_xgmii_txc(sfp0_txc_int),
        .phy_1_rx_clk(sfp0_rx_clk_int),
        .phy_1_rx_rst(sfp0_rx_rst_int),
        .phy_1_xgmii_rxd(sfp0_rxd_int),
        .phy_1_xgmii_rxc(sfp0_rxc_int),
        .phy_1_tx_bad_block(),
        .phy_1_rx_error_count(sfp0_rx_error_count_int),
        .phy_1_rx_bad_block(),
        .phy_1_rx_sequence_error(),
        .phy_1_rx_block_lock(sfp0_rx_block_lock),
        .phy_1_rx_high_ber(),
        .phy_1_rx_status(sfp0_rx_status),
        .phy_1_cfg_tx_prbs31_enable(sfp0_cfg_tx_prbs31_enable_int),
        .phy_1_cfg_rx_prbs31_enable(sfp0_cfg_rx_prbs31_enable_int),

        .phy_2_tx_clk(sfp1_tx_clk_int),
        .phy_2_tx_rst(sfp1_tx_rst_int),
        .phy_2_xgmii_txd(sfp1_txd_int),
        .phy_2_xgmii_txc(sfp1_txc_int),
        .phy_2_rx_clk(sfp1_rx_clk_int),
        .phy_2_rx_rst(sfp1_rx_rst_int),
        .phy_2_xgmii_rxd(sfp1_rxd_int),
        .phy_2_xgmii_rxc(sfp1_rxc_int),
        .phy_2_tx_bad_block(),
        .phy_2_rx_error_count(sfp1_rx_error_count_int),
        .phy_2_rx_bad_block(),
        .phy_2_rx_sequence_error(),
        .phy_2_rx_block_lock(sfp1_rx_block_lock),
        .phy_2_rx_high_ber(),
        .phy_2_rx_status(sfp1_rx_status),
        .phy_2_cfg_tx_prbs31_enable(sfp1_cfg_tx_prbs31_enable_int),
        .phy_2_cfg_rx_prbs31_enable(sfp1_cfg_rx_prbs31_enable_int)
    );

    wire ptp_clk;
    wire ptp_rst;
    wire ptp_sample_clk;
    wire [DDR_CH-1:0]                     ddr_clk;
    wire [DDR_CH-1:0]                     ddr_rst;

    wire [DDR_CH*AXI_DDR_ID_WIDTH-1:0]    m_axi_ddr_awid;
    wire [DDR_CH*AXI_DDR_ADDR_WIDTH-1:0]  m_axi_ddr_awaddr;
    wire [DDR_CH*8-1:0]                   m_axi_ddr_awlen;
    wire [DDR_CH*3-1:0]                   m_axi_ddr_awsize;
    wire [DDR_CH*2-1:0]                   m_axi_ddr_awburst;
    wire [DDR_CH-1:0]                     m_axi_ddr_awlock;
    wire [DDR_CH*4-1:0]                   m_axi_ddr_awcache;
    wire [DDR_CH*3-1:0]                   m_axi_ddr_awprot;
    wire [DDR_CH*4-1:0]                   m_axi_ddr_awqos;
    wire [DDR_CH-1:0]                     m_axi_ddr_awvalid;
    wire [DDR_CH-1:0]                     m_axi_ddr_awready;
    wire [DDR_CH*AXI_DDR_DATA_WIDTH-1:0]  m_axi_ddr_wdata;
    wire [DDR_CH*AXI_DDR_STRB_WIDTH-1:0]  m_axi_ddr_wstrb;
    wire [DDR_CH-1:0]                     m_axi_ddr_wlast;
    wire [DDR_CH-1:0]                     m_axi_ddr_wvalid;
    wire [DDR_CH-1:0]                     m_axi_ddr_wready;
    wire [DDR_CH*AXI_DDR_ID_WIDTH-1:0]    m_axi_ddr_bid;
    wire [DDR_CH*2-1:0]                   m_axi_ddr_bresp;
    wire [DDR_CH-1:0]                     m_axi_ddr_bvalid;
    wire [DDR_CH-1:0]                     m_axi_ddr_bready;
    wire [DDR_CH*AXI_DDR_ID_WIDTH-1:0]    m_axi_ddr_arid;
    wire [DDR_CH*AXI_DDR_ADDR_WIDTH-1:0]  m_axi_ddr_araddr;
    wire [DDR_CH*8-1:0]                   m_axi_ddr_arlen;
    wire [DDR_CH*3-1:0]                   m_axi_ddr_arsize;
    wire [DDR_CH*2-1:0]                   m_axi_ddr_arburst;
    wire [DDR_CH-1:0]                     m_axi_ddr_arlock;
    wire [DDR_CH*4-1:0]                   m_axi_ddr_arcache;
    wire [DDR_CH*3-1:0]                   m_axi_ddr_arprot;
    wire [DDR_CH*4-1:0]                   m_axi_ddr_arqos;
    wire [DDR_CH-1:0]                     m_axi_ddr_arvalid;
    wire [DDR_CH-1:0]                     m_axi_ddr_arready;
    wire [DDR_CH*AXI_DDR_ID_WIDTH-1:0]    m_axi_ddr_rid;
    wire [DDR_CH*AXI_DDR_DATA_WIDTH-1:0]  m_axi_ddr_rdata;
    wire [DDR_CH*2-1:0]                   m_axi_ddr_rresp;
    wire [DDR_CH-1:0]                     m_axi_ddr_rlast;
    wire [DDR_CH-1:0]                     m_axi_ddr_rvalid;
    wire [DDR_CH-1:0]                     m_axi_ddr_rready;

    wire [DDR_CH-1:0]                     ddr_status;

    assign ptp_clk = sfp_mgt_refclk_bufg;
    assign ptp_rst = sfp_rst;
    assign ptp_sample_clk = clk_125mhz_int;

    assign sfp_1_led = sfp0_rx_status;

    assign sfp_2_led = sfp1_rx_status;

    fpga_core #(
    // FW and board IDs
    .FPGA_ID(FPGA_ID),
    .FW_ID(FW_ID),
    .FW_VER(FW_VER),
    .BOARD_ID(BOARD_ID),
    .BOARD_VER(BOARD_VER),
    .BUILD_DATE(BUILD_DATE),
    .GIT_HASH(GIT_HASH),
    .RELEASE_INFO(RELEASE_INFO),

    // Board configuration
    .TDMA_BER_ENABLE(TDMA_BER_ENABLE),

    // Structural configuration
    .IF_COUNT(IF_COUNT),
    .PORTS_PER_IF(PORTS_PER_IF),
    .SCHED_PER_IF(SCHED_PER_IF),
    .PORT_MASK(PORT_MASK),

    // Clock configuration
    .CLK_PERIOD_NS_NUM(CLK_PERIOD_NS_NUM),
    .CLK_PERIOD_NS_DENOM(CLK_PERIOD_NS_DENOM),

    // PTP configuration
    .PTP_CLK_PERIOD_NS_NUM(PTP_CLK_PERIOD_NS_NUM),
    .PTP_CLK_PERIOD_NS_DENOM(PTP_CLK_PERIOD_NS_DENOM),
    .PTP_TS_WIDTH(PTP_TS_WIDTH),
    .PTP_CLOCK_PIPELINE(PTP_CLOCK_PIPELINE),
    .PTP_CLOCK_CDC_PIPELINE(PTP_CLOCK_CDC_PIPELINE),
    .PTP_PORT_CDC_PIPELINE(PTP_PORT_CDC_PIPELINE),
    .PTP_PEROUT_ENABLE(PTP_PEROUT_ENABLE),
    .PTP_PEROUT_COUNT(PTP_PEROUT_COUNT),

    // Queue manager configuration
    .EVENT_QUEUE_OP_TABLE_SIZE(EVENT_QUEUE_OP_TABLE_SIZE),
    .TX_QUEUE_OP_TABLE_SIZE(TX_QUEUE_OP_TABLE_SIZE),
    .RX_QUEUE_OP_TABLE_SIZE(RX_QUEUE_OP_TABLE_SIZE),
    .CQ_OP_TABLE_SIZE(CQ_OP_TABLE_SIZE),
    .EQN_WIDTH(EQN_WIDTH),
    .TX_QUEUE_INDEX_WIDTH(TX_QUEUE_INDEX_WIDTH),
    .RX_QUEUE_INDEX_WIDTH(RX_QUEUE_INDEX_WIDTH),
    .CQN_WIDTH(CQN_WIDTH),
    .EQ_PIPELINE(EQ_PIPELINE),
    .TX_QUEUE_PIPELINE(TX_QUEUE_PIPELINE),
    .RX_QUEUE_PIPELINE(RX_QUEUE_PIPELINE),
    .CQ_PIPELINE(CQ_PIPELINE),

    // TX and RX engine configuration
    .TX_DESC_TABLE_SIZE(TX_DESC_TABLE_SIZE),
    .RX_DESC_TABLE_SIZE(RX_DESC_TABLE_SIZE),
    .RX_INDIR_TBL_ADDR_WIDTH(RX_INDIR_TBL_ADDR_WIDTH),

    // Scheduler configuration
    .TX_SCHEDULER_OP_TABLE_SIZE(TX_SCHEDULER_OP_TABLE_SIZE),
    .TX_SCHEDULER_PIPELINE(TX_SCHEDULER_PIPELINE),
    .TDMA_INDEX_WIDTH(TDMA_INDEX_WIDTH),

    // Interface configuration
    .PTP_TS_ENABLE(PTP_TS_ENABLE),
    .TX_CPL_FIFO_DEPTH(TX_CPL_FIFO_DEPTH),
    .TX_TAG_WIDTH(TX_TAG_WIDTH),
    .TX_CHECKSUM_ENABLE(TX_CHECKSUM_ENABLE),
    .RX_HASH_ENABLE(RX_HASH_ENABLE),
    .RX_CHECKSUM_ENABLE(RX_CHECKSUM_ENABLE),
    .ENABLE_PADDING(ENABLE_PADDING),
    .ENABLE_DIC(ENABLE_DIC),
    .MIN_FRAME_LENGTH(MIN_FRAME_LENGTH),
    .TX_FIFO_DEPTH(TX_FIFO_DEPTH),
    .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
    .MAX_TX_SIZE(MAX_TX_SIZE),
    .MAX_RX_SIZE(MAX_RX_SIZE),
    .TX_RAM_SIZE(TX_RAM_SIZE),
    .RX_RAM_SIZE(RX_RAM_SIZE),


    // Application block configuration
    .APP_ID(APP_ID),
    .APP_ENABLE(APP_ENABLE),
    .APP_CTRL_ENABLE(APP_CTRL_ENABLE),
    .APP_DMA_ENABLE(APP_DMA_ENABLE),
    .APP_AXIS_DIRECT_ENABLE(APP_AXIS_DIRECT_ENABLE),
    .APP_AXIS_SYNC_ENABLE(APP_AXIS_SYNC_ENABLE),
    .APP_AXIS_IF_ENABLE(APP_AXIS_IF_ENABLE),
    .APP_STAT_ENABLE(APP_STAT_ENABLE),

    // DMA interface configuration
    .DMA_IMM_ENABLE(DMA_IMM_ENABLE),
    .DMA_IMM_WIDTH(DMA_IMM_WIDTH),
    .DMA_LEN_WIDTH(DMA_LEN_WIDTH),
    .DMA_TAG_WIDTH(DMA_TAG_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .RAM_PIPELINE(RAM_PIPELINE),

    // PCIe interface configuration
    .AXIS_PCIE_DATA_WIDTH(AXIS_PCIE_DATA_WIDTH),
    .AXIS_PCIE_KEEP_WIDTH(AXIS_PCIE_KEEP_WIDTH),
    .AXIS_PCIE_RC_USER_WIDTH(AXIS_PCIE_RC_USER_WIDTH),
    .AXIS_PCIE_RQ_USER_WIDTH(AXIS_PCIE_RQ_USER_WIDTH),
    .AXIS_PCIE_CQ_USER_WIDTH(AXIS_PCIE_CQ_USER_WIDTH),
    .AXIS_PCIE_CC_USER_WIDTH(AXIS_PCIE_CC_USER_WIDTH),
    .RC_STRADDLE(RC_STRADDLE),
    .RQ_STRADDLE(RQ_STRADDLE),
    .CQ_STRADDLE(CQ_STRADDLE),
    .CC_STRADDLE(CC_STRADDLE),
    .RQ_SEQ_NUM_WIDTH(RQ_SEQ_NUM_WIDTH),
    .PF_COUNT(PF_COUNT),
    .VF_COUNT(VF_COUNT),
    .PCIE_TAG_COUNT(PCIE_TAG_COUNT),

    // Interrupt configuration
    .IRQ_INDEX_WIDTH(IRQ_INDEX_WIDTH),

    // AXI lite interface configuration (control)
    .AXIL_CTRL_DATA_WIDTH(AXIL_CTRL_DATA_WIDTH),
    .AXIL_CTRL_ADDR_WIDTH(AXIL_CTRL_ADDR_WIDTH),

    // AXI lite interface configuration (application control)
    .AXIL_APP_CTRL_DATA_WIDTH(AXIL_APP_CTRL_DATA_WIDTH),
    .AXIL_APP_CTRL_ADDR_WIDTH(AXIL_APP_CTRL_ADDR_WIDTH),

    // Ethernet interface configuration
    .XGMII_DATA_WIDTH(XGMII_DATA_WIDTH),
    .XGMII_CTRL_WIDTH(XGMII_CTRL_WIDTH),
    .AXIS_ETH_DATA_WIDTH(AXIS_ETH_DATA_WIDTH),
    .AXIS_ETH_KEEP_WIDTH(AXIS_ETH_KEEP_WIDTH),
    .AXIS_ETH_SYNC_DATA_WIDTH(AXIS_ETH_SYNC_DATA_WIDTH),
    .AXIS_ETH_TX_USER_WIDTH(AXIS_ETH_TX_USER_WIDTH),
    .AXIS_ETH_RX_USER_WIDTH(AXIS_ETH_RX_USER_WIDTH),
    .AXIS_ETH_TX_PIPELINE(AXIS_ETH_TX_PIPELINE),
    .AXIS_ETH_TX_FIFO_PIPELINE(AXIS_ETH_TX_FIFO_PIPELINE),
    .AXIS_ETH_TX_TS_PIPELINE(AXIS_ETH_TX_TS_PIPELINE),
    .AXIS_ETH_RX_PIPELINE(AXIS_ETH_RX_PIPELINE),
    .AXIS_ETH_RX_FIFO_PIPELINE(AXIS_ETH_RX_FIFO_PIPELINE),

    // Statistics counter subsystem
    .STAT_ENABLE(STAT_ENABLE),
    .STAT_DMA_ENABLE(STAT_DMA_ENABLE),
    .STAT_PCIE_ENABLE(STAT_PCIE_ENABLE),
    .STAT_INC_WIDTH(STAT_INC_WIDTH),
    .STAT_ID_WIDTH(STAT_ID_WIDTH)
    )
    core_inst (
        /*
         * Clock: 250 MHz
         * Synchronous reset
         */
        .clk_250mhz(pcie_user_clk),
        .rst_250mhz(pcie_user_reset),
        // Run MACsec HLS crypto at 10G MAC TX clock domain (156.25 MHz)
        // to raise per-frame crypto throughput vs previous 125 MHz domain.
        .hls_clk(sfp0_tx_clk_int),
        .hls_rst(sfp0_tx_rst_int),

        /*
         * PTP clock
         */
        .ptp_clk(ptp_clk),
        .ptp_rst(ptp_rst),
        .ptp_sample_clk(ptp_sample_clk),

        /*
         * GPIO
         */
        .btnu(btnu_int),
        .btnl(btnl_int),
        .btnd(btnd_int),
        .btnr(btnr_int),
        .btnc(btnc_int),
        .sw(sw_int),
        .led(led),

        /*
         * I2C
         */
        .i2c_scl_i(i2c_scl_i),
        .i2c_scl_o(i2c_scl_o),
        .i2c_scl_t(i2c_scl_t),
        .i2c_sda_i(i2c_sda_i),
        .i2c_sda_o(i2c_sda_o),
        .i2c_sda_t(i2c_sda_t),

        /*
         * PCIe
         */
        .m_axis_rq_tdata(axis_rq_tdata),
        .m_axis_rq_tkeep(axis_rq_tkeep),
        .m_axis_rq_tlast(axis_rq_tlast),
        .m_axis_rq_tready(axis_rq_tready),
        .m_axis_rq_tuser(axis_rq_tuser),
        .m_axis_rq_tvalid(axis_rq_tvalid),

        .s_axis_rc_tdata(axis_rc_tdata),
        .s_axis_rc_tkeep(axis_rc_tkeep),
        .s_axis_rc_tlast(axis_rc_tlast),
        .s_axis_rc_tready(axis_rc_tready),
        .s_axis_rc_tuser(axis_rc_tuser),
        .s_axis_rc_tvalid(axis_rc_tvalid),

        .s_axis_cq_tdata(axis_cq_tdata),
        .s_axis_cq_tkeep(axis_cq_tkeep),
        .s_axis_cq_tlast(axis_cq_tlast),
        .s_axis_cq_tready(axis_cq_tready),
        .s_axis_cq_tuser(axis_cq_tuser),
        .s_axis_cq_tvalid(axis_cq_tvalid),

        .m_axis_cc_tdata(axis_cc_tdata),
        .m_axis_cc_tkeep(axis_cc_tkeep),
        .m_axis_cc_tlast(axis_cc_tlast),
        .m_axis_cc_tready(axis_cc_tready),
        .m_axis_cc_tuser(axis_cc_tuser),
        .m_axis_cc_tvalid(axis_cc_tvalid),

        .s_axis_rq_seq_num_0(pcie_rq_seq_num),
        .s_axis_rq_seq_num_valid_0(pcie_rq_seq_num_vld),
        .s_axis_rq_seq_num_1(4'd0),
        .s_axis_rq_seq_num_valid_1(1'b0),
        .pcie_tfc_nph_av(pcie_tfc_nph_av),
        .pcie_tfc_npd_av(pcie_tfc_npd_av),

        .cfg_max_payload(cfg_max_payload),
        .cfg_max_read_req(cfg_max_read_req),
        .cfg_rcb_status(cfg_rcb_status),

        .cfg_mgmt_addr(cfg_mgmt_addr[9:0]),
        .cfg_mgmt_function_number(cfg_mgmt_addr[17:10]),
        .cfg_mgmt_write(cfg_mgmt_write),
        .cfg_mgmt_write_data(cfg_mgmt_write_data),
        .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
        .cfg_mgmt_read(cfg_mgmt_read),
        .cfg_mgmt_read_data(cfg_mgmt_read_data),
        .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done),

        .cfg_fc_ph(cfg_fc_ph),
        .cfg_fc_pd(cfg_fc_pd),
        .cfg_fc_nph(cfg_fc_nph),
        .cfg_fc_npd(cfg_fc_npd),
        .cfg_fc_cplh(cfg_fc_cplh),
        .cfg_fc_cpld(cfg_fc_cpld),
        .cfg_fc_sel(cfg_fc_sel),

        .cfg_interrupt_msix_enable(cfg_interrupt_msix_enable),
        .cfg_interrupt_msix_mask(cfg_interrupt_msix_mask),
        .cfg_interrupt_msix_vf_enable(cfg_interrupt_msix_vf_enable),
        .cfg_interrupt_msix_vf_mask(cfg_interrupt_msix_vf_mask),
        .cfg_interrupt_msix_address(cfg_interrupt_msix_address),
        .cfg_interrupt_msix_data(cfg_interrupt_msix_data),
        .cfg_interrupt_msix_int(cfg_interrupt_msix_int),
        .cfg_interrupt_msix_vec_pending(),
        .cfg_interrupt_msix_vec_pending_status(1'b0),
        .cfg_interrupt_msix_sent(cfg_interrupt_msix_sent),
        .cfg_interrupt_msix_fail(cfg_interrupt_msix_fail),
        .cfg_interrupt_msi_function_number(cfg_interrupt_msi_function_number),

        .status_error_cor(status_error_cor),
        .status_error_uncor(status_error_uncor),

        /*
         * Ethernet: SFP+
         */
        .sfp0_tx_clk(sfp0_tx_clk_int),
        .sfp0_tx_rst(sfp0_tx_rst_int),
        .sfp0_txd(sfp0_txd_int),
        .sfp0_txc(sfp0_txc_int),
        .sfp0_cfg_tx_prbs31_enable(sfp0_cfg_tx_prbs31_enable_int),
        .sfp0_rx_clk(sfp0_rx_clk_int),
        .sfp0_rx_rst(sfp0_rx_rst_int),
        .sfp0_rxd(sfp0_rxd_int),
        .sfp0_rxc(sfp0_rxc_int),
        .sfp0_cfg_rx_prbs31_enable(sfp0_cfg_rx_prbs31_enable_int),
        .sfp0_rx_error_count(sfp0_rx_error_count_int),
        .sfp0_rx_status(sfp0_rx_status),
        .sfp0_tx_disable_b(sfp0_tx_disable_b),

        .sfp1_tx_clk(sfp1_tx_clk_int),
        .sfp1_tx_rst(sfp1_tx_rst_int),
        .sfp1_txd(sfp1_txd_int),
        .sfp1_txc(sfp1_txc_int),
        .sfp1_cfg_tx_prbs31_enable(sfp1_cfg_tx_prbs31_enable_int),
        .sfp1_rx_clk(sfp1_rx_clk_int),
        .sfp1_rx_rst(sfp1_rx_rst_int),
        .sfp1_rxd(sfp1_rxd_int),
        .sfp1_rxc(sfp1_rxc_int),
        .sfp1_cfg_rx_prbs31_enable(sfp1_cfg_rx_prbs31_enable_int),
        .sfp1_rx_error_count(sfp1_rx_error_count_int),
        .sfp1_rx_status(sfp1_rx_status),
        .sfp1_tx_disable_b(sfp1_tx_disable_b),

        .sfp_drp_clk(sfp_drp_clk),
        .sfp_drp_rst(sfp_drp_rst),
        .sfp_drp_addr(sfp_drp_addr),
        .sfp_drp_di(sfp_drp_di),
        .sfp_drp_en(sfp_drp_en),
        .sfp_drp_we(sfp_drp_we),
        .sfp_drp_do(sfp_drp_do),
        .sfp_drp_rdy(sfp_drp_rdy),

        /*
         * DDR
         */
        .ddr_clk(ddr_clk),
        .ddr_rst(ddr_rst),

        .m_axi_ddr_awid(m_axi_ddr_awid),
        .m_axi_ddr_awaddr(m_axi_ddr_awaddr),
        .m_axi_ddr_awlen(m_axi_ddr_awlen),
        .m_axi_ddr_awsize(m_axi_ddr_awsize),
        .m_axi_ddr_awburst(m_axi_ddr_awburst),
        .m_axi_ddr_awlock(m_axi_ddr_awlock),
        .m_axi_ddr_awcache(m_axi_ddr_awcache),
        .m_axi_ddr_awprot(m_axi_ddr_awprot),
        .m_axi_ddr_awqos(m_axi_ddr_awqos),
        .m_axi_ddr_awvalid(m_axi_ddr_awvalid),
        .m_axi_ddr_awready(m_axi_ddr_awready),
        .m_axi_ddr_wdata(m_axi_ddr_wdata),
        .m_axi_ddr_wstrb(m_axi_ddr_wstrb),
        .m_axi_ddr_wlast(m_axi_ddr_wlast),
        .m_axi_ddr_wvalid(m_axi_ddr_wvalid),
        .m_axi_ddr_wready(m_axi_ddr_wready),
        .m_axi_ddr_bid(m_axi_ddr_bid),
        .m_axi_ddr_bresp(m_axi_ddr_bresp),
        .m_axi_ddr_bvalid(m_axi_ddr_bvalid),
        .m_axi_ddr_bready(m_axi_ddr_bready),
        .m_axi_ddr_arid(m_axi_ddr_arid),
        .m_axi_ddr_araddr(m_axi_ddr_araddr),
        .m_axi_ddr_arlen(m_axi_ddr_arlen),
        .m_axi_ddr_arsize(m_axi_ddr_arsize),
        .m_axi_ddr_arburst(m_axi_ddr_arburst),
        .m_axi_ddr_arlock(m_axi_ddr_arlock),
        .m_axi_ddr_arcache(m_axi_ddr_arcache),
        .m_axi_ddr_arprot(m_axi_ddr_arprot),
        .m_axi_ddr_arqos(m_axi_ddr_arqos),
        .m_axi_ddr_arvalid(m_axi_ddr_arvalid),
        .m_axi_ddr_arready(m_axi_ddr_arready),
        .m_axi_ddr_rid(m_axi_ddr_rid),
        .m_axi_ddr_rdata(m_axi_ddr_rdata),
        .m_axi_ddr_rresp(m_axi_ddr_rresp),
        .m_axi_ddr_rlast(m_axi_ddr_rlast),
        .m_axi_ddr_rvalid(m_axi_ddr_rvalid),
        .m_axi_ddr_rready(m_axi_ddr_rready),

        .ddr_status(ddr_status)
    );

    assign cfg_mgmt_addr[18] = 1'b0;

endmodule

`resetall
