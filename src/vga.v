//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: vga.v
// Description: Part of the Next186 SoC PC project, VGA module
//		customized VGA, only modes 3 (25x80x256 text), 13h (320x200x256 graphic) 
//		and VESA 101h (640x480x256) implemented
// Version 1.0
// Creation date: Jan2012
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
//////////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module VGA_SG
  (
  input  wire	[9:0]	tc_hsblnk,
  input  wire	[9:0]	tc_hssync,
  input  wire	[9:0]	tc_hesync,
  input  wire	[9:0]	tc_heblnk,

  output reg	[9:0]	hcount = 0,
  output reg			hsync,
  output reg			hblnk = 0,

  input  wire	[9:0]	tc_vsblnk,
  input  wire	[9:0]	tc_vssync,
  input  wire	[9:0]	tc_vesync,
  input  wire	[9:0]	tc_veblnk,

  output reg	[9:0]	vcount = 0,
  output reg			vsync,
  output reg			vblnk = 0,

  input  wire			clk,	// clk_pixel
  input  wire			ce
  );

  //******************************************************************//
  // This logic describes a 10-bit horizontal position counter.       //
  //******************************************************************//
  always @(posedge clk)
		if(ce) begin
			if(hcount >= tc_heblnk) begin
				hcount <= 0;
				hblnk <= 0;
			end else begin
				hcount <= hcount + 10'd1;
				hblnk <= (hcount >= tc_hsblnk);
			end
			hsync <= (hcount >= tc_hssync) && (hcount < tc_hesync);
		end
		
  //******************************************************************//
  // This logic describes a 10-bit vertical position counter.         //
  //******************************************************************//
	always @(posedge clk)
		if(ce && hcount == tc_heblnk) begin
			if (vcount >= tc_veblnk) begin
				vcount <= 0;
				vblnk <= 0;
			end else begin
				vcount <= vcount + 10'd1;
				vblnk <= (vcount >= tc_vsblnk);
			end
			vsync <= (vcount >= tc_vssync) && (vcount < tc_vesync);
		end

  //******************************************************************//
  // This is the logic for the horizontal outputs.  Active video is   //
  // always started when the horizontal count is zero.  Example:      //
  //                          
  //
  // tc_hsblnk = 03                                                   //
  // tc_hssync = 07                                                   //
  // tc_hesync = 11                                                   //
  // tc_heblnk = 15 (htotal)                                          //
  //                                                                  //
  // hcount   00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15         //
  // hsync    ________________________------------____________        //
  // hblnk    ____________------------------------------------        //
  //                                                                  //
  // hsync time  = (tc_hesync - tc_hssync) pixels                     //
  // hblnk time  = (tc_heblnk - tc_hsblnk) pixels                     //
  // active time = (tc_hsblnk + 1) pixels                             //
  //                                                                  //
  //******************************************************************//

  //******************************************************************//
  // This is the logic for the vertical outputs.  Active video is     //
  // always started when the vertical count is zero.  Example:        //
  //                                                                  //
  // tc_vsblnk = 03                                                   //
  // tc_vssync = 07                                                   //
  // tc_vesync = 11                                                   //
  // tc_veblnk = 15 (vtotal)                                          //
  //                                                                  //
  // vcount   00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15         //
  // vsync    ________________________------------____________        //
  // vblnk    ____________------------------------------------        //
  //                                                                  //
  // vsync time  = (tc_vesync - tc_vssync) lines                      //
  // vblnk time  = (tc_veblnk - tc_vsblnk) lines                      //
  // active time = (tc_vsblnk + 1) lines                              //
  //                                                                  //
  //******************************************************************//


endmodule


module VGA_DAC(
     input CE,
	 input WR,
	 input reset,
     input [3:0]addr,
	 input [7:0]din,
	 output [7:0]dout,
	 input CLK,
	 input VGA_CLK,
	 input [7:0]vga_addr,
	 input setindex,
	 output [17:0]color,
	 output reg vgatext = 1'b1,
	 output reg vga13 = 1'b1,
	 output reg vgaflash = 0,
	 output reg half = 0,
	 output reg [3:0]hrzpan = 0,
	 output reg ppm = 0, // pixel panning mode
	 output reg cga4 = 0,	// CGA 320x200x4 (2bpp, interleaved banks) - modes 4/5
	 output reg cga2 = 0,	// CGA 640x200x2 (1bpp, interleaved banks) - mode 6
	 input [3:0]ega_attr,
	 output [7:0]ega_pal_index
    );

	initial vgatext = 1'b1;
	initial vga13 = 1'b1;
	
	reg [7:0]mask = 8'hff;
	reg [9:0]index = 0;
	reg mode = 0;
	reg [4:0]a0index = 0;
	reg a0data = 0;
	wire [7:0]pal_dout;
	wire [31:0]pal_out;
	wire addr6 = addr == 6;
	wire addr7 = addr == 7;
	wire addr8 = addr == 8;
	wire addr9 = addr == 9;
	wire addr0 = addr == 0;
	//reg [5:0]egapal[15:0];
	//initial $readmemh("egapal.mem", egapal);
	reg [5:0] egapal [0:15];
	initial begin
		egapal[0]=6'd0;  egapal[1]=6'd1;  egapal[2]=6'd2;  egapal[3]=6'd3;
		egapal[4]=6'd4;  egapal[5]=6'd5;  egapal[6]=6'd6;  egapal[7]=6'd7;
		egapal[8]=6'd8;  egapal[9]=6'd9;  egapal[10]=6'd10; egapal[11]=6'd11;
		egapal[12]=6'd12; egapal[13]=6'd13; egapal[14]=6'd14; egapal[15]=6'd15;
	end
	reg p54s = 1'b0;
	reg [3:0]colsel = 4'b0000;
	wire [5:0]egacolor = egapal[ega_attr]; 
	assign ega_pal_index = {colsel[3:2], p54s ? colsel[1:0] : egacolor[5:4], egacolor[3:0]};
	reg [7:0]store[5'h14:0];
	reg [7:0]attrib;
////
//	DAC_SRAM vga_dac 

	// --- Power-on palette initializer -----------------------------------
	// Gowin_DPB_dac has no .mi init file, so on power-up its BRAM contents
	// are undefined (observed as all-0xFF), which shows up as a garbled
	// green screen once INT 10h switches into a text/graphics mode.
	// This block writes a standard CGA/EGA 16-colour palette (entries 0-15,
	// 6 bits/channel) into the DAC through port A, using the exact same
	// R,G,B byte-offset sequence (index*4+0/+1/+2) that the CPU driver uses
	// when it programs the DAC via ports 3C8h/3C9h. Entries 16-255 are
	// cleared to black. This runs once, for 1024 CLK cycles, before normal
	// CPU access to the DAC is relied upon.
	function [5:0] cga_r; input [3:0] i; begin case(i)
		4'd0:cga_r=6'd0;  4'd1:cga_r=6'd0;  4'd2:cga_r=6'd0;  4'd3:cga_r=6'd0;
		4'd4:cga_r=6'd42; 4'd5:cga_r=6'd42; 4'd6:cga_r=6'd42; 4'd7:cga_r=6'd42;
		4'd8:cga_r=6'd21; 4'd9:cga_r=6'd21; 4'd10:cga_r=6'd21;4'd11:cga_r=6'd21;
		4'd12:cga_r=6'd63;4'd13:cga_r=6'd63;4'd14:cga_r=6'd63;4'd15:cga_r=6'd63;
	endcase end endfunction
	function [5:0] cga_g; input [3:0] i; begin case(i)
		4'd0:cga_g=6'd0;  4'd1:cga_g=6'd0;  4'd2:cga_g=6'd42; 4'd3:cga_g=6'd42;
		4'd4:cga_g=6'd0;  4'd5:cga_g=6'd0;  4'd6:cga_g=6'd21; 4'd7:cga_g=6'd42;
		4'd8:cga_g=6'd21; 4'd9:cga_g=6'd21; 4'd10:cga_g=6'd63;4'd11:cga_g=6'd63;
		4'd12:cga_g=6'd21;4'd13:cga_g=6'd21;4'd14:cga_g=6'd63;4'd15:cga_g=6'd63;
	endcase end endfunction
	function [5:0] cga_b; input [3:0] i; begin case(i)
		4'd0:cga_b=6'd0;  4'd1:cga_b=6'd42; 4'd2:cga_b=6'd0;  4'd3:cga_b=6'd42;
		4'd4:cga_b=6'd0;  4'd5:cga_b=6'd42; 4'd6:cga_b=6'd0;  4'd7:cga_b=6'd42;
		4'd8:cga_b=6'd21; 4'd9:cga_b=6'd63; 4'd10:cga_b=6'd21;4'd11:cga_b=6'd63;
		4'd12:cga_b=6'd21;4'd13:cga_b=6'd63;4'd14:cga_b=6'd21;4'd15:cga_b=6'd63;
	endcase end endfunction

	reg pal_init_done = 1'b0;
	reg [9:0] pal_init_addr = 10'd0;
	wire pal_init_active = ~pal_init_done;
	wire [7:0] pal_init_color_idx = pal_init_addr[9:2];
	wire [1:0] pal_init_ch = pal_init_addr[1:0];
	wire [5:0] pal_init_val = (pal_init_color_idx < 8'd16) ?
		(pal_init_ch == 2'd0 ? cga_r(pal_init_color_idx[3:0]) :
		 pal_init_ch == 2'd1 ? cga_g(pal_init_color_idx[3:0]) :
		 pal_init_ch == 2'd2 ? cga_b(pal_init_color_idx[3:0]) : 6'd0)
		: 6'd0;
	wire [7:0] pal_init_data = {2'b00, pal_init_val};

	always @(posedge CLK) begin
		if(!pal_init_done) begin
			if(pal_init_addr == 10'd1023) pal_init_done <= 1'b1;
			pal_init_addr <= pal_init_addr + 10'd1;
		end
	end
	// ---------------------------------------------------------------------

	wire [7:0] dadr = vga_addr & mask;
    Gowin_DPB_dac vga_dac(
        .clka(CLK), //input clka
        .wrea((CE & WR & addr9) | pal_init_active), //input wrea
        .reseta(1'b0), //input reseta
        .cea(1'b1), //input cea
        .ocea(1'b1), //input ocea
        .ada(pal_init_active ? pal_init_addr : index), //input [9:0] ada
        .dina(pal_init_active ? pal_init_data : din), //input [7:0] dina
        .douta(pal_dout), //output [7:0] douta

        .clkb(VGA_CLK), //input clkb
        .wreb(1'b0), //input wreb
        .resetb(1'b0), //input resetb
        .ceb(1'b1), //input ceb
        .oceb(1'b1), //input oceb
        .adb(vga_addr & mask), //input [7:0] adb
        .dinb(32'h00000000), //input [31:0] dinb
        .doutb(pal_out) //output [31:0] doutb
    );

	assign color = {pal_out[21:16], pal_out[13:8], pal_out[5:0]};
	assign dout = addr6 ? mask : addr7 ? {6'bxxxxxx, mode, mode} : addr8 ? index[9:2] : addr9 ? pal_dout : attrib;
	
	always @(posedge CLK) begin

		if(setindex) a0data <= 0;
		else if(CE && addr0 && WR) a0data <= ~a0data;
	
		if(CE) begin
			if(addr0) begin
				if(WR) begin					
					if(a0data) begin
						if(!a0index[4]) egapal[a0index[3:0]] <= din[5:0];
						else case(a0index[3:0]) 
							4'h0: {p54s, vga13, ppm, half, vgaflash, cga4, cga2, vgatext} <= {din[7:3], din[2], din[1], ~din[0]};
								// bits 2/1 of ATC reg 10h are unused by the Next186 BIOS,
								// they are reused here as the CGA 4-colour / 2-colour mode flags
							4'h3: hrzpan <= din[3:0];
							4'h4: colsel <= din[3:0];
						endcase 
						store[a0index] <= din;
					end else begin
						a0index <= din[4:0];
						attrib <= store[din[4:0]];
					end
				end
			end 
			if(addr6 && WR) mask <= din;
			if(addr7 | addr8) begin
				if(WR) index <= {din, 2'b00};
				mode <= addr8;
			end else if(addr9) index <= index + (index[1:0] == 2'b10 ? 10'd2 : 10'd1);
		end
	end

endmodule



module VGA_CRT(
    input CE,
	 input WR,
	 input WORD,
	 input [15:0]din,
	 input addr,
	 output [7:0]dout,
	 input CLK,
	 output reg oncursor,
	 output reg [4:0]cursorstart,
	 output reg [4:0]cursorend,
	 output reg [11:0]cursorpos,
	 output reg [15:0]scraddr = 16'h0000,
	 output reg [7:0]offset = 8'h28,
	 output reg [9:0]lcr = 10'h3ff,	// line compare register
	 output reg repln = 1'b0,		// line repeat (1 for 200-line graphic modes)
	 output reg [9:0]vde = 10'h18f	// last visible scan line (399 = 400 lines)
    );

	// ------------------------------------------------------------------
	// 2026-09: the 20K port had scraddr/offset/lcr/vde/repln tied to
	// constants (Mode 3 values) to work around a mid-frame tearing bug.
	// That also froze the geometry for every non-Mode-3 screen:
	//   * mode 0Dh (320x200x16) needs offset = 14h, not 28h
	//     -> with 28h the fetch stride is doubled, the picture is
	//        vertically squeezed and the bottom runs off screen
	//        (exactly the "Pole Chudes" symptom),
	//   * modes 12h / 25h need vde = 479, not 399,
	//   * scraddr must be writable or page flipping / hardware
	//     scrolling never works.
	// The registers are restored here; the tearing is fixed properly in
	// system.v by latching the CRTC geometry once per frame instead of
	// letting it change in the middle of an active frame.
	// ------------------------------------------------------------------
	initial scraddr = 16'h0000;
	initial offset  = 8'h28;
	initial lcr     = 10'h3ff;
	initial vde     = 10'h18f;
	initial repln   = 1'b0;

	reg [4:0]idx_buf = 0;
	reg [7:0]store[5'h18:0];
	wire [4:0]index = addr ? idx_buf : din[4:0];
	wire [7:0]data = addr ? din[7:0] : din[15:8];
	reg [7:0]dout1;
	assign dout = addr ? dout1 : {3'b000, idx_buf};

	always @(posedge CLK) begin
		if(CE && WR) begin
			if(!addr) idx_buf <= din[4:0];
			if(addr || WORD) begin
				store[index] <= data;
				case(index)
					5'h7: {vde[9:8], lcr[8]} <= {data[6], data[1], data[4]};
					5'h9: {lcr[9], repln} <= {data[6], data[0] | data[7]};
					5'ha: {oncursor, cursorstart} <= data[5:0];
					5'hb: cursorend <= data[4:0];
					5'hc: scraddr[15:8] <= data;
					5'hd: scraddr[7:0] <= data;
					5'he: cursorpos[11:8] <= data[3:0];
					5'hf: cursorpos[7:0] <= data;
					5'h12: vde[7:0] <= data;
					5'h13: offset <= data;
					5'h18: lcr[7:0] <= data;
				endcase
			end
		end
		dout1 <= store[idx_buf];
	end
endmodule


module VGA_SC(
    input CE,
	 input WR,
	 input WORD,
	 input [15:0]din,
	 output [7:0]dout,
	 input addr,
	 input CLK,
	 output reg planarreq,
	 output reg[3:0]wplane
    );
	
	reg [2:0]idx_buf = 0;
	wire [2:0]index = addr ? idx_buf : din[2:0];
	wire [7:0]data = addr ? din[7:0] : din[15:8];
	reg [7:0]dout1;
	assign dout = addr ? dout1 : {5'b00000, idx_buf};
	 
	always @(posedge CLK) begin 
		if(CE && WR) begin
			if(!addr) idx_buf <= din[2:0];
			if(addr || WORD) begin
				if(index == 2) wplane <= data[3:0];
				if(index == 4) planarreq <= ~data[3];
			end
		end
		dout1 <= {4'b0000, idx_buf == 2 ? wplane : {~planarreq, 3'b000}};
	end
endmodule


module VGA_GC(
    input CE,
	 input WR,
	 input WORD,
	 input [15:0]din,
	 output [7:0]dout,
	 input addr,
	 input CLK,
	 output reg [1:0]rplane = 2'b00,
	 output reg[7:0]bitmask = 8'b11111111,
	 output reg [2:0]rwmode = 3'b000,
	 output reg [3:0]setres = 4'b0000,
	 output reg [3:0]enable_setres = 4'b0000,
	 output reg [1:0]logop = 2'b00,
	 output reg [3:0]color_compare = 4'b0000,
	 output reg [3:0]color_dont_care = 4'b1111,
	 output reg [2:0]rotate_count = 3'b000
    );
	
	initial bitmask = 8'b11111111;
	initial color_dont_care = 4'b1111;
	
	reg [3:0]idx_buf = 0;
	reg [7:0]store[8:0];
	wire [3:0]index = addr ? idx_buf : din[3:0];
	wire [7:0]data = addr ? din[7:0] : din[15:8];
	reg [7:0]dout1;
	assign dout = addr ? dout1 : {4'b0000, idx_buf};
	 
	always @(posedge CLK) begin
		if(CE && WR) begin
			if(!addr) idx_buf <= din[3:0];
			if(addr || WORD) begin
				store[index] <= data;
				case(index)
					0: setres <= data[3:0];
					1: enable_setres <= data[3:0];
					2: color_compare <= data[3:0];
					3: {logop, rotate_count} <= data[4:0];
					4: rplane <= data[1:0];
					5: rwmode <= {data[3], data[1:0]};
					7: color_dont_care <= data[3:0];
					8: bitmask <= data;
				endcase
			end
		end
		dout1 <= store[idx_buf];
	end
endmodule



//////////////////////////////////////////////////////////////////////////////////
// CGA mode/colour-select registers, ports 3D8h and 3D9h.
// The Next186 core never decoded these, so every real CGA game (modes 4/5/6)
// ended up drawing its bitmap into what the hardware still believed was the
// 80x25 text buffer - which is exactly the "scrambled characters that almost
// look like the picture" effect.
// Only the bits that matter for the colour lookup are kept.
//////////////////////////////////////////////////////////////////////////////////
module VGA_CGA(
	input CE,			// 3d8h / 3d9h decoded, IORQ & CPU_CE
	input WR,
	input addr,			// 0 = 3d8h (mode control), 1 = 3d9h (colour select)
	input [7:0]din,
	output [7:0]dout,
	input CLK,
	input [1:0]pixel,	// 2bpp pixel value (mode 4/5) - bit1:0
	input mode2,		// 1 = 640x200x2 (mode 6): only pixel[1] is used
	output [3:0]color	// resulting 4 bit DAC index (entries 0..15)
	);

	reg [7:0]reg3d8 = 8'h0a;	// mode control
	reg [7:0]reg3d9 = 8'h30;	// colour select (palette 1, high intensity)

	always @(posedge CLK)
		if(CE && WR) begin
			if(addr) reg3d9 <= din;
			else reg3d8 <= din;
		end

	assign dout = addr ? reg3d9 : reg3d8;

	wire bw    = reg3d8[2];		// black & white bit -> cyan/red/white set (mode 5)
	wire [3:0]bg = reg3d9[3:0];	// background / border / mode-6 foreground
	wire inten = reg3d9[4];
	wire palsel= reg3d9[5];

	// colour 1/2/3 of the selected CGA palette
	wire [3:0]c1 = {inten, (bw | palsel) ? 3'd3 : 3'd2};	// cyan  : green
	wire [3:0]c2 = {inten, bw ? 3'd4 : palsel ? 3'd5 : 3'd4};	// red   : magenta : red
	wire [3:0]c3 = {inten, (bw | palsel) ? 3'd7 : 3'd6};	// white : brown

	assign color = mode2 ? (pixel[1] ? bg : 4'd0)
	                     : (pixel == 2'b00) ? bg
	                     : (pixel == 2'b01) ? c1
	                     : (pixel == 2'b10) ? c2 : c3;
endmodule
