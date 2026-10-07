//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: ddr_186.v
// Description: Part of the Next186 SoC PC project, main system, RAM interface
// Version 2.0
// Creation date: Apr2014
//
// Author: Nicolae Dumitrache 
// e-mail: ndumitrache@opencores.org
//
/////////////////////////////////////////////////////////////////////////////////
// 
// Copyright (C) 2012 Nicolae Dumitrache
// 
// This source file may be used and distributed without 
// restriction provided that this copyright statement is not 
// removed from the file and that any derivative work contains 
// the original copyright notice and the associated disclaimer.
// 
// This source file is free software; you can redistribute it 
// and/or modify it under the terms of the GNU Lesser General 
// Public License as published by the Free Software Foundation;
// either version 2.1 of the License, or (at your option) any 
// later version. 
// 
// This source is distributed in the hope that it will be 
// useful, but WITHOUT ANY WARRANTY; without even the implied 
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR 
// PURPOSE. See the GNU Lesser General Public License for more 
// details. 
// 
// You should have received a copy of the GNU Lesser General 
// Public License along with this source; if not, download it 
// from http://www.opencores.org/lgpl.shtml 
// 
///////////////////////////////////////////////////////////////////////////////////
// Additional Comments: 
//
// 25Apr2012 - added SD card SPI support
// 15May2012 - added PIT 8253 (sound + timer INT8)
// 24May2012 - added PIC 8259  
// 28May2012 - RS232 boot loader does not depend on CPU speed anymore (uses timer0)
//	01Feb2013 - ADD 8042 PS2 Keyboard & Mouse controller
// 27Feb2013 - ADD RTC
// 04Apr2013 - ADD NMI, port 3bc for 8 leds
//
// Feb2014 - ported for SDRAM, added USB host serial communication
// 		   - added video modes 0dh, 12h
//		   - support for ModeX
// Jul2017 - high speed COM (up to 115200*8)
// Aug2017 - added Line Compare Register
// Sep2017 - VGA barrel shifter, NMI on IRQ
// Oct2017 - added VGA VDE register, improved 400/480 lines configuration based on VDE
//////////////////////////////////////////////////////////////////////////////////

/* ----------------- implemented ports -------------------
0001 - BYTE write: bit01=ComSel (00=DCE, 01=EXT, 1x=HOST), bit2=Host reset, bit43=COM divider shift right bits
0001 - WORD write: bit0=auto cache flush
	  
0002 - 32 bit CPU data port R/W, lo first
0003 - 32 bit CPU command port W
		16'b00000cvvvvvvvvvv = set r/w pointer - 256 32bit integers, 1024 instructions. c=1 for code write, 0 for data read/write
		16'b100wwwvvvvvvvvvv = run ip - 1024 instructions, 3 bit data window offs
0004 - I2C interface: W= {xxxx,cccc,dddddddd}, R={dddddddd,xxxxxxxx}
0006 - WORD write: NMIonIORQ low port address. NMI if (IORQ and PORT_ADDR >= NMIonIORQ_LO and PORT_ADDR <= NMIonIORQ_HI)
0007 - WORD write: NMIonIORQ high port address

0021 - interrupt controller master data port. R/W interrupt mask, 1disabled/0enabled (bit0=timer, bit1=keyboard, bit4=COM1) 
00a1 - interrupt controller slave data port. R/W interrupt mask, 1disabled/0enabled (bit0=RTC, bit4=mouse) 

0040-0043 - PIT 8253 ports

0x60, 0x64 - 8042 keyboard/mouse data and cfg

0061 - bits1:0 speaker on/off (write only)

0070 - RTC (16bit write only counter value). RTC is incremented with 1Mhz and at set value sends INT70h, then restart from 0
		 When set, it restarts from 0. If the set value is 0, it will send INT70h only once, if it was not already 0
			
080h-08fh - memory map: bit9:0=64 Kbytes DDRAM segment index (up to 1024 segs = 64MB), mapped over 
								PORT[3:0] 80186 addressable segment
								
0200h-020fh - joystick port (GPIO) - pullup
		WORD/BYTE r/w: bits[15:8] = 0 for input, 1 for output, bits[7:0]=data

0378 - sound port: 8bit=Covox & DSS compatible, 16bit = stereo L+R - fifo sampled at 44100Hz
		 bit4 of port 03DA is 1 when the sound queue is full. If it is 0, the queue may accept up to 1152 stereo samples (L + R), so 2304 16bit writes.

0379 - parallel port control: bit6 = 1 when DSS queue is full

0388,0389,038A,038B - Adlib ports: 0388=bank1 addr, 0389=bank1 data, 038A=bank2 addr, 038B=bank2 data

03C0 - VGA mode 
		index 00h..0Fh  = EGA palette registers
		index 10h:
			bit0 = graphic(1)/text(0)
			bit3 = text mode flash enabled(1)
			bit4 = half mode (EGA)
			bit5 = ppm - pixel panning mode
			bit6 = vga mode 13h(1)
			bit7 = P54S - 1 to use color select 5-4 from reg 14h
		index 13h: bit[3:0] = hrz pan
		index 14h: bit[3:2] = color select 7-6, bit[1:0] = color select 5-4

03C4, 03C5 (Sequencer registers) - idx2[3:0] = write plane, idx4[3]=0 for planar (rw)

03C6 - DAC mask (rw)
03C7 - DAC read index (rw)
03C8 - DAC write index (rw)
03C9 - DAC color (rw)
03CB - font: write WORD = set index (8 bit), r/w BYTE = r/w font data

03CE, 03CF (Graphics registers) (rw)
	0: setres <= din[3:0];
	1: enable_setres <= din[3:0];
	2: color_compare <= din[3:0];
	3: logop <= din[4:3];
	4: rplane <= din[1:0];
	5: rwmode <= {din[3], din[1:0]};
	7: color_dont_care <= din[3:0];
	8: bitmask <= din[7:0]; (1=CPU, 0=latch)

03DA - read VGA status, bit0=1 on vblank or hblank, bit1=RS232in, bit2=i2cackerr, bit3=1 on vblank, bit4=sound queue full, bit5=DSP32 halt, bit6=i2cack, bit7=1 always, bit15:8=SD SPI byte read
		 write bit7=SD SPI MOSI bit, SPI CLK 0->1 (BYTE write only), bit8 = SD card chip select (WORD write only)
		 also reset the 3C0 port index flag

03B4, 03D4 - VGA CRT write index:  
										07h: bit1 = VDE8, bit4 = LCR8, bit6 = VDE9
										09h: bit6 = LCR9
										0Ah(bit 5 only): hide cursor
										0Ch: HI screen offset
										0Dh: LO screen offset
										0Eh: HI cursor pos
										0Fh: LO cursor pos
										12h: VDE[7:0]
										13h: scan line offset
										18h: Line Compare Register (LCR)
03B5, 03D5 - VGA CRT read/write data

03f8-03fb - COM1 ports
03fc-03fe - com0 ports(For.Debug)
03ff        User.Button
*/

`timescale 1ns / 1ps
//`define NoCPU

module system (
		 input 	CLK_50MHZ,
		 input clk_pixel,
		 output reg [5:0] VGA_R, VGA_G, VGA_B,
		 output wire      VGA_HSYNC, VGA_VSYNC, VGA_hblnk,
		 output frame_on,
		 input BTN_RESET,	// Reset
		 input BTN_NMI,		// NMI
		 input BTN_USER,	// USER
		 output [7:0]LED,	// HALT
		 output reg [7:0] DEBUG_STATUS,
		 output reg [20:0] DEBUG_IADDR, output reg [18:0] DEBUG_RAM_ADDR,
		 output reg [31:0] DEBUG_RAM_DOUT, output reg [31:0] DEBUG_INSTR_LO,
			 output reg [31:0] DEBUG_RAM_DIN, output reg [31:0] DEBUG_ROM_DOUT,
		 output reg [15:0] DEBUG_CPU_DIN, output reg DEBUG_IADDR_VALID, output reg DEBUG_RAM_VALID,
		 output wire [20:0] DEBUG_LIVE_IADDR, output wire [15:0] DEBUG_LAST_IO_PORT, output wire [15:0] DEBUG_LAST_IO_DATA, output wire DEBUG_LAST_IO_WR,
		 output wire [20:0] DEBUG_LAST_MEM_ADDR, output wire [31:0] DEBUG_LAST_MEM_DATA, output wire DEBUG_LAST_MEM_WR,
		 input  RS232_DCE_RXD, RS232_EXT_RXD,
		 output RS232_DCE_TXD, RS232_EXT_TXD,
		 input  RS232_HOST_RXD,
		 output RS232_HOST_TXD,
		 output reg RS232_HOST_RST,

		 // SDRAM(Internal connection, "magic" ports)
		 input  wire		sdram_clk,
		 input  wire		sdram_clk_p,
		 input  wire		pll_lock,
		 inout  wire [31:0]	IO_sdram_dq,
		 output wire [10:0]	O_sdram_addr,
		 output wire [1:0]	O_sdram_ba,
		 output wire		O_sdram_cs_n,
		 output wire		O_sdram_wen_n,
		 output wire		O_sdram_ras_n,
		 output wire		O_sdram_cas_n,
		 output wire		O_sdram_clk,
		 output wire		O_sdram_cke,
		 output wire [3:0]	O_sdram_dqm,

		 output reg  SD_n_CS = 1'b1,
		 output wire SD_DI,
		 output reg  SD_CK = 0,
		 input  wire SD_DO,
		 
		 output AUD_L, AUD_R,
	 	 inout PS2_CLK1, PS2_CLK2,
		 inout PS2_DATA1, PS2_DATA2,
		 
		 // USB HID injection from FPGA Companion (via top-level)
		 input       inject_kb_stb,
		 input [7:0] inject_kb_data,
		 input       inject_mouse_stb,
		 input [7:0] inject_mouse_data,

		 // USB SDC / Storage from FPGA Companion
		 input       mcu_sdc_strobe,
		 input       mcu_start,
		 input [7:0] mcu_dout,
		 output [7:0] mcu_sdc_din,
		 output      sdc_irq_n,
		 
		 //inout [7:0]GPIO,
		 output [7:0]GPIO,
		 output I2C_SCL,
		 inout I2C_SDA
    );

	// Forward declarations used by CPU/PIC wiring; keep them before first use.
	wire [7:0] PIC_IVECT;
	wire INT;
	wire I_KB;
	wire I_MOUSE;
	wire I_COM1 = 1'b0;
	wire [7:0] COM1_DOUT;
	wire sq_full;
	wire dss_full;
	wire [15:0] cpu32_data;
	wire cpu32_halt;
	wire [14:0] cache_hi_addr;
	wire [8:0] memmap;
	wire [8:0] memmap_mux;
	wire [7:0] i2cdout;
	wire i2cack;
	wire i2cackerr;
	wire [7:0] opl32_data;
	wire [3:0] seg_addr;
	wire vga_planar_seg = (seg_addr == 4'hA);
	initial SD_n_CS = 1'b1;

	// Disabled legacy peripheral blocks are intentionally kept inactive.
	// Drive their buses explicitly so synthesis has no floating internal nets.
	assign COM1_DOUT = 8'h00;
	assign cache_hi_addr = 15'h0000;
	assign i2cdout = 8'h00;
	assign i2cack = 1'b0;
	assign i2cackerr = 1'b0;
	assign I2C_SCL = 1'b1;
	
	wire [15:0]cntrl0_user_input_data;//i
	wire [1:0]sys_cmd_ack;
	wire sys_rd_data_valid;
	wire sys_wr_data_valid;
	wire ps_calib; // psram init.end   
	wire [15:0]sys_DOUT;	// sdr data out
	wire [31:0] DOUT;
	wire [15:0]CPU_DOUT;
	wire [15:0]PORT_ADDR;
	wire [31:0] DRAM_dout;
	wire [20:0] ADDR;
	wire IORQ;
	wire WR;
	wire INTA;
	wire WORD;
	wire [3:0] RAM_WMASK;
	wire raw_hsync, raw_vsync, raw_hblnk, raw_vblnk;
	wire hblnk = raw_hblnk;
	wire vblnk = raw_vblnk;
	wire [9:0]hcount;
	wire [9:0]vcount;
	assign VGA_HSYNC = raw_hsync;
	assign VGA_VSYNC = raw_vsync;
	assign VGA_hblnk = raw_hblnk || raw_vblnk;
	reg [3:0]vga_hrzpan = 0;
	wire [3:0]vga_hrzpan_req;
	wire [9:0]hcount_pan = hcount + vga_hrzpan - 10'd17;
	reg FifoStart = 1'b0;	// fifo not empty
	wire displ_on = !(hblnk | vblnk | !FifoStart_pix);
	wire [17:0]DAC_COLOR;
	wire [9:0]fifo_wr_used_words;
	reg [8:0] vga_fifo_fill_count; // diagnostic write-side counter; not used for FIFO control
	wire AlmostFull;
	wire AlmostEmpty;
	wire fifo_empty;

	// --- Diagnostic only: does the video FIFO actually starve while we're
	// live-displaying pixels? This never influenced any timing/control path
	// before, it's purely observational, latched once and held so a single
	// glimpse (e.g. reading the LED) is enough to catch an event that may
	// only last one pixel clock. Cleared only by power-on reset (preset).
	reg vga_underrun_latched = 1'b0;
	always @(posedge clk_pixel) begin
		if (preset)
			vga_underrun_latched <= 1'b0;
		else if (displ_on && (fifo_empty || AlmostEmpty))
			vga_underrun_latched <= 1'b1;
	end

	wire clk_cpu;
	wire clk_dsp;
	wire CPU_CE;	// CPU clock enable
	wire CE;
	wire CE_186;
	wire CPU_DBG_IFETCH, CPU_DBG_RAM_MREQ, CPU_DBG_CE186;
wire [20:0] CPU_DBG_IADDR; wire [18:0] CPU_DBG_RAM_ADDR; wire [31:0] CPU_DBG_RAM_DOUT; wire [31:0] CPU_DBG_RAM_DIN; wire [47:0] CPU_DBG_INSTR; wire [15:0] CPU_DBG_CPU_DIN;
wire CPU_DBG_BOOT_CS; wire CPU_DBG_BIOS_CS; wire [31:0] CPU_DBG_ROM_DOUT;
wire [7:0] CPU_DBG_SDRAM_STATE;
	wire ddr_rd = 1'b0;
	wire ddr_wr = 1'b0;
	wire TIMER_OE = PORT_ADDR[15:2] == 14'b00000000010000;	//   40h..43h
	wire VGA_DAC_OE = PORT_ADDR[15:4] == 12'h03c && PORT_ADDR[3:0] <= 4'h9; // 3c0h..3c9h	
	wire LED_PORT = PORT_ADDR[15:0] == 16'h03bc;
	wire SPEAKER_PORT = PORT_ADDR[15:0] == 16'h0061;
	wire MEMORY_MAP = PORT_ADDR[15:4] == 12'h008;
	wire VGA_FONT_OE = PORT_ADDR[15:0] == 16'h03cb;
	wire AUX_OE = PORT_ADDR[15:0] == 16'h0001;
	wire I2C_SELECT = PORT_ADDR[15:0] == 16'h0004;
	wire INPUT_STATUS_OE = PORT_ADDR[15:0] == 16'h03da;
	wire VGA_CRT_OE = (PORT_ADDR[15:1] == 15'b000000111011010) || (PORT_ADDR[15:1] == 15'b000000111101010); // 3b4h, 3b5h, 3d4h, 3d5h
	wire RTC_SELECT = PORT_ADDR[15:0] == 16'h0070;
	wire VGA_SC = PORT_ADDR[15:1] == (16'h03c4 >> 1); // 3c4h, 3c5h
	wire VGA_GC = PORT_ADDR[15:1] == (16'h03ce >> 1); // 3ceh, 3cfh
	wire VGA_CGA_OE = PORT_ADDR[15:1] == (16'h03d8 >> 1); // 3d8h, 3d9h - CGA mode/colour select
	wire PIC_OE = PORT_ADDR[15:8] == 8'h00 && PORT_ADDR[6:0] == 7'b0100001;	// 21h, a1h
	wire KB_OE = PORT_ADDR[15:4] == 12'h006 && {PORT_ADDR[3], PORT_ADDR[1:0]} == 3'b000; // 60h, 64h
	wire JOYSTICK = PORT_ADDR[15:4] == 12'h020; // 0x200-0x20f
	wire PARALLEL_PORT = PORT_ADDR[15:0] == 16'h0378;
	wire PARALLEL_PORT_CTL = PORT_ADDR[15:0] == 16'h0379;
	wire USB_STORAGE_OE = PORT_ADDR[15:3] == (16'h0270 >> 3); // 0x270 - 0x277
	wire [15:0] usb_storage_dout;
	wire usb_storage_oe;
	wire CPU32_PORT = PORT_ADDR[15:1] == (16'h0002 >> 1); // port 1 for data and 3 for instructions
	wire COM0_PORT = PORT_ADDR[15:2] == (16'h03fc >> 2);
	wire COM1_PORT = PORT_ADDR[15:2] == (16'h03f8 >> 2);
	wire OPL3_PORT = PORT_ADDR[15:2] == (16'h0388 >> 2); // 0x388 .. 0x38b
	wire NMI_IORQ_PORT = PORT_ADDR[15:1] == (16'h0006 >> 1); // 6, 7
 	wire [7:0]VGA_DAC_DATA;
	wire [7:0]VGA_CRT_DATA;
	wire [7:0]VGA_CGA_DATA;
	wire [7:0]VGA_SC_DATA;
	wire [7:0]VGA_GC_DATA;
	wire [15:0]PORT_IN;
	wire [7:0]TIMER_DOUT;
	wire [7:0]KB_DOUT;
	wire [7:0]PIC_DOUT;
	wire [7:0]COM0_DOUT;
	wire HALT;
	wire CLK14745600; // RS232 clk
 	wire CLK44100x256;
		
	reg [1:0]cntrl0_user_command_register = 0;
	reg [16:0]vga_ddr_row_col = 0; // video buffer offset (multiple of 4)
	reg s_prog_full;
	reg s_prog_empty;
	reg s_ddr_rd = 1'b0;
	reg s_ddr_wr = 1'b0;
	reg crw = 0;	// 1=cache read window
	reg s_RS232_DCE_RXD;
	reg s_RS232_HOST_RXD;
	reg [18:0]rstcount = 0;
	reg [18:0]s_displ_on = 0;	// clk_25 delayed displ_on
	reg [2:0]vga13 = 0; 		// 1 for mode 13h
	// FIX: Initialize vgatext to 3'b111 (text mode by default).
	// VGA_DAC initializes vgatext=1'b1 and synchronizers vgatextreq_mctr1/mctr2 are 1'b1.
	// Initializing system.v's vgatext to 0 caused a circular deadlock:
	// vga_lnend evaluated to 21 instead of 6, waiting for 168 dwords that never arrive
	// (FIFO fills at 40 dwords in text mode), so s_vga_endscanline never fired,
	// vga_ddr_row_count never incremented, s_vga_endframe never fired, and
	// vgatext[0] could never update from vgatextreq_mctr2!
	reg [2:0]vgatext = 3'b111;  		// 1 for text mode
	// CGA (modes 4/5/6) mode flags, same 3-stage pipeline as vga13/planar/half:
	// [0] = SDRAM/fetch domain, [1] = pixel domain, [2] = raster-timing domain
	reg [2:0]cga4 = 0;	// 320x200x4, 2 bits/pixel
	reg [2:0]cga2 = 0;	// 640x200x2, 1 bit/pixel
	wire [2:0]cga = cga4 | cga2;
	reg [2:0]v240 = 0;
	reg [2:0]planar = 0;
	reg [2:0]half = 0;
	reg [0:0]repln_graph = 0;
	wire vgaflash;
	reg flashbit = 0;
	reg [5:0]flashcount = 0;
	wire [5:0]char_row = vcount[8:3] >> !half[2];
	wire [3:0]char_ln = {(vcount[3] & !half[1]), vcount[2:0]};
	wire [11:0]charcount = {char_row, 4'b0000} + {char_row, 6'b000000} + hcount_pan[9:3];
	wire [31:0]fifo_dout32;
	wire [15:0]fifo_dout = (vgatext[1] ? hcount_pan[3] : vga13[1] ? hcount_pan[2] : hcount_pan[1]) ? fifo_dout32[31:16] : fifo_dout32[15:0];

	reg [8:0]vga_ddr_row_count = 0;
	reg [2:0]max_read;
	reg [4:0]col_counter;
	wire vga_end_frame = vga_ddr_row_count == (v240[0] ? 479 : 399);
	reg [3:0]vga_repln_count = 0; // repeat line counter
	wire [3:0]vga_repln = vgatext[0] ? (half[0] ? 7 : 15) : cga[0] ? 4'd1 : {3'b000, repln_graph[0]};
	reg [7:0]vga_lnbytecount = 0; // line byte count (multiple of 4)
	// CGA needs 80 bytes = 20 dwords per displayed line; the fetch granularity is
	// 8 dwords, so 24 are fetched and the 4 surplus dwords are consumed by the
	// trailing prefetch pops (see exline below) - exactly like every other mode.
	wire [4:0]vga_lnend = cga[0] ? 5'd3 : (vgatext[0] | half[0]) ? 6 : (vga13[0] | planar[0]) ? 11 : 21; // multiple of 32 (SDRAM resolution = 32)
	reg [11:0]vga_font_counter = 0;
	reg [7:0]vga_attr;
	reg [4:0]RTCDIV25 = 0;
	reg [1:0]RTCSYNC = 0;
	reg [15:0]RTC = 0;
	reg [15:0]RTCSET = 0;
	wire RTCEND = RTC == RTCSET;
	wire RTCDIVEND = RTCDIV25 == 24;

	// ---------------------------------------------------------------------
	// Explicit CDC bridges between the 64.8 MHz SDRAM/control clock domain,
	// the 16.2 MHz CPU clock domain, and the 25.2 MHz pixel clock domain.
	// These are intentionally 2-stage synchronizers; every signal below is
	// either a slow configuration/status value or a level/pulse much wider
	// than the destination clock period.
	// ---------------------------------------------------------------------
	reg FifoStart_pix1 = 1'b0, FifoStart_pix2 = 1'b0;
	reg vgaflash_pix1 = 1'b0, vgaflash_pix2 = 1'b0;
	reg ppm_pix1 = 1'b0, ppm_pix2 = 1'b0;
	reg [3:0] vga_hrzpan_req_pix1 = 4'd0, vga_hrzpan_req_pix2 = 4'd0;
	reg oncursor_pix1 = 1'b0, oncursor_pix2 = 1'b0;
	reg [4:0] crs_start_pix1 = 5'd0, crs_start_pix2 = 5'd0;
	reg [4:0] crs_end_pix1 = 5'd0, crs_end_pix2 = 5'd0;
	reg [11:0] cursorpos_pix1 = 12'd0, cursorpos_pix2 = 12'd0;
	reg [9:0] lcr_pix1 = 10'h3ff, lcr_pix2 = 10'h3ff;
	reg [9:0] vde_pix1 = 10'd399, vde_pix2 = 10'd399;

	reg VGA_VSYNC_mctr1 = 1'b0, VGA_VSYNC_mctr2 = 1'b0;
	reg vsync_cpu1 = 1'b0, vsync_cpu2 = 1'b0;
	reg vblnk_cpu1 = 1'b0, vblnk_cpu2 = 1'b0;
	reg rtc_tick_cpu1 = 1'b0, rtc_tick_cpu2 = 1'b0;

	reg [15:0] scraddr_mctr1 = 16'd0, scraddr_mctr2 = 16'd0;
	reg [9:0] lcr_mctr1 = 10'd0, lcr_mctr2 = 10'd0;
	reg [9:0] vde_mctr1 = 10'd399, vde_mctr2 = 10'd399;
	reg [7:0] vga_offset_mctr1 = 8'd0, vga_offset_mctr2 = 8'd0;
	reg vgatextreq_mctr1 = 1'b1, vgatextreq_mctr2 = 1'b1;
	reg vga13req_mctr1 = 1'b1, vga13req_mctr2 = 1'b1;
	reg planarreq_mctr1 = 1'b0, planarreq_mctr2 = 1'b0;
	reg cga4req_mctr1 = 1'b0, cga4req_mctr2 = 1'b0;
	reg cga2req_mctr1 = 1'b0, cga2req_mctr2 = 1'b0;
	reg halfreq_mctr1 = 1'b0, halfreq_mctr2 = 1'b0;
	reg replnreq_mctr1 = 1'b0, replnreq_mctr2 = 1'b0;

	always @(posedge clk_pixel) begin
		FifoStart_pix1 <= FifoStart;
		FifoStart_pix2 <= FifoStart_pix1;
		vgaflash_pix1 <= vgaflash;
		vgaflash_pix2 <= vgaflash_pix1;
		ppm_pix1 <= ppm;
		ppm_pix2 <= ppm_pix1;
		vga_hrzpan_req_pix1 <= vga_hrzpan_req;
		vga_hrzpan_req_pix2 <= vga_hrzpan_req_pix1;
		oncursor_pix1 <= oncursor;
		oncursor_pix2 <= oncursor_pix1;
		crs_start_pix1 <= crs[0];
		crs_start_pix2 <= crs_start_pix1;
		crs_end_pix1 <= crs[1];
		crs_end_pix2 <= crs_end_pix1;
		cursorpos_pix1 <= cursorpos;
		cursorpos_pix2 <= cursorpos_pix1;
		lcr_pix1 <= lcr;
		lcr_pix2 <= lcr_pix1;
		vde_pix1 <= vde;
		vde_pix2 <= vde_pix1;
	end

	// Pixel-domain VSYNC is asynchronous to clk_mctr and therefore remains a
	// conventional two-flop synchronizer on the positive edge.
	always @(posedge clk_mctr) begin
		VGA_VSYNC_mctr1 <= VGA_VSYNC;
		VGA_VSYNC_mctr2 <= VGA_VSYNC_mctr1;
	end

	// CPU -> clk_mctr transfer: clk_mctr is 4x clk_cpu and derived from the
	// same PLL. Sampling the first stage on the falling edge gives a deliberate
	// half-cycle of hold margin, while the second stage returns to the normal
	// positive-edge domain used by the framebuffer state machine.
	always @(negedge clk_mctr) begin
		scraddr_mctr1 <= scraddr;
		lcr_mctr1 <= lcr;
		vde_mctr1 <= vde;
		vga_offset_mctr1 <= vga_offset;
		vgatextreq_mctr1 <= vgatextreq;
		vga13req_mctr1 <= vga13req;
		planarreq_mctr1 <= planarreq;
		cga4req_mctr1 <= cga4req;
		cga2req_mctr1 <= cga2req;
		halfreq_mctr1 <= halfreq;
		replnreq_mctr1 <= replnreq;
	end

	always @(posedge clk_mctr) begin
		scraddr_mctr2 <= scraddr_mctr1;
		lcr_mctr2 <= lcr_mctr1;
		vde_mctr2 <= vde_mctr1;
		vga_offset_mctr2 <= vga_offset_mctr1;
		vgatextreq_mctr2 <= vgatextreq_mctr1;
		vga13req_mctr2 <= vga13req_mctr1;
		planarreq_mctr2 <= planarreq_mctr1;
		cga4req_mctr2 <= cga4req_mctr1;
		cga2req_mctr2 <= cga2req_mctr1;
		halfreq_mctr2 <= halfreq_mctr1;
		replnreq_mctr2 <= replnreq_mctr1;
	end

	always @(posedge clk_cpu) begin
		vsync_cpu1 <= raw_vsync;
		vsync_cpu2 <= vsync_cpu1;
		vblnk_cpu1 <= vblnk;
		vblnk_cpu2 <= vblnk_cpu1;
		rtc_tick_cpu1 <= RTCDIVEND;
		rtc_tick_cpu2 <= rtc_tick_cpu1;
	end

	wire FifoStart_pix = FifoStart_pix2;
	wire vgaflash_pix = vgaflash_pix2;
	wire ppm_pix = ppm_pix2;
	wire [3:0] vga_hrzpan_req_pix = vga_hrzpan_req_pix2;
	wire oncursor_pix = oncursor_pix2;
	wire [4:0] crs_start_pix = crs_start_pix2;
	wire [4:0] crs_end_pix = crs_end_pix2;
	wire [11:0] cursorpos_pix = cursorpos_pix2;
	wire [9:0] lcr_pix = lcr_pix2;
	wire [9:0] vde_pix = vde_pix2;
	wire [7:0]font_dout;
	wire [7:0]VGA_FONT_DATA;
	wire vgatextreq;
	wire vga13req;
	reg [9:0] lcr_f = 10'h3ff;
	reg [7:0] offset_f = 8'h28;
	reg [9:0] vde_pixf = 10'd399;
	reg [9:0] lcr_pixf = 10'h3ff;
	wire planarreq;
	wire cga4req;
	wire cga2req;
	wire replnreq;
	wire halfreq;
	wire oncursor;
	wire [4:0]crs[1:0];
	wire [11:0]cursorpos;
	wire [15:0]scraddr;
	reg flash_on;
	reg speaker_on = 1'b0;
	reg [9:0]rNMI = 0;
	wire [2:0]shift = half[1] ? ~hcount_pan[3:1] : ~hcount_pan[2:0];
	wire [2:0]pxindex = -hcount_pan[2:0];
	// ---- CGA pixel extraction -------------------------------------------
	wire [7:0] cga_byte = (hcount_pan[4:3] == 2'b00) ? fifo_dout32[7:0] :
	                      (hcount_pan[4:3] == 2'b01) ? fifo_dout32[15:8] :
	                      (hcount_pan[4:3] == 2'b10) ? fifo_dout32[23:16] :
	                                                   fifo_dout32[31:24];
	wire [1:0] cga_pixel = cga2[1] ? {cga_byte[~hcount_pan[2:0]], 1'b0} :
	                       (hcount_pan[2:1] == 2'b00) ? cga_byte[7:6] :
	                       (hcount_pan[2:1] == 2'b01) ? cga_byte[5:4] :
	                       (hcount_pan[2:1] == 2'b10) ? cga_byte[3:2] :
	                                                    cga_byte[1:0];
	wire [3:0]cga_color;
	wire [3:0]EGA_MUX = vgatext[1] ? ((font_dout[pxindex] ^ flash_on) ? vga_attr[3:0] : {vga_attr[7] & ~vgaflash_pix, vga_attr[6:4]}) :
							  {fifo_dout32[{2'b11, shift}], fifo_dout32[{2'b10, shift}], fifo_dout32[{2'b01, shift}], fifo_dout32[{2'b00, shift}]};
	wire [7:0]VGA_INDEX;
	reg [3:0]exline = 4'b0000; // extra 8 dwords (32 bytes) for screen panning
	wire vrdon = s_displ_on[~vga_hrzpan];
	wire vrden = (vrdon || exline[3]) && (cga[1] ? &hcount_pan[4:0] : (vgatext[1] | half[1]) ? &hcount_pan[3:0] : (vga13[1] | planar[1]) ? &hcount_pan[2:0] : &hcount_pan[1:0]);
	reg s_vga_endline;
	reg s_vga_endscanline = 1'b0;
	reg s_vga_endframe;
	reg [23:0]sdraddr;
	// Translate legacy 9K VGA framebuffer offsets into the 20K SDRAM word address space.
	// Text: 0x8000 legacy offset -> 0x2E000 (B8000 byte address / 4).
	// Mode 13h: 0xE000 legacy offset -> 0x28000 (A0000 byte address / 4).
	wire [3:0]vga_wplane;
	wire [1:0]vga_rplane;
	wire [7:0]vga_bitmask;	// write 1=CPU, 0=VGA latch
	wire [2:0]vga_rwmode;
	wire [3:0]vga_setres;
	wire [3:0]vga_enable_setres;
	wire [1:0]vga_logop;
	wire [3:0]vga_color_compare;
	wire [3:0]vga_color_dont_care;
	wire [2:0]vga_rotate_count;
	wire [7:0]vga_offset;
	reg [2:0]auto_flush = 3'b000;
	wire ppm; 			// pixel panning mode
	wire [9:0]lcr; 		// line compare register
	wire [9:0]vde;		// vertical display end
	wire sdon = s_displ_on[17+vgatext[1]] & (vcount <= vde_pixf);
	wire preset = BTN_RESET || ~rstcount[18];

// Com interface
	reg [1:0]ComSel = 2'b00; // 00:COM1=RS232_DCE, 01: COM1=RS232_EXT, 1x: COM1=RS232_HOST
	//wire RX = ComSel[1] ? RS232_HOST_RXD : ComSel[0] ? RS232_EXT_RXD : RS232_DCE_RXD;	
	wire RX = RS232_DCE_RXD;	
	wire TX;
	//assign RS232_DCE_TXD = ComSel[1:0] == 2'b00 ? TX : 1'b1;
	assign RS232_DCE_TXD = TX;
	assign RS232_EXT_TXD = ComSel[1:0] == 2'b01 ? TX : 1'b1;
	assign RS232_HOST_TXD = ComSel[1] ? TX : 1'b1;
	reg [1:0]COMBRShift = 2'b00; 
	
//// SD interface
//	reg [7:0]SDI;
//	assign SD_DI = CPU_DOUT[7];

// GPIO interface	// Output only IO.Adrd:0x200-0x20f(WORD)
	reg [7:0]GPIOState = 8'h00;
	reg [7:0]GPIOData;
	reg [7:0]GPIODout = 8'h00;
	assign GPIO = GPIODout;

// I2C interface
	reg [11:0]i2c_cd = 0;
	
// opl3 interface
    wire [15:0]opl3left;
    wire [15:0]opl3right;
    wire stb44100;

// NMI on IORQ
	reg [15:0]NMIonIORQ_LO = 16'h0001;
	reg [15:0]NMIonIORQ_HI = 16'h0000;

	assign LED = {vga_underrun_latched, !cpu32_halt, AUD_L, AUD_R, planarreq, |sys_cmd_ack, ~SD_n_CS, HALT};
	assign frame_on = s_displ_on[16+vgatext[1]];

	// ---------------------------------------------------------------------
	// Next186 64-KB segment map.  The original design uses sixteen I/O
	// ports (80h..8Fh) to select a physical 64-KB SDRAM segment for each
	// 20/21-bit CPU address segment.  The BIOS relies on this immediately
	// at boot: OUT 8Ch,0015h maps C000:0000..C000:FFFF to physical segment
	// 15h, where it shadows the F000 ROM.  Without this block, BIOS shadow
	// copies land at the wrong SDRAM address and the subsequent ROM handoff
	// cannot execute correctly.
	//
	// The VGA/cache legacy path no longer owns this map, but memmap_mux is
	// still provided from the same table for compatibility and is sampled
	// only when a real memory request is accepted by mem_controller.
	// ---------------------------------------------------------------------
	seg_map u_seg_map (
		.CLK     (clk_cpu),
		.RST     (preset),
		.cpuaddr (PORT_ADDR[3:0]),
		.cpurdata(memmap),
		.cpuwdata(CPU_DOUT[8:0]),
		.memaddr (ADDR[20:16]),
		.memdata (memmap_mux),
		.WE      (MEMORY_MAP && IORQ && CPU_CE && WR && WORD)
	);

	// ---------------------------------------------------------------------
	// Hardware LIM EMS 4.0/3.2 Banking Controller
	// Ports 0x0260..0x026F (Page mapping registers, control & status)
	// ---------------------------------------------------------------------
	wire [15:0] ems_port_dout;
	wire        ems_port_oe;
	wire        ems_flush;
	wire [20:0] cpu_phys_dword;
	wire        is_ems;

	ems_map u_ems_map (
		.CLK            (clk_cpu),
		.RST            (preset),
		.PORT_ADDR      (PORT_ADDR),
		.CPU_DOUT       (CPU_DOUT),
		.IORQ           (IORQ),
		.WR             (WR),
		.WORD           (WORD),
		.CPU_CE         (CPU_CE),
		.PORT_DOUT      (ems_port_dout),
		.PORT_OE        (ems_port_oe),
		.ems_flush      (ems_flush),
		.ADDR           (ADDR),
		.memmap_mux     (memmap_mux[6:0]),
		.cpu_phys_dword (cpu_phys_dword),
		.is_ems         (is_ems)
	);

	assign PORT_IN[15:8] = 
		({8{usb_storage_oe}} & usb_storage_dout[15:8]) |
		({8{ems_port_oe}} & ems_port_dout[15:8]) |
		({8{MEMORY_MAP}} & {7'b0000000, memmap[8]}) |
		({8{INPUT_STATUS_OE}} & SDI) |
		({8{CPU32_PORT}} & cpu32_data[15:8]) | 
		({8{JOYSTICK}} & GPIOState) |
		({8{I2C_SELECT}} & i2cdout);

	assign PORT_IN[7:0] = //INPUT_STATUS_OE ? {2'b1x, cpu32_halt, sq_full, vblnk, s_RS232_HOST_RXD, s_RS232_DCE_RXD, hblnk | vblnk} : CPU32_PORT ? cpu32_data[7:0] : slowportdata;
							 ({8{usb_storage_oe}} & usb_storage_dout[7:0]) |
							 ({8{ems_port_oe}} & ems_port_dout[7:0]) |
							 ({8{VGA_DAC_OE}} & VGA_DAC_DATA) |
							 ({8{VGA_FONT_OE}}& VGA_FONT_DATA) |
							 ({8{KB_OE}} & KB_DOUT) |
							 ({8{INPUT_STATUS_OE}} & {1'b1, i2cack, cpu32_halt, sq_full, vsync_cpu2, i2cackerr, s_RS232_DCE_RXD, hblnk | vblnk}) | 
							 ({8{VGA_CRT_OE}} & VGA_CRT_DATA) | 
							 ({8{VGA_CGA_OE}} & VGA_CGA_DATA) |
							 ({8{MEMORY_MAP}} & {memmap[7:0]}) |
							 ({8{TIMER_OE}} & TIMER_DOUT) |
							 ({8{PIC_OE}} & PIC_DOUT) |
							 ({8{VGA_SC}} & VGA_SC_DATA) |
							 ({8{VGA_GC}} & VGA_GC_DATA) |
							 ({8{JOYSTICK}} & GPIOData) |
							 ({8{PARALLEL_PORT_CTL}} & {1'b1, dss_full, 6'b000000}) |
							 ({8{CPU32_PORT}} & cpu32_data[7:0]) | 
							 ({8{COM0_PORT}} & COM0_DOUT) | 
							 ({8{COM1_PORT}} & COM1_DOUT) | 
							 ({8{OPL3_PORT}} & opl32_data) ;

	//dcm dcm_system ( .inclk0(CLK_50MHZ), .c0(clk_25), .c1(clk_sdr), .c2(sdr_CLK_out), .c3(CLK44100x256), .c4(CLK14745600) ); 
	//dcm_cpu dcm_cpu_inst ( .inclk0(CLK_50MHZ), .c0(clk_cpu), .c1(clk_dsp) );
	reg [31:0] aud_acc = 32'd0;
	reg clk_aud = 1'b0;
	always @(posedge sdram_clk) begin
		aud_acc <= aud_acc + 32'h2C99D3DB;
		clk_aud <= aud_acc[31];
	end
	assign CLK44100x256 = clk_aud;
	assign CLK14745600  = clk_aud;
	assign clk_cpu = CLK_50MHZ;
	assign clk_dsp = CLK_50MHZ;
	reg [23:0] debug_heartbeat;
	reg cpu_mreq_seen;
	reg cpu_ifetch_seen;
	reg cpu_ram_mreq_seen;
	reg cpu_ce186_seen;
	reg vga_dma_seen;
	reg [10:0] vga_fifo_highwater;
	reg debug_first_ifetch_latched;
	reg debug_first_ramreq_latched;
	reg debug_first_data_latched;
	always @ (posedge CLK_50MHZ) begin
		if (preset) begin
			debug_heartbeat <= 24'd0;
			cpu_mreq_seen <= 1'b0;
			cpu_ifetch_seen <= 1'b0;
			cpu_ram_mreq_seen <= 1'b0;
			cpu_ce186_seen <= 1'b0;
			debug_first_ifetch_latched <= 1'b0;
			debug_first_ramreq_latched <= 1'b0;
			debug_first_data_latched <= 1'b0;
			DEBUG_IADDR <= 21'd0;
			DEBUG_RAM_ADDR <= 19'd0;
			DEBUG_RAM_DOUT <= 32'd0;
			DEBUG_RAM_DIN <= 32'd0;
			DEBUG_ROM_DOUT <= 32'd0;
			DEBUG_INSTR_LO <= 32'd0;
			DEBUG_CPU_DIN <= 16'd0;
			DEBUG_IADDR_VALID <= 1'b0;
			DEBUG_RAM_VALID <= 1'b0;
		end else begin
			debug_heartbeat <= debug_heartbeat + 24'd1;
			if (CPU_CE && MREQ) cpu_mreq_seen <= 1'b1;
			if (CPU_DBG_IFETCH) cpu_ifetch_seen <= 1'b1;
			if (CPU_DBG_RAM_MREQ) cpu_ram_mreq_seen <= 1'b1;
			if (CPU_DBG_CE186) cpu_ce186_seen <= 1'b1;
			if (CPU_DBG_BOOT_CS || CPU_DBG_BIOS_CS) begin
				DEBUG_ROM_DOUT <= CPU_DBG_ROM_DOUT;
			end
			if (CPU_DBG_RAM_MREQ && !debug_first_ramreq_latched) begin
				DEBUG_RAM_DIN <= CPU_DBG_RAM_DIN;
			end
			if (CPU_DBG_IFETCH && !debug_first_ifetch_latched) begin
				debug_first_ifetch_latched <= 1'b1;
				DEBUG_IADDR <= CPU_DBG_IADDR;
				DEBUG_INSTR_LO <= CPU_DBG_INSTR[31:0];
				DEBUG_IADDR_VALID <= 1'b1;
			end
			if (CPU_DBG_RAM_MREQ && !debug_first_ramreq_latched) begin
				debug_first_ramreq_latched <= 1'b1;
				DEBUG_RAM_ADDR <= CPU_DBG_RAM_ADDR;
			end
			if (sys_rd_data_valid && !debug_first_data_latched) begin
				debug_first_data_latched <= 1'b1;
				DEBUG_RAM_DOUT <= CPU_DBG_RAM_DOUT;
				DEBUG_CPU_DIN <= CPU_DBG_CPU_DIN;
				DEBUG_RAM_VALID <= 1'b1;
			end
		end
	end

	// Latch whether the VGA read path has ever produced a valid word.
	always @ (posedge clk_mctr) begin
		if (preset) begin
			vga_dma_seen <= 1'b0;
			vga_fifo_highwater <= 11'd0;
		end else begin
			if (sys_rd_data_valid) vga_dma_seen <= 1'b1;
			if (fifo_wr_used_words > vga_fifo_highwater)
				vga_fifo_highwater <= fifo_wr_used_words;
		end
	end

	// Bring-up status bits for the HDMI diagnostic screen:
	// bit0 = !preset (CPU/system out of reset)
	// bit1 = SDRAM phase calibration complete
	// bit2 = VGA FIFO started
	// bit3 = CPU HALT
	// bit4 = CPU_CE
	// bit5 = memory CE
	// bit6 = CPU memory request observed (latched)
	// bit7 = VGA DMA word observed (latched)
	reg [20:0] debug_live_iaddr_r;
	reg [15:0] debug_last_io_port_r, debug_last_io_data_r;
	reg debug_last_io_wr_r;
	reg [20:0] debug_last_mem_addr_r;
	reg [31:0] debug_last_mem_data_r;
	reg debug_last_mem_wr_r;

	always @(posedge clk_cpu) begin
		if (preset) begin
			debug_live_iaddr_r <= 21'd0;
			debug_last_io_port_r <= 16'd0;
			debug_last_io_data_r <= 16'd0;
			debug_last_io_wr_r <= 1'b0;
			debug_last_mem_addr_r <= 21'd0;
			debug_last_mem_data_r <= 32'd0;
			debug_last_mem_wr_r <= 1'b0;
		end else begin
			debug_live_iaddr_r <= CPU_DBG_IADDR;
			if (IORQ && CPU_CE) begin
				debug_last_io_port_r <= PORT_ADDR;
				debug_last_io_data_r <= CPU_DOUT;
				debug_last_io_wr_r <= WR;
			end
			if (MREQ && CPU_CE) begin
				debug_last_mem_addr_r <= ADDR;
				debug_last_mem_data_r <= WR ? DOUT : DRAM_dout;
				debug_last_mem_wr_r <= WR;
			end
		end
	end
	assign DEBUG_LIVE_IADDR = debug_live_iaddr_r;
	assign DEBUG_LAST_IO_PORT = debug_last_io_port_r;
	assign DEBUG_LAST_IO_DATA = debug_last_io_data_r;
	assign DEBUG_LAST_IO_WR = debug_last_io_wr_r;
	assign DEBUG_LAST_MEM_ADDR = debug_last_mem_addr_r;
	assign DEBUG_LAST_MEM_DATA = debug_last_mem_data_r;
	assign DEBUG_LAST_MEM_WR = debug_last_mem_wr_r;

	always @(*) begin
		DEBUG_STATUS = 8'b0;
		DEBUG_STATUS[0] = !preset;
		DEBUG_STATUS[1] = ps_calib;
		DEBUG_STATUS[2] = FifoStart;
		DEBUG_STATUS[3] = HALT;
		DEBUG_STATUS[4] = CPU_CE;
		DEBUG_STATUS[5] = CE;
		DEBUG_STATUS[6] = cpu_ifetch_seen;
		DEBUG_STATUS[7] = cpu_ram_mreq_seen;
	end

`ifndef NoCPU
	wire cpu_real_flush;
	unit186 CPUUnit
	(
		 .CPU_FLUSH_OUT(cpu_real_flush),
		 .INPORT(INTA ? {8'h00, PIC_IVECT} : PORT_IN), 
		 .DIN(DRAM_dout), 
		 .CPU_DOUT(CPU_DOUT),
		 .PORT_ADDR(PORT_ADDR),
		 .SEG_ADDR(seg_addr),
		 .DOUT(DOUT), 
		 .ADDR(ADDR), 
		 .WMASK(RAM_WMASK), 
		 .CLK(clk_cpu), 
		 .CE(CE), 
		 .CPU_CE(CPU_CE),
		 .CE_186(CE_186),
		 .INTR(INT), 
		 .NMI(rNMI[9] || (CPU_CE && IORQ && PORT_ADDR >= NMIonIORQ_LO && PORT_ADDR <= NMIonIORQ_HI)), 
		 .RST(preset), 
		 .INTA(INTA), 
		 .LOCK(LOCK), 
		 .HALT(HALT), 
		 .MREQ(MREQ),
		 .DEBUG_IFETCH(CPU_DBG_IFETCH),
		 .DEBUG_RAM_MREQ(CPU_DBG_RAM_MREQ),
		 .DEBUG_CE186(CPU_DBG_CE186),
		 .DEBUG_IADDR(CPU_DBG_IADDR),
		 .DEBUG_RAM_ADDR(CPU_DBG_RAM_ADDR),
		 .DEBUG_RAM_DOUT(CPU_DBG_RAM_DOUT),
		 .DEBUG_RAM_DIN(CPU_DBG_RAM_DIN),
		 .DEBUG_INSTR(CPU_DBG_INSTR),
		 .DEBUG_CPU_DIN(CPU_DBG_CPU_DIN),
		 .IORQ(IORQ),
		 .WR(WR),
		 .WORD(WORD),
		 .FASTIO(1'b1),
		 
		 .VGA_SEL(planarreq && vga_planar_seg),
		 .VGA_WPLANE(vga_wplane),
		 .VGA_RPLANE(vga_rplane),
		 .VGA_BITMASK(vga_bitmask),
		 .VGA_RWMODE(vga_rwmode),
		 .VGA_SETRES(vga_setres),
		 .VGA_ENABLE_SETRES(vga_enable_setres),
		 .VGA_LOGOP(vga_logop),
		 .VGA_COLOR_COMPARE(vga_color_compare),
		 .VGA_COLOR_DONT_CARE(vga_color_dont_care),
		 .VGA_ROTATE_COUNT(vga_rotate_count)
	);
`else
//--  Dumy.Setup VGA  ------------------------------------
	assign ADDR = daddr;
	assign DOUT = ddout;
	assign MREQ = dmreq;
	assign RAM_WMASK = dmask;
	reg  [20:0] daddr,waddr;
	reg  [31:0] ddout;
	reg         dmreq;
	reg  [3:0]  dmask;
	reg  [7:0]  hloop, vloop;
	reg  [15:0] ddptn;

	assign PORT_ADDR = dioadr;
	assign CPU_DOUT  = {8'h00,diodat};
	assign CPU_CE    = 1;
	assign IORQ      = diorq;
	assign WR        = diowr;
	reg [ 3:0] dioseq,diossq;
	reg [15:0] dioadr;
	reg  [7:0] diodat;
	reg        diorq, diowr;

	always @ (posedge clk_cpu) begin	// Dumy.Access
		if(preset) begin
			dioseq <= 1; diossq <= 0; diorq <= 0; dmreq <= 0; 
		end else if(CE) begin
			case(dioseq)
				4'h1: if(diossq==0) begin dioadr <= 16'h03c8; diodat <= 8'h01; diossq <= 1; dioseq <= 2; end 
				4'h2: if(diossq==0) begin dioadr <= 16'h03c9; diodat <= 8'h2a; diossq <= 1; dioseq <= 3; end 
				4'h3: if(diossq==0) begin dioadr <= 16'h03c9; diodat <= 8'h2a; diossq <= 1; dioseq <= 4; end 
				4'h4: if(diossq==0) begin dioadr <= 16'h03c9; diodat <= 8'h2a; diossq <= 1; dioseq <= 5; end
				//
				4'd5 : begin dioseq <=  6; waddr <= 21'h0b8000; vloop <= 0; end
				4'd6 : begin dioseq <=  7; ddptn <= 16'h0100+vloop; hloop <= 0; end 
				4'd7 : begin dioseq <=  8; dmreq <= 1; daddr <= waddr; ddout <= {16'h0000,ddptn+32}; 
							if(~waddr[1]) dmask <= 4'b0011;
							else          dmask <= 4'b1100; 
					   end
				4'd8 : begin 
						dioseq <=  9; dmreq <= 0; daddr <= 0; waddr <= waddr + 2; 
						if(ddptn[7:0]>=8'h60) ddptn[7:0] <= 0;
						else                  ddptn[7:0] <= ddptn[7:0] + 1; 
					end
				4'd9 : if(hloop<79) begin dioseq <= 7; hloop <= hloop + 1; end
						else        begin dioseq <= 10; dmreq <= 0; end
				4'd10: begin
						if(vloop<24) dioseq <= 6;
						else         dioseq <= 0; // end
						vloop <= vloop + 1;
					end
			endcase
			//
			case(diossq)
				4'h1: begin diorq <= 1; diowr <= 1; diossq <= 2; end
				4'h2: begin diorq <= 0; diowr <= 0; diossq <= 3; end
				4'h3: diossq <= 0;
			endcase
		end
	end
//-------------------------------------------
`endif

	mem_controller cache_ctl
	(
		 .addr(ADDR), 
		 .memmap_mux(memmap_mux),
		 .cpu_phys_dword_in(cpu_phys_dword),
		 .is_ems(is_ems),
		 .ems_flush(ems_flush),
		 .dout(DRAM_dout), 
		 .din(DOUT), 
		 .clk(clk_cpu), 
		 .mreq(preset ? 1'b0 : MREQ), 
		 .wmask(RAM_WMASK),
		 .ce(CE), 
		 .cpu_ce(CPU_CE), 
		 // SDRAM(Internal connection)
		 .reset(BTN_RESET),
		 .sdram_clk(sdram_clk),
		 .sdram_clk_p(sdram_clk_p),
		 .ps_calib(ps_calib),
		 .pll_lock(pll_lock),
		 .IO_sdram_dq(IO_sdram_dq),
		 .O_sdram_addr(O_sdram_addr),
		 .O_sdram_ba(O_sdram_ba),
		 .O_sdram_cs_n(O_sdram_cs_n),
		 .O_sdram_wen_n(O_sdram_wen_n),
		 .O_sdram_ras_n(O_sdram_ras_n),
		 .O_sdram_cas_n(O_sdram_cas_n),
		 .O_sdram_clk(O_sdram_clk),
		 .O_sdram_cke(O_sdram_cke),
		 .O_sdram_dqm(O_sdram_dqm),
		// vga data
		//.clk_sdr(clk_sdr),
		.clk_mctr(clk_mctr),
		.vblnk(vblnk),
		.sdraddr(sdraddr),
		.sys_CMD(cntrl0_user_command_register),
		.sys_cmd_ack(sys_cmd_ack),
		.sys_DOUT(sys_DOUT),
		.sys_rd_data_valid(sys_rd_data_valid),
		 .dbg_boot_cs(CPU_DBG_BOOT_CS), .dbg_bios_cs(CPU_DBG_BIOS_CS), .dbg_rom_dout(CPU_DBG_ROM_DOUT),
		 .dbg_sdram_state(CPU_DBG_SDRAM_STATE),

		 // RESTORED: use the real CPU flush (far jmp / int, from unit186's
		 // internal FLUSH net via CPU_FLUSH_OUT) instead of the vblank-
		 // derived auto_flush stand-in. auto_flush only pulses once per
		 // frame (~60 Hz), so a BIU stall on a far jump/interrupt that
		 // happens between vblanks was left unrecovered until the next
		 // vblank edge (or not recovered at all before further CPU
		 // activity corrupted the pending transaction) — this is the
		 // most likely single cause of the "boots to BIOS sometimes,
		 // DOS load hangs/corrupts" pattern, since DOS issues far
		 // jumps/INT calls far more densely than the BIOS splash does.
		 .flush(cpu_real_flush)
	);

	// Debug serial (COM0_PORT:$3fc-3fe)
	always @ (posedge clk_cpu) begin
		if(COM0_PORT && PORT_ADDR[1:0]==2'b00 && WR) tx0_dt <= CPU_DOUT[7:0];
	end
	assign COM0_DOUT = 	PORT_ADDR[1:0]==2'b00 ? rx0_dt :			// $3fc
						PORT_ADDR[1:0]==2'b01 ? {rx0_rdy,7'h00} :	// $3fd
						PORT_ADDR[1:0]==2'b10 ? {tx0_bsy,7'h00} :	// $3fe
												{BTN_USER,7'h00};	// 03ff Reset.Start DOS: BTN active-high, released=0 -> real BIOS
						//						{BTN_USER,7'h00};	// 03ff Reset.Start MON
	wire rx0_rd  = COM0_PORT && PORT_ADDR[1:0]==2'b00;
	wire tx0_req = COM0_PORT && PORT_ADDR[1:0]==2'b00 && WR;
	//wire rx_rd   = COM1_PORT && PORT_ADDR[1:0]==2'b00;
	//wire tx_req  = COM1_PORT && PORT_ADDR[1:0]==2'b00 && WR;
	wire tx0_bsy,rx0_rdy;
	reg  [7:0] tx0_dt;
	wire [7:0] rx0_dt;
	rs232c rs232c(
		.RESETB(~BTN_RESET), .CLK(clk_cpu), .TXD(TX), .RXD(RX), 
		.TX_DATA(tx0_dt), .TX_DATA_EN(tx0_req), .TX_BUSY(tx0_bsy), 
		.RX_DATA(rx0_dt), .RX_DATA_RD(rx0_rd),  .RX_DATA_RDY(rx0_rdy)
		);
 

	VGA_SG VGA 
	(
		.tc_hsblnk(10'd639), 
		.tc_hssync(10'd655+10'd19), 	// +17 for hrz panning
		.tc_hesync(10'd751+10'd19), 	// +17 for hrz panning
		.tc_heblnk(10'd799), 
		.hcount(hcount), 
		.hsync(raw_hsync), 
		.hblnk(raw_hblnk), 
		// REVERTED: forcing a fixed 525-line/60Hz raster here desynced the
		// SDRAM frame-fetch state machine (vga_ddr_row_count / s_vga_endframe,
		// reset off VGA_VSYNC_mctr2) from the actual displayed raster, since
		// VGA_HSYNC/VGA_VSYNC/VGA_hblnk drive the HDMI TMDS encoders directly
		// with no resync FIFO in between (see Next186_SoC.v: svo_tmds is fed
		// straight from these signals). Restored the original mode-dependent
		// timing, matching the proven Tang Nano 9K reference design.
		.tc_vsblnk(v240[2] ? 10'd479 : 10'd399), 
		.tc_vssync(v240[2] ? 10'd489 : 10'd411), 
		.tc_vesync(v240[2] ? 10'd491 : 10'd413), 
		.tc_veblnk(v240[2] ? 10'd520 : 10'd446), 
		.vcount(vcount), 
		.vsync(raw_vsync), 
		.vblnk(raw_vblnk), 
		.clk(clk_pixel),
		// Match the proven Tang Nano 9K design: VGA raster timing
		// is held until the prefetch FIFO is actually ready.
		.ce(FifoStart_pix)
	);
	
	VGA_DAC dac 
	(
		 .CE(VGA_DAC_OE && IORQ && CPU_CE), 
		 .WR(WR), 
		 .reset(preset),
		 .addr(PORT_ADDR[3:0]), 
		 .din(CPU_DOUT[7:0]), 
		 .dout(VGA_DAC_DATA), 
		 .CLK(clk_cpu), 
		 .VGA_CLK(clk_pixel), 
		 .vga_addr(cga[1] ? {4'b0000, cga_color} : (vgatext[1] | (~vga13[1] & planar[1])) ? VGA_INDEX : (vga13[1] ? hcount_pan[1] : hcount_pan[0]) ? fifo_dout[15:8] : fifo_dout[7:0]),
		 .color(DAC_COLOR),
		 .vgatext(vgatextreq),
		 .vga13(vga13req),
		 .cga4(cga4req),
		 .cga2(cga2req),
		 .half(halfreq),
		 .vgaflash(vgaflash),
		 .setindex(INPUT_STATUS_OE && IORQ && CPU_CE),
		 .hrzpan(vga_hrzpan_req),
		 .ppm(ppm),
		 .ega_attr(EGA_MUX),
		 .ega_pal_index(VGA_INDEX)
    );
	 
	 VGA_CRT crt
	 (
		.CE(IORQ && CPU_CE && VGA_CRT_OE),
		.WR(WR),
		.WORD(WORD),
		.din(CPU_DOUT),
		.addr(PORT_ADDR[0]),
		.dout(VGA_CRT_DATA),
		.CLK(clk_cpu),
		.oncursor(oncursor),
		.cursorstart(crs[0]),
		.cursorend(crs[1]),
		.cursorpos(cursorpos),
		.scraddr(scraddr),
		.offset(vga_offset),
		.lcr(lcr),
		.repln(replnreq),
		.vde(vde)
    );

	VGA_CGA cgareg
	(
		.CE(IORQ && CPU_CE && VGA_CGA_OE),
		.WR(WR),
		.addr(PORT_ADDR[0]),
		.din(CPU_DOUT[7:0]),
		.dout(VGA_CGA_DATA),
		.CLK(clk_cpu),
		.pixel(cga_pixel),
		.mode2(cga2[1]),
		.color(cga_color)
	);
	
	VGA_SC sc
	(
		.CE(IORQ && CPU_CE && VGA_SC),	// 3c4, 3c5
		.WR(WR),
		.WORD(WORD),
		.din(CPU_DOUT),
		.dout(VGA_SC_DATA),
		.addr(PORT_ADDR[0]),
		.CLK(clk_cpu),
		.planarreq(planarreq),
		.wplane(vga_wplane)
    );

	VGA_GC gc
	(
		.CE(IORQ && CPU_CE && VGA_GC),
		.WR(WR),
		.WORD(WORD),
		.din(CPU_DOUT),
		.addr(PORT_ADDR[0]),
		.CLK(clk_cpu),
		.rplane(vga_rplane),
		.bitmask(vga_bitmask),
		.rwmode(vga_rwmode),
		.setres(vga_setres),
		.enable_setres(vga_enable_setres),
		.logop(vga_logop),
		.color_compare(vga_color_compare),
		.color_dont_care(vga_color_dont_care),
		.rotate_count(vga_rotate_count),
		.dout(VGA_GC_DATA)
	);

    Gowin_DPB_font vga_font(
        .clka(clk_pixel),
        .wrea(1'b0),
        .ada({fifo_dout[7:0], char_ln}),
        .dina(8'h00),
        .douta(font_dout),
        .ocea(1'b1), .cea(1'b1), .reseta(1'b0),
        .clkb(clk_cpu),
        .wreb(WR & IORQ & VGA_FONT_OE & ~WORD & CPU_CE),
        .adb(vga_font_counter),
        .dinb(CPU_DOUT[7:0]),
        .doutb(VGA_FONT_DATA),
        .oceb(1'b1), .ceb(1'b1), .resetb(1'b0)
    );

//--//
	wire timer_int;
	PIC_8259 PIC 
	(
		 .CS(PIC_OE && IORQ && CPU_CE), // 21h, a1h
		 .WR(WR), 
		 .din(CPU_DOUT[7:0]), 
		 .slave(PORT_ADDR[7]),
		 .dout(PIC_DOUT), 
		 .ivect(PIC_IVECT), 
		 .clk(clk_cpu), 
		 .INT(INT), 
		 .IACK(INTA & CPU_CE), 
		 .I({I_COM1, I_MOUSE, RTCEND, I_KB, timer_int})
    );

	 wire timer_spk;
	 timer_8253 timer 
	 (
		 .CS(TIMER_OE && IORQ && CPU_CE), 
		 .WR(WR), 
		 .addr(PORT_ADDR[1:0]), 
		 .din(CPU_DOUT[7:0]), 
		 .dout(TIMER_DOUT), 
		 .CLK_25(clk_pixel), 
		 .clk(clk_cpu), 
		 .out0(timer_int), 
		 .out2(timer_spk)
    );
	 
	//wire KB_RST  = 0;

	KB_Mouse_8042 KB_Mouse 
	(
		 .CS(IORQ && CPU_CE && KB_OE), // 60h, 64h
		 .WR(WR), 
		 .cmd(PORT_ADDR[2]), // 64h
		 .din(CPU_DOUT[7:0]), 
		 .dout(KB_DOUT), 
		 .clk(clk_cpu), 
		 .I_KB(I_KB), 
		 .I_MOUSE(I_MOUSE), 
		 .CPU_RST(KB_RST), 
		 .PS2_CLK1(PS2_CLK1), 
		 .PS2_CLK2(PS2_CLK2), 
		 .PS2_DATA1(PS2_DATA1), 
		 .PS2_DATA2(PS2_DATA2),
		 .inject_kb_stb(inject_kb_stb),
		 .inject_kb_data(inject_kb_data),
		 .inject_mouse_stb(inject_mouse_stb),
		 .inject_mouse_data(inject_mouse_data)
	);

	sdc_pc u_sdc_pc (
		.clk        (clk_cpu),
		.reset      (preset),
		.CS         (IORQ && CPU_CE && USB_STORAGE_OE),
		.WR         (WR),
		.WORD       (WORD),
		.addr       (PORT_ADDR[2:0]),
		.din        (CPU_DOUT),
		.dout       (usb_storage_dout),
		.oe         (usb_storage_oe),
		.mcu_strobe (mcu_sdc_strobe),
		.mcu_start  (mcu_start),
		.data_in    (mcu_dout),
		.data_out   (mcu_sdc_din),
		.irq        (sdc_irq_n)
	);
	soundwave sound_gen
	(
		.CLK(clk_cpu),
		.CLK44100x256(CLK44100x256),
		.data(CPU_DOUT),
		.we(IORQ & CPU_CE & WR & PARALLEL_PORT),
		.word(WORD),
		.speaker(speaker_on & timer_spk),
		.opl3left(opl3left),
		.opl3right(opl3right),
		.stb44100(stb44100),
		.full(sq_full),	// when not full, write max 2x1152 16bit samples
		.dss_full(dss_full),
		.AUDIO_L(AUD_L),
		.AUDIO_R(AUD_R)
	);	 
	DSP32 DSP32_inst
	(
		.clkcpu(clk_cpu),
		.clkdsp(clk_dsp),
		.cmd(PORT_ADDR[0]), // port 2=data, port 3=cmd (word only)
		.ce(IORQ & CPU_CE & CPU32_PORT & WORD),
		.wr(WR),
		.din(CPU_DOUT),
		.dout(cpu32_data),
		.halt(cpu32_halt)
	);
/*
//	UART_8250 UART(
//		.CLK_18432000(CLK14745600),
//		.RS232_DCE_RXD(RX),
//		.RS232_DCE_TXD(TX),
//		.clk(clk_cpu),
//		.din(CPU_DOUT[7:0]),
//		.dout(COM1_DOUT),
//		.cs(COM1_PORT && IORQ && CPU_CE),
//		.wr(WR),
//		.addr(PORT_ADDR[2:0]),
//		.BRShift(COMBRShift),
//		.INT(I_COM1)
//   );
*/
    opl3 opl3_inst (
        .clk(CLK_50MHZ), // 50Mhz (min 45Mhz)
        .cpu_clk(clk_cpu),
        .addr(PORT_ADDR[1:0]),
        .din(CPU_DOUT[7:0]),
        .dout(opl32_data),
        .ce(IORQ & CPU_CE & OPL3_PORT),
        .wr(WR),
        .left(opl3left),
        .right(opl3right),
        .stb44100(stb44100),
        .reset(preset)    
     );
/*	
	i2c_master_byte i2cmb
	(
		.refclk(clk_pixel),	// 25Mhz=100Kbps...100Mhz=400Kbps
		.din(i2c_cd[7:0]),
		.cmd(i2c_cd[11:8]),	// 01xx=wr,10xx=rd+ack, 11xx=rd+nack, xx1x=start, xxx1=stop
		.dout(i2cdout),
		.ack(i2cack),
		.noack(i2cackerr),
		.SCL(I2C_SCL),
		.SDA(I2C_SDA),
		.rst(1'b0)
	);
*/
	// Match the original Next186 9K VGA DMA contract: each sys_CMD=2'b10
	// request produces exactly 16 consecutive 16-bit sys_DOUT words.
	// The 20K SDRAM backend fetches 8 x 32-bit words and exposes their
	// 16 half-words through mem_controller.
wire wrreq = (!crw && sys_rd_data_valid && !col_counter[4]);
	wire fifo_full_unused;
	// Match the original Next186 9K VGA contract.  The FIFO is allowed to
	// drain during VSYNC exactly as in the reference design; the important
	// invariant is that every sys_CMD burst contributes exactly 16 half-words.
	// Keeping this protocol identical prevents FIFO write/read phase drift.
	FIFO_HS_vga vga_fifo(
		.WrClk(clk_mctr),
		.RdClk(clk_pixel),
		.Data(sys_DOUT),
		.WrEn(wrreq),
		.RdEn(vrden || VGA_VSYNC),
		.Q(fifo_dout32),
		.Rnum(fifo_wr_used_words),
		.Almost_Empty(AlmostEmpty),
		.Almost_Full(AlmostFull),
		.Full(fifo_full_unused),
		.Empty(fifo_empty)
	);


	// Direct state-free CGA row address calculation from vga_ddr_row_count (0..399):
	// Bank 0 (even rows): 0x0E000 (B8000 / 4). Bank 1 (odd rows): 0x0E800 (BA000 / 4).
	// Row offset within bank = row * 20 dwords (80 bytes per scanline).
	wire [16:0] cga_base = vga_ddr_row_count[1] ? 17'h0E800 : 17'h0E000;
	wire [11:0] cga_row_offset = {vga_ddr_row_count[8:2], 4'b0000} + {vga_ddr_row_count[8:2], 2'b00};
	wire [16:0] cga_addr = cga_base + {5'b00000, cga_row_offset};

	reg nop;
	always @ (posedge clk_mctr) begin
		if (preset) begin
			// Reset every piece of VGA/SDRAM-prefetch control state together.
			// The previous design left several of these registers uninitialised
			// across S2 reset, so wrreq/command generation could remain inactive
			// even though the CPU/BIOS had already restarted.
			s_prog_full <= 1'b0;
			s_prog_empty <= 1'b1;
			FifoStart <= 1'b0;
			vga_fifo_fill_count <= 9'd0;
			s_ddr_rd <= 1'b0;
			s_ddr_wr <= 1'b0;
			s_vga_endline <= 1'b0;
			s_vga_endframe <= 1'b0;
			nop <= 1'b1;
			cntrl0_user_command_register <= 2'b00;
			sdraddr <= 24'd0;
			max_read <= 3'd7;
			col_counter <= 5'd0;
			crw <= 1'b0;
			vga_lnbytecount <= 8'd0;
			vga_ddr_row_count <= 9'd0;
			vga_ddr_row_col <= 17'he000;
			vga_repln_count <= 4'd0;
			s_vga_endscanline <= 1'b0;
		end else begin
			// Restore the reference Next186 9K FIFO control semantics.
			// The generated 20K FIFO exposes a synchronized 10-bit Rnum, matching
			// the original FIFO interface used by the working design.
			s_prog_full <= (fifo_wr_used_words > 10'd350);
			if (fifo_wr_used_words < 10'd64) begin
				s_prog_empty <= 1'b1;
			end else begin
				s_prog_empty <= 1'b0;
				FifoStart <= 1'b1;
			end
			// vga_fifo_fill_count is retained only as a diagnostic counter.
			if (wrreq && vga_fifo_fill_count != 9'h1FF)
				vga_fifo_fill_count <= vga_fifo_fill_count + 1'b1;

			s_ddr_rd <= ddr_rd;
			s_ddr_wr <= ddr_wr;
			s_vga_endline <= vga_repln_count == vga_repln;
			s_vga_endframe <= vga_end_frame;
			nop <= sys_cmd_ack == 2'b00;

			// Current Next186 video DMA uses the dedicated VGA framebuffer path.
			// Keep its address calculation independent from cache request flags;
			// the cache read/write commands are disabled below in this port.
			// VGA framebuffer addresses must use the same 32-bit-word SDRAM address
			// convention as the CPU.  The BIOS/CPU text buffer is at B8000h,
			// hence word address 0x2E000; mode 13h graphics starts at A0000h,
			// hence word address 0x28000.  vga_ddr_row_col is the legacy 9K
			// framebuffer offset (text starts at 0x8000, graphics at 0xE000),
			// so translate that offset to the real 20K SDRAM word address here.
			// This fixes the previous mapping where text 0x8000 became 0x18000
			// (CPU-visible byte address 0x60000), instead of B8000h.
			// Row/page-boundary burst clamp. NOTE: the mem_controller.v
			// comment for this exact logic states the intent is a 512-word
			// boundary ("sdraddr[7:3] as its 512-word SDRAM row boundary"),
			// but &sdraddr[7:3] alone only detects a 256-word boundary
			// (all-ones only every 2^8 words, not 2^9). Widened to
			// sdraddr[8:3] to match the documented intent -- this can only
			// ever *lengthen* bursts (fewer needless truncations), never
			// shorten them, so it's a safe, monotonic change either way.
			// NOTE: measured impact of the old 256-word check was small
			// (~3% of burst-start addresses affected) -- unlikely to be the
			// primary source of the visible glitching by itself, but it's
			// a real, free-to-fix inefficiency in the same pipeline.
			sdraddr <= {6'b000001, (cga[0] ? cga_addr : vga_ddr_row_col) + vga_lnbytecount};
			max_read <= 3'b111;

			if(VGA_VSYNC_mctr2) begin
				vga_lnbytecount <= 0;
				vga_ddr_row_count <= 0;
				vga_repln_count <= 0;
			end else begin
				// Keep issuing VGA read commands while the write-side FIFO is not
				// almost full.  The mem_controller itself holds one request until
				// completion, so a sustained command level cannot be lost.
				if(s_prog_empty) cntrl0_user_command_register <= 2'b10;
				else if(~s_prog_full) cntrl0_user_command_register <= 2'b10;
				else cntrl0_user_command_register <= 2'b00;

				if(!crw && sys_rd_data_valid && col_counter != 0)
					col_counter <= col_counter - 1'b1;

				if(nop) case(sys_cmd_ack)
					2'b10: begin
						crw <= 1'b0;
						col_counter <= {1'b0, max_read, 1'b1};
						vga_lnbytecount <= vga_lnbytecount + max_read + 1'b1;
					end
					2'b01, 2'b11: crw <= 1'b1;
				endcase

				if(s_vga_endscanline) begin
					col_counter[3:1] <= col_counter[3:1] - vga_lnbytecount[2:0];
					vga_lnbytecount <= 0;
					s_vga_endscanline <= 1'b0;

					if(s_vga_endframe)
						vga_ddr_row_col <= {{1'b0, scraddr_mctr2[15:13]} + (vgatext[0] ? 4'b0111 : 4'b0100), scraddr_mctr2[12:0]};
					else if(!cga[0] && ({1'b0, vga_ddr_row_count} == lcr_f))
						vga_ddr_row_col <= vgatext[0] ? 17'he000 : 17'h8000;
					else if(s_vga_endline)
						vga_ddr_row_col <= vga_ddr_row_col + (vgatext[0] ? 17'd40 : {offset_f, 1'b0});

					if(s_vga_endline) vga_repln_count <= 0;
					else vga_repln_count <= vga_repln_count + 1'b1;

					if(s_vga_endframe) begin
						vga13[0] <= vga13req_mctr2;
						vgatext[0] <= vgatextreq_mctr2;
						v240[0] <= vde_mctr2 >= 10'd400;
						planar[0] <= planarreq_mctr2;
						half[0] <= halfreq_mctr2;
						repln_graph[0] <= replnreq_mctr2;
						cga4[0] <= cga4req_mctr2;
						cga2[0] <= cga2req_mctr2;
						lcr_f <= lcr_mctr2;
						offset_f <= vga_offset_mctr2;
						vga_ddr_row_count <= 0;
					end else vga_ddr_row_count <= vga_ddr_row_count + 1'b1;
				end else begin
					s_vga_endscanline <= (vga_lnbytecount[7:3] == vga_lnend);
				end
			end
		end
	end

	reg [7:0]SDI;
	//assign SD_DI = CPU_DOUT[7];
	assign SD_DI = sd_dout[7];

	reg  [7:0] sd_dout, sd_din;
	reg  [4:0] sd_dct; 
	reg        sd_bsy, sd_run, sd_ckx;
	reg  [2:0] sd_div;
	reg        sd_do_sync1, sd_do_sync2; // 2-flop synchronizer for the async SD_DO card input
	wire       sd_dix = sd_dout[7];
	always @ (posedge clk_cpu) begin
		s_RS232_DCE_RXD <= RS232_DCE_RXD;
		s_RS232_HOST_RXD <= RS232_HOST_RXD;
		sd_do_sync1 <= SD_DO;
		sd_do_sync2 <= sd_do_sync1;
		if(IORQ & CPU_CE) begin
			if(WR & AUX_OE) begin
				if(WORD) auto_flush[2] <= CPU_DOUT[0];
				else {COMBRShift[1:0], RS232_HOST_RST, ComSel[1:0]} <= CPU_DOUT[4:0];
			end
			if(VGA_FONT_OE) vga_font_counter <= WR && WORD ? {CPU_DOUT[7:0], 4'b0000} : vga_font_counter + 1'b1; 
			if(WR & SPEAKER_PORT) speaker_on <= &CPU_DOUT[1:0];
		end
// SD
		if(CPU_CE) begin
			//SD_CK <= IORQ & INPUT_STATUS_OE & WR & ~WORD;
			if(IORQ & INPUT_STATUS_OE & WR) begin
				if(WORD) SD_n_CS <= ~CPU_DOUT[8]; // SD chip select
				//else SDI <= {SDI[6:0], SD_DO};
			end
		end

		if(preset) begin sd_bsy <= 0; sd_run <= 0; sd_ckx <= 0; end
		else begin
			if(IORQ & INPUT_STATUS_OE && CPU_CE) begin
				if(WR && ~WORD && ~sd_bsy) begin
					sd_dout <= CPU_DOUT[7:0]; sd_dct <= 15;
					sd_bsy <= 1; sd_run <= 1; sd_div <= 0;
				end
				if(~WR && WORD) sd_bsy <= 0;
			end

			if(sd_run) begin
				SD_CK <= sd_dct[0];
				if(~sd_dct[0]) begin
					sd_dout <= {sd_dout[6:0], 1'b0};
					SDI <= {SDI[6:0], SD_DO};
				end
				if(sd_dct==0) sd_run <= 0; 
				else          sd_dct <= sd_dct - 5'd1;
			end
		end

// RESET / power-on bring-up:
		// Initial reset timing must not depend on CPU_CE, because CPU_CE is
		// generated by the CPU/BIU and can be 0 while the core is held in reset.
		// Also ignore KB_RST during this automatic power-on interval.
		if(BTN_RESET || ~ps_calib) rstcount <= 0;
		else if(~rstcount[18]) rstcount <= rstcount + 1'b1;
// RTC		
		RTCSYNC <= {RTCSYNC[0], rtc_tick_cpu2};
		if(IORQ && CPU_CE && WR && WORD && RTC_SELECT) begin
			RTC <= 0;
			RTCSET <= CPU_DOUT;
		end else if(RTCSYNC == 2'b01) begin
			if(RTCEND) RTC <= 0;
			else RTC <= RTC + 1'b1;
		end
// GPIO
		if(CPU_CE) GPIOData <= GPIO;
		if(IORQ && CPU_CE && WR && JOYSTICK) begin
			if(WORD) GPIOState <= CPU_DOUT[15:8];
			GPIODout <= CPU_DOUT[7:0];
		end
// NMI on IORQ
		if(IORQ && CPU_CE && WR && NMI_IORQ_PORT)
			if(PORT_ADDR[0]) NMIonIORQ_HI <= CPU_DOUT;
			else NMIonIORQ_LO <= CPU_DOUT;
// I2C
		if(CPU_CE && IORQ && WR && WORD && I2C_SELECT) i2c_cd <= CPU_DOUT[11:0];
					
		auto_flush[1:0] <= {auto_flush[0], vblnk_cpu2};		
	end
	
	always @ (posedge clk_pixel) begin
		s_displ_on <= {s_displ_on[17:0], displ_on};
		// 8 trailing FIFO pops normally (32 panning bytes); CGA fetches 24 dwords
		// per line and displays 20, so it only needs 4 trailing pops to stay in
		// balance (exline[3] gates vrden, so 4'b1011 allows exactly 4).
		exline <= vrdon ? (cga[1] ? 4'b1011 : 4'b1111) : (exline - vrden); // 32 extra bytes at the end of the scanline, for panning
		
		vga_attr <= fifo_dout[15:8];		
		flash_on <= (vgaflash_pix & fifo_dout[15] & flashcount[5]) | (~oncursor_pix && flashcount[4] && (charcount == cursorpos_pix) && (char_ln >= crs_start_pix[3:0]) && (char_ln <= crs_end_pix[3:0]));		
		
		if(!vblnk) begin
			flashbit <= 1;
			vga13[2] <= vga13[1];
			vgatext[2] <= vgatext[1];
			cga4[2] <= cga4[1];
			cga2[2] <= cga2[1];
			v240[2] <= v240[1];
			planar[2] <= planar[1];
			half[2] <= half[1];
		end else if(flashbit) begin
			flashcount <= flashcount + 1'b1;
			flashbit <= 0;
			vga13[1] <= vga13[0];
			vgatext[1] <= vgatext[0];
			cga4[1] <= cga4[0];
			cga2[1] <= cga2[0];
			vde_pixf <= vde_pix;	// CRTC geometry is only allowed to change during vblank
			lcr_pixf <= lcr_pix;
			v240[1] <= v240[0];
			planar[1] <= planar[0];
			half[1] <= half[0];
		end
		
		if(RTCDIVEND) RTCDIV25 <= 0;	// real time clock
		else RTCDIV25 <= RTCDIV25 + 1'b1;
		
		if(!BTN_NMI) rNMI <= 0;		// NMI
		else if(!rNMI[9] && RTCDIVEND) rNMI <= rNMI + 1'b1;	// 1Mhz increment

		if(VGA_VSYNC) vga_hrzpan <= half[0] ? {vga_hrzpan_req_pix[2:0], 1'b0} : {1'b0, vga_hrzpan_req_pix[2:0]};
		else if(VGA_HSYNC && ppm_pix && (vcount == lcr_pixf)) vga_hrzpan <= 4'b0000;

		{VGA_B, VGA_G, VGA_R} <= DAC_COLOR & {18{sdon}};
	end
	
endmodule



// ---------------------------------------------------------------------------
// 64-KB segment mapper used by the original Next186 memory architecture.
// ---------------------------------------------------------------------------
module seg_map(
    input  wire       CLK,
    input  wire       RST,
    input  wire [3:0] cpuaddr,
    output wire [8:0] cpurdata,
    input  wire [8:0] cpuwdata,
    input  wire [4:0] memaddr,
    output wire [8:0] memdata,
    input  wire       WE
);
    reg [8:0] map [0:31];

    // Reference Next186 segment layout.  Segment 0Fh (F000h) is physical
    // segment 15h so that the BIOS ROM can be shadow-copied into RAM there;
    // the BIOS changes segment 0Ch (C000h) to 15h with OUT 8Ch,0015h.
    // Segments 10h..1Fh provide the extended/high-memory window used by
    // the original software environment.
    always @(posedge CLK) begin
        if (RST) begin
            map[0]  <= 9'h000;
            map[1]  <= 9'h001;
            map[2]  <= 9'h002;
            map[3]  <= 9'h003;
            map[4]  <= 9'h004;
            map[5]  <= 9'h005;
            map[6]  <= 9'h006;
            map[7]  <= 9'h007;
            map[8]  <= 9'h008;
            map[9]  <= 9'h009;
            map[10] <= 9'h00A;
            map[11] <= 9'h00B;
            map[12] <= 9'h012;
            map[13] <= 9'h013;
            map[14] <= 9'h014;
            map[15] <= 9'h00F;
            map[16] <= 9'h016;
            map[17] <= 9'h001;
            map[18] <= 9'h002;
            map[19] <= 9'h003;
            map[20] <= 9'h004;
            map[21] <= 9'h005;
            map[22] <= 9'h006;
            map[23] <= 9'h007;
            map[24] <= 9'h008;
            map[25] <= 9'h009;
            map[26] <= 9'h00A;
            map[27] <= 9'h00B;
            map[28] <= 9'h00C;
            map[29] <= 9'h00D;
            map[30] <= 9'h00E;
            map[31] <= 9'h00F;
        end else if (WE) begin
            map[cpuaddr] <= cpuwdata;
        end
    end

    assign cpurdata = map[cpuaddr];
    assign memdata  = map[memaddr];
endmodule
