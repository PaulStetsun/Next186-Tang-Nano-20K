//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: KB_8042.v
// Description: Part of the Next186 SoC PC project, keyboard/mouse PS2 controller
//		Simplified 8042 implementation
// Version 1.0
// Creation date: Jan2013
//
// Author: Nicolae Dumitrache 
// e-mail: ndumitrache@opencores.org
//
/////////////////////////////////////////////////////////////////////////////////
// 
// Copyright (C) 2013 Nicolae Dumitrache
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
// http://www.computer-engineering.org/ps2keyboard/
// http://wiki.osdev.org/%228042%22_PS/2_Controller
// http://wiki.osdev.org/Mouse_Input
//
//	Primary connection
//		NET "PS2_CLK1" LOC = "W12" | IOSTANDARD = LVCMOS33 | DRIVE = 8 | SLEW = SLOW ;
//		NET "PS2_DATA1" LOC = "V11" | IOSTANDARD = LVCMOS33 | DRIVE = 8 | SLEW = SLOW ;
//	Secondary connection (requires Y-splitter cable)
//		NET "PS2_CLK2" LOC = "U11" | IOSTANDARD = LVCMOS33 | DRIVE = 8 | SLEW = SLOW ;
//		NET "PS2_DATA2" LOC = "Y12" | IOSTANDARD = LVCMOS33 | DRIVE = 8 | SLEW = SLOW ;
//////////////////////////////////////////////////////////////////////////////////
// 12Feb2018 - fix KB connection issue
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module KB_Mouse_8042(
    input CS,
	 input WR,
    input cmd,			// 0x60 = data, 0x64 = cmd
	 input [7:0]din,
	 output [7:0]dout, 
	 input clk,			// cpu CLK
	 output I_KB,		// interrupt keyboard
	 output I_MOUSE,  // interrupt mouse
	 output reg CPU_RST = 0,
	 inout PS2_CLK1,
	 inout PS2_CLK2,
	 inout PS2_DATA1,
	 inout PS2_DATA2,
	 // External scancode injection from FPGA Companion (USB HID via RP2040)
	 // When inject_kb_stb is pulsed, inject_kb_data is pushed into the
	 // keyboard output buffer exactly as if it arrived from the PS/2 line.
	 // Clean path for USB keyboard without bit-banging PS/2 pins.
	 input       inject_kb_stb,
	 input [7:0] inject_kb_data,
	 input       inject_mouse_stb,
	 input [7:0] inject_mouse_data
    );
	 
//	status bit5 = MOBF (mouse to host buffer full - with OBF), bit4=INH, bit2(1-initialized ok), bit1(IBF-input buffer full - host to kb/mouse), bit0(OBF-output buffer full - kb/mouse to host)
	// INT+INT2 enabled, EN+EN2=0 so keyboard/mouse are ENABLED from reset
	// (old value 4'b1100 had EN=1 → keyboard disabled → inject never accepted)
	reg [3:0]cmdbyte = 4'b0011; // EN2,EN,INT2,INT
	reg translate_en = 1'b0; // Bit 6 of 8042 command byte (Set 2 -> Set 1 translation)
	reg set1_break = 1'b0;

	function [7:0] set2to1;
		input [7:0] s2;
		begin
			case (s2)
				8'h01: set2to1 = 8'h43; // F9
				8'h03: set2to1 = 8'h3F; // F5
				8'h04: set2to1 = 8'h3D; // F3
				8'h05: set2to1 = 8'h3B; // F1
				8'h06: set2to1 = 8'h3C; // F2
				8'h07: set2to1 = 8'h58; // F12
				8'h09: set2to1 = 8'h44; // F10
				8'h0A: set2to1 = 8'h42; // F8
				8'h0B: set2to1 = 8'h40; // F6
				8'h0C: set2to1 = 8'h3E; // F4
				8'h0D: set2to1 = 8'h0F; // Tab
				8'h0E: set2to1 = 8'h29; // ` ~
				8'h11: set2to1 = 8'h38; // LAlt / RAlt
				8'h12: set2to1 = 8'h2A; // LShift
				8'h14: set2to1 = 8'h1D; // LCtrl / RCtrl
				8'h15: set2to1 = 8'h10; // Q
				8'h16: set2to1 = 8'h02; // 1
				8'h1A: set2to1 = 8'h2C; // Z
				8'h1B: set2to1 = 8'h1F; // S
				8'h1C: set2to1 = 8'h1E; // A
				8'h1D: set2to1 = 8'h11; // W
				8'h1E: set2to1 = 8'h03; // 2
				8'h1F: set2to1 = 8'h5B; // L-GUI
				8'h21: set2to1 = 8'h2E; // C
				8'h22: set2to1 = 8'h2D; // X
				8'h23: set2to1 = 8'h20; // D
				8'h24: set2to1 = 8'h12; // E
				8'h25: set2to1 = 8'h05; // 4
				8'h26: set2to1 = 8'h04; // 3
				8'h27: set2to1 = 8'h5C; // R-GUI
				8'h29: set2to1 = 8'h39; // Space
				8'h2A: set2to1 = 8'h2F; // V
				8'h2B: set2to1 = 8'h21; // F
				8'h2C: set2to1 = 8'h14; // T
				8'h2D: set2to1 = 8'h13; // R
				8'h2E: set2to1 = 8'h06; // 5
				8'h2F: set2to1 = 8'h5D; // App/Menu
				8'h31: set2to1 = 8'h31; // N
				8'h32: set2to1 = 8'h30; // B
				8'h33: set2to1 = 8'h23; // H
				8'h34: set2to1 = 8'h22; // G
				8'h35: set2to1 = 8'h15; // Y
				8'h36: set2to1 = 8'h07; // 6
				8'h3A: set2to1 = 8'h32; // M
				8'h3B: set2to1 = 8'h25; // J
				8'h3C: set2to1 = 8'h16; // U
				8'h3D: set2to1 = 8'h08; // 7
				8'h3E: set2to1 = 8'h09; // 8
				8'h41: set2to1 = 8'h33; // , <
				8'h42: set2to1 = 8'h26; // K
				8'h43: set2to1 = 8'h17; // I
				8'h44: set2to1 = 8'h18; // O
				8'h45: set2to1 = 8'h0B; // 0
				8'h46: set2to1 = 8'h0A; // 9
				8'h49: set2to1 = 8'h34; // . >
				8'h4A: set2to1 = 8'h35; // / ?
				8'h4B: set2to1 = 8'h27; // L
				8'h4C: set2to1 = 8'h27; // ; :
				8'h4D: set2to1 = 8'h19; // P
				8'h4E: set2to1 = 8'h0C; // - _
				8'h52: set2to1 = 8'h28; // ' "
				8'h54: set2to1 = 8'h1A; // [ {
				8'h55: set2to1 = 8'h0D; // = +
				8'h58: set2to1 = 8'h3A; // CapsLock
				8'h59: set2to1 = 8'h36; // RShift
				8'h5A: set2to1 = 8'h1C; // Enter
				8'h5B: set2to1 = 8'h1B; // ] }
				8'h5D: set2to1 = 8'h2B; // \ |
				8'h66: set2to1 = 8'h0E; // Backspace
				8'h69: set2to1 = 8'h4F; // KP 1 / End
				8'h6B: set2to1 = 8'h4B; // KP 4 / Left
				8'h6C: set2to1 = 8'h47; // KP 7 / Home
				8'h70: set2to1 = 8'h52; // KP 0 / Ins
				8'h71: set2to1 = 8'h53; // KP . / Del
				8'h72: set2to1 = 8'h50; // KP 2 / Down
				8'h73: set2to1 = 8'h4C; // KP 5
				8'h74: set2to1 = 8'h4D; // KP 6 / Right
				8'h75: set2to1 = 8'h48; // KP 8 / Up
				8'h76: set2to1 = 8'h01; // Esc
				8'h77: set2to1 = 8'h45; // NumLock
				8'h78: set2to1 = 8'h57; // F11
				8'h79: set2to1 = 8'h4E; // KP +
				8'h7A: set2to1 = 8'h51; // KP 3 / PgDn
				8'h7B: set2to1 = 8'h4A; // KP -
				8'h7C: set2to1 = 8'h37; // KP *
				8'h7D: set2to1 = 8'h49; // KP 9 / PgUp
				8'h7E: set2to1 = 8'h46; // ScrollLock
				8'h83: set2to1 = 8'h41; // F7
				default: set2to1 = s2;
			endcase
		end
	endfunction
	reg wcfg = 1'b0;	// write config byte
	reg next_mouse = 1'b0;
	reg ctl_outb = 1'b0;
	reg [9:0]wr_data;
	reg [7:0]clkdiv128 = 0;
	reg [7:0]cnt100us = 0; // single delay counter for both kb and mouse
	reg wr_mouse = 1'b0;
	reg wr_kb = 1'b0;
	reg rd_kb = 1'b0;
	reg rd_mouse = 1'b0;
	reg OBF = 1'b0;
	reg MOBF = 1'b0;
	reg [7:0]s_data;

	// USB inject FIFO — absorb single-cycle pulses even when OBF is full
	reg [7:0] inj_q [0:7];
	reg [2:0] inj_w = 3'd0;
	reg [2:0] inj_r = 3'd0;
	reg [3:0] inj_n = 4'd0;
	wire inj_avail = (inj_n != 4'd0);
	reg [7:0] minj_q [0:15];
	reg [3:0] minj_w = 4'd0;
	reg [3:0] minj_r = 4'd0;
	reg [4:0] minj_n = 5'd0;
	wire minj_avail = (minj_n != 5'd0);

	wire [7:0]kb_data;
	wire [7:0]mouse_data;
	wire kb_data_out_ready;
	wire kb_data_in_ready;
	wire mouse_data_out_ready;
	wire mouse_data_in_ready;
	wire IBF = wr_kb | wr_mouse;
	wire kb_shift;
	wire mouse_shift;
	
	assign dout = cmd ? {2'b00, MOBF, 1'b1, wcfg, 1'b1, IBF, OBF | MOBF | ctl_outb} : ctl_outb ? {1'b0, translate_en, cmdbyte[3:2], 2'b00, cmdbyte[1:0]} : s_data; //MOBF ? mouse_data : kb_data;
	assign I_KB = cmdbyte[0] & OBF; 			// INT & OBF
	assign I_MOUSE = cmdbyte[1] & MOBF; 	// INT2 & MOBF
	
	PS2Interface Keyboard
	(
		.PS2_CLK(PS2_CLK1),
		.PS2_DATA(PS2_DATA1),
		.clk(clk),
		.rd(rd_kb),
		.wr(wr_kb),
		.data_in(wr_data[0]),
		.data_out(kb_data),
		.data_out_ready(kb_data_out_ready),
		.data_in_ready(kb_data_in_ready),
		.delay100us(cnt100us[7]),
		.data_shift(kb_shift),
		.clk_sample(clkdiv128[7])
	);

	PS2Interface Mouse
	(
		.PS2_CLK(PS2_CLK2),
		.PS2_DATA(PS2_DATA2),
		.clk(clk),
		.rd(rd_mouse),
		.wr(wr_mouse),
		.data_in(wr_data[0]),
		.data_out(mouse_data),
		.data_out_ready(mouse_data_out_ready),
		.data_in_ready(mouse_data_in_ready),
		.delay100us(cnt100us[7]),
		.data_shift(mouse_shift),
		.clk_sample(clkdiv128[7])
	);
	
	reg [7:0] auto_kb_q [0:3];
	reg [2:0] auto_kb_len = 0;
	reg [7:0] auto_mouse_q [0:3];
	reg [2:0] auto_mouse_len = 0;

	always @(posedge clk) begin
		CPU_RST <= 0;
		wr_kb <= 1'b0;
		wr_mouse <= 1'b0;
		rd_kb <= 1'b0;
		rd_mouse <= 1'b0;

		clkdiv128 <= clkdiv128[6:0] + 1'b1;
		if(CS & WR & ~cmd & ~wcfg) cnt100us <= 0; // reset 100us counter for PS2 writing
		else if(!cnt100us[7] & clkdiv128[7]) cnt100us <= cnt100us + 1'b1;
		
		
		// --- USB inject FIFO (enqueue) ---
		// Always enqueue; never gated by 8042 disable flags.
		if (inject_kb_stb && (inj_n != 4'd8)) begin
			inj_q[inj_w] <= inject_kb_data;
			inj_w <= inj_w + 3'd1;
			inj_n <= inj_n + 4'd1;
		end else if (inject_mouse_stb && (minj_n != 5'd16)) begin
			minj_q[minj_w] <= inject_mouse_data;
			minj_w <= minj_w + 4'd1;
			minj_n <= minj_n + 5'd1;
		end

		// --- Deliver to host buffer (dequeue) ---
		// Only when not also enqueueing (avoids NBA race on inj_n / minj_n)
		if (~OBF & ~MOBF & ~inject_kb_stb & ~inject_mouse_stb) begin
			if (auto_kb_len != 3'd0 & ~cmdbyte[2]) begin
				OBF <= 1'b1;
				s_data <= auto_kb_q[0];
				auto_kb_q[0] <= auto_kb_q[1];
				auto_kb_q[1] <= auto_kb_q[2];
				auto_kb_len <= auto_kb_len - 1'b1;
			end else if (auto_mouse_len != 3'd0 & ~cmdbyte[3]) begin
				MOBF <= 1'b1;
				s_data <= auto_mouse_q[0];
				auto_mouse_q[0] <= auto_mouse_q[1];
				auto_mouse_q[1] <= auto_mouse_q[2];
				auto_mouse_len <= auto_mouse_len - 1'b1;
			end else if (inj_n != 4'd0) begin
				if (translate_en && (inj_q[inj_r] == 8'hF0)) begin
					set1_break <= 1'b1;
					inj_r <= inj_r + 3'd1;
					inj_n <= inj_n - 4'd1;
				end else if (translate_en && (inj_q[inj_r] == 8'hE0 || inj_q[inj_r] == 8'hE1)) begin
					// Drop E0/E1 prefix under XT Set 1 translation:
					// Standard PC/XT (84-key) drivers do not recognize E0 and treat it as break code 0x60
					inj_r <= inj_r + 3'd1;
					inj_n <= inj_n - 4'd1;
				end else begin
					OBF <= 1'b1;
					if (translate_en) begin
						s_data <= (set1_break ? 8'h80 : 8'h00) | set2to1(inj_q[inj_r]);
						set1_break <= 1'b0;
					end else begin
						s_data <= inj_q[inj_r];
					end
					inj_r <= inj_r + 3'd1;
					inj_n <= inj_n - 4'd1;
				end
			end else if (minj_n != 5'd0 & ~cmdbyte[3]) begin
				MOBF <= 1'b1;
				s_data <= minj_q[minj_r];
				minj_r <= minj_r + 4'd1;
				minj_n <= minj_n - 5'd1;
			end else if (kb_data_out_ready & ~rd_kb & ~cmdbyte[2]) begin
				if (translate_en && (kb_data == 8'hF0)) begin
					set1_break <= 1'b1;
					rd_kb <= 1'b1;
				end else if (translate_en && (kb_data == 8'hE0 || kb_data == 8'hE1)) begin
					rd_kb <= 1'b1;
				end else begin
					OBF <= 1'b1;
					if (translate_en) begin
						s_data <= (set1_break ? 8'h80 : 8'h00) | set2to1(kb_data);
						set1_break <= 1'b0;
					end else begin
						s_data <= kb_data;
					end
					rd_kb <= 1'b1;
				end
			end
		end
		
		if(kb_shift | mouse_shift) wr_data <= {1'b1, wr_data[9:1]};
		
		if(CS) 
			if(WR)
				if(cmd)	// 0x64 write
					case(din)
						8'h20: ctl_outb <= 1'b1;	// read config byte
						8'h60: wcfg <= 1;			// write config byte
						8'ha7: cmdbyte[3] <= 1;	// disable mouse
						8'ha8: cmdbyte[3] <= 0;	// enable mouse
						8'had: cmdbyte[2] <= 1;	// disable kb
						8'hae: cmdbyte[2] <= 0;	// enable kb
						8'hd4: next_mouse <= 1;	//	write next byte to mouse
						8'h90: begin
							translate_en <= 1'b1;
							set1_break <= 1'b0;
							OBF <= 1'b0;
							inj_r <= 3'd0;
							inj_w <= 3'd0;
							inj_n <= 4'd0;
						end
						8'h91: begin
							translate_en <= 1'b0;
							set1_break <= 1'b0;
							OBF <= 1'b0;
							inj_r <= 3'd0;
							inj_w <= 3'd0;
							inj_n <= 4'd0;
						end
						/*8'hf0, 8'hf2, 8'hf4, 8'hf6, 8'hf8, 8'hfa, 8'hfc,*/ 8'hfe: CPU_RST <= 1; // CPU reset
					endcase 
				else begin	// 0x60 write
					if(wcfg) begin
						cmdbyte <= {din[5:4], din[1:0]};
						translate_en <= din[6];
						set1_break <= 1'b0;
					end
					else begin
						next_mouse <= 0;
						wr_mouse <= next_mouse;
						wr_kb <= ~next_mouse;
						wr_data <= {~^din, din, 1'b0};
						if(!next_mouse) begin
							if(din == 8'hff) begin
								auto_kb_q[0] <= 8'hfa;
								auto_kb_q[1] <= 8'haa;
								auto_kb_len  <= 3'd2;
							end else if(din == 8'hf2) begin
								auto_kb_q[0] <= 8'hfa;
								auto_kb_q[1] <= 8'hab;
								auto_kb_q[2] <= 8'h83;
								auto_kb_len  <= 3'd3;
							end else begin
								auto_kb_q[0] <= 8'hfa;
								auto_kb_len  <= 3'd1;
							end
						end else begin
							if(din == 8'hff) begin
								auto_mouse_q[0] <= 8'hfa;
								auto_mouse_q[1] <= 8'haa;
								auto_mouse_q[2] <= 8'h00;
								auto_mouse_len  <= 3'd3;
							end else if(din == 8'hf2) begin
								auto_mouse_q[0] <= 8'hfa;
								auto_mouse_q[1] <= 8'h00;
								auto_mouse_len  <= 3'd2;
							end else begin
								auto_mouse_q[0] <= 8'hfa;
								auto_mouse_len  <= 3'd1;
							end
						end
					end
					wcfg <= 0;
				end
			else 	// read data
				if(~cmd) begin	
					ctl_outb <= 1'b0;
					if(!ctl_outb) begin
						OBF <= 1'b0;
						MOBF <= 1'b0;
						rd_kb <= OBF;
						rd_mouse <= MOBF;
					end
				end
	end
endmodule


module PS2Interface(
	 inout PS2_CLK,
	 inout PS2_DATA,
	 input clk,
	 input rd,				// enable PS2 data reading
	 input wr,				// can write data from controller to PS2
	 input data_in,		// data from controller
	 input delay100us,
	 output [7:0]data_out,	// data from PS2
	 output reg data_out_ready = 1,	// PS2 received data ready
	 output reg data_in_ready = 1,	// PS2 sent data ready
	 output data_shift,
	 input clk_sample
	);
	
	initial data_out_ready = 1;
	initial data_in_ready = 1;
	
	reg [1:0]s_clk = 2'b11;
	wire ps2_clk_fall = s_clk == 2'b10;
	reg [9:0]data = 0;
	reg rd_progress = 1'b0;
	reg s_ps2_clk = 1'b1;
	reg rclk = 1'b1;
	reg rdata = 1'b1;
	reg s_ps2_data = 1'b1;
	
	assign PS2_CLK = rclk ? 1'bz : 1'b0;
	assign PS2_DATA = rdata ? 1'bz : 1'b0;
	assign data_out = data[7:0];
	assign data_shift = ~data_in_ready && delay100us && ps2_clk_fall;

	always @(posedge clk) begin
		if(clk_sample) begin
			s_ps2_clk <= PS2_CLK; 	// debounce PS2 clock and data
			s_ps2_data <= PS2_DATA;
		end
		
		s_clk <= {s_clk[0], s_ps2_clk};
		if(data_out_ready) rd_progress <= 1'b0;

		if(~data_in_ready) begin	// send data to PS2
			if(data_shift) data_in_ready <= data_in ^ s_ps2_data;
		end else if(wr && ~rd_progress) data_in_ready <= 1'b0;	// initiate data sending to PS2
		else if(~data_out_ready) begin	// receive data from PS2
			if(ps2_clk_fall) begin
				rd_progress <= 1'b1;
				if(rd_progress) {data, data_out_ready} <= {s_ps2_data, data[9:1], ~data[0]}; // receive is ended by data[9]
				else data <= 10'b0111111111;
			end
		end else if(rd) data_out_ready <= 1'b0; // initiate data receiving from PS2

		rclk <= ((~data_out_ready & data_in_ready) | (~data_in_ready & delay100us));
		rdata <= (data_in_ready | data_in | ~delay100us);
	end
endmodule
