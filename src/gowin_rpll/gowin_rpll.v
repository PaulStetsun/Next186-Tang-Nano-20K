//Copyright (C)2014-2022 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//GOWIN Version: V1.9.8.03
//Part Number: GW2AR-LV18QN88C8/I7
//Device: GW2AR-18
//Device Version: C
//
// ADAPTED FOR TANG NANO 20K (was GW1NR-9C / Tang Nano 9K).
// IDIV_SEL/FBDIV_SEL/ODIV_SEL and the new CLKOUTP output are taken
// VERBATIM from a real, hardware-tested Gowin-generated rPLL for this
// exact device (GW2AR-LV18QN88C8/I7, Device Version C), found in
// github.com/nand2mario/nestang, src/pllr/gowin_pll_nes.v -- not hand-guessed. This yields CLKOUT = 27MHz * (11+1)/(4+1) / ... = 64.8MHz,
// deliberately LOWER than the original 9K's 72MHz (the sdram32.v/nestang
// SDRAM controller this project now uses is only rated to ~66.7MHz).
// CLKOUTP is a phase-shifted copy of CLKOUT. Phase/duty are STATIC
// parameters here; dynamic PSDA/DUTYDA inputs are intentionally disabled.
// used to drive O_sdram_clk with the correct setup/hold margin at the
// physical SDRAM pins.
//
// Note: PSDA_SEL="1000" (180-degree phase shift) matches the proven
// Sipeed Tang Nano 20K nestang reference design for SDRAM clock phase alignment,
// wired straight to the SDRAM's O_sdram_clk pin to compensate for clock-to-pin delay.
//
// clkoutd (÷4 via DYN_SDIV_SEL, giving ~16.2MHz) is kept for parity with
// the original design's clk50m signal; verify against actual usage in
// Next186_SoC.v if you change target frequencies.

module Gowin_rPLL (clkout, lock, clkoutd, clkoutd3, clkoutp, clkin, reset);

output clkout;
output lock;
output clkoutd;
output clkoutd3;
output clkoutp;
input clkin;
input reset;

wire clkoutd3_o;
wire gw_gnd;

assign gw_gnd = 1'b0;
assign clkoutd3 = clkoutd3_o;

rPLL rpll_inst (
    .CLKOUT(clkout),
    .LOCK(lock),
    .CLKOUTP(clkoutp),
    .CLKOUTD(clkoutd),
    .CLKOUTD3(clkoutd3_o),
    .RESET(reset),
    .RESET_P(gw_gnd),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .FBDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .IDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .PSDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DUTYDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FDLY({gw_gnd,gw_gnd,gw_gnd,gw_gnd})
);

defparam rpll_inst.FCLKIN = "27";
defparam rpll_inst.DYN_IDIV_SEL = "false";
defparam rpll_inst.IDIV_SEL = 4;
defparam rpll_inst.DYN_FBDIV_SEL = "false";
defparam rpll_inst.FBDIV_SEL = 11;
defparam rpll_inst.DYN_ODIV_SEL = "false";
defparam rpll_inst.ODIV_SEL = 8;
defparam rpll_inst.PSDA_SEL = "1000";
defparam rpll_inst.DYN_DA_EN = "false";
defparam rpll_inst.DUTYDA_SEL = "1000";
defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL = "internal";
defparam rpll_inst.CLKOUT_BYPASS = "false";
defparam rpll_inst.CLKOUTP_BYPASS = "false";
defparam rpll_inst.CLKOUTD_BYPASS = "false";
defparam rpll_inst.DYN_SDIV_SEL = 4;
defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
defparam rpll_inst.DEVICE = "GW2AR-18C";

endmodule //Gowin_rPLL
