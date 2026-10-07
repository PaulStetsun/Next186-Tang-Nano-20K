`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: sound_gen.v
// Description: Part of the Next186 SoC PC project, 
//		stereo 2x16bit pulse density modulated sound generator
// 	44100 samples/sec
//		Disney Sound Source and Covox Speech compatible
// Version 1.0
// Creation date: Jan2015
//
// Author: Nicolae Dumitrache 
// e-mail: ndumitrache@opencores.org
//
/////////////////////////////////////////////////////////////////////////////////
// 
// Copyright (C) 2015 Nicolae Dumitrache
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
//////////////////////////////////////////////////////////////////////////////////
// Additional Comments: 
//
//	byte write: both channels are the same (Covox emulation), the 8bit sample value is shifted by 8, the channel selector is reset to LEFT
// word write: LEFT first, the queue is updated only after RIGHT value is written
// sample rate: 44100Hz
//////////////////////////////////////////////////////////////////////////////////
`define SPKVOL	11

module soundwave(
		input CLK,
		input CLK44100x256,
		input [15:0]data,
		input we,
		input word,
		input speaker,
		input [15:0]opl3left,
		input [15:0]opl3right,
		output stb44100,
		output full,	// when not full, write max 2x1152 16bit samples
		output dss_full,
		output reg AUDIO_L,
		output reg AUDIO_R
	);

	 reg [31:0]wdata;
	 reg lr = 1'b0;
	 reg [2:0]write = 3'b000;
	 wire qempty;
	 wire [31:0]sample;
	 wire [31:0]sample1 = qempty ? 32'hc000c000 : sample;
	 reg [31:0]lval = 0; 
	 reg [31:0]rval = 0;
	 reg [8:0]clkdiv = 0;
	 reg [15:0]r_opl3left = 0;
	 reg [15:0]r_opl3right = 0;
	 wire [16:0]lmix = {sample1[15], sample1[15:0]} + {r_opl3left[15], r_opl3left} + (speaker << `SPKVOL); // signed mixer left
	 wire [16:0]rmix = {sample1[31], sample1[31:16]} + {r_opl3right[15], r_opl3right} + (speaker << `SPKVOL); // signed mixer right
	 wire [15:0]lclamp = (~|lmix[16:15] | &lmix[16:15]) ? {!lmix[15], lmix[14:0]} : {16{!lmix[16]}}; // clamp to [-32768..32767] and add 32878
	 wire [15:0]rclamp = (~|rmix[16:15] | &rmix[16:15]) ? {!rmix[15], rmix[14:0]} : {16{!rmix[16]}};
	 wire lsign = lval[31:16] < lclamp;
	 wire rsign = rval[31:16] < rclamp;
	 wire [11:0]wrusedw;
	 wire [11:0]rdusedw;
	 assign full = wrusedw >= 12'd2940;
	 assign dss_full = wrusedw >= 12'd16;	// Disney sound source 16-byte FIFO full flag
	 assign stb44100 = clkdiv[8];
	 sndfifo sndfifo_inst 
	 (
	  .wrclk(CLK), // input wr_clk
	  .rdclk(CLK44100x256), // input rd_clk
	  .data(wdata), // input [31 : 0] din
	  .wrreq(|write), // input wr_en
	  .rdreq(clkdiv[8]), // input rd_en
	  .q(sample), // output [31 : 0] dout
	  .wrusedw(wrusedw),
	  .rdusedw(rdusedw),
	  .rdempty(qempty) // output empty
	);
	 always @(posedge CLK44100x256) begin
		clkdiv[8:0] <= clkdiv[7:0] + 1'b1;
		if(clkdiv[8]) begin
	       r_opl3left <= opl3left;
           r_opl3right <= opl3right;
		end
		
		lval <= lval - lval[31:7] + (lsign << 25);
		AUDIO_L <= lsign;

		rval <= rval - rval[31:7] + (rsign << 25);
		AUDIO_R <= rsign;
	 end


	always @(posedge CLK) begin
		if(we) 
			if(word) begin
				lr <= !lr;
				write <= {2'b00, lr};
				if(lr) wdata[31:16] <= data;
				else wdata[15:0] <= data;
			end else begin
				lr <= 1'b0;		// left
				write <= 3'b110;
				wdata <= {1'b1, data[7:0], 8'b00000001, data[7:0], 7'b0000000};
			end
		else write <= write - |write;
	end


endmodule

module sndfifo (
    input  wire        wrclk,
    input  wire        rdclk,
    input  wire [31:0] data,
    input  wire        wrreq,
    input  wire        rdreq,
    output reg  [31:0] q = 32'd0,
    output wire [11:0] wrusedw,
    output wire [11:0] rdusedw,
    output wire        rdempty
);
    localparam DEPTH = 2048;
    localparam ADDR_WIDTH = 11;

    reg [31:0] mem [0:DEPTH-1];

    reg [ADDR_WIDTH:0] wr_ptr = 0;
    reg [ADDR_WIDTH:0] rd_ptr = 0;

    wire [ADDR_WIDTH:0] wr_ptr_gray = wr_ptr ^ (wr_ptr >> 1);
    wire [ADDR_WIDTH:0] rd_ptr_gray = rd_ptr ^ (rd_ptr >> 1);

    reg [ADDR_WIDTH:0] wr_ptr_gray_r1 = 0, wr_ptr_gray_r2 = 0;
    always @(posedge rdclk) begin
        wr_ptr_gray_r1 <= wr_ptr_gray;
        wr_ptr_gray_r2 <= wr_ptr_gray_r1;
    end

    reg [ADDR_WIDTH:0] rd_ptr_gray_w1 = 0, rd_ptr_gray_w2 = 0;
    always @(posedge wrclk) begin
        rd_ptr_gray_w1 <= rd_ptr_gray;
        rd_ptr_gray_w2 <= rd_ptr_gray_w1;
    end

    reg [ADDR_WIDTH:0] wr_ptr_bin_rd;
    integer i;
    always @(*) begin
        wr_ptr_bin_rd[ADDR_WIDTH] = wr_ptr_gray_r2[ADDR_WIDTH];
        for (i = ADDR_WIDTH - 1; i >= 0; i = i - 1)
            wr_ptr_bin_rd[i] = wr_ptr_bin_rd[i+1] ^ wr_ptr_gray_r2[i];
    end

    reg [ADDR_WIDTH:0] rd_ptr_bin_wr;
    integer j;
    always @(*) begin
        rd_ptr_bin_wr[ADDR_WIDTH] = rd_ptr_gray_w2[ADDR_WIDTH];
        for (j = ADDR_WIDTH - 1; j >= 0; j = j - 1)
            rd_ptr_bin_wr[j] = rd_ptr_bin_wr[j+1] ^ rd_ptr_gray_w2[j];
    end

    always @(posedge wrclk) begin
        if (wrreq) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    assign rdempty = (rd_ptr == wr_ptr_bin_rd);
    always @(posedge rdclk) begin
        if (rdreq && !rdempty) begin
            q <= mem[rd_ptr[ADDR_WIDTH-1:0]];
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    assign wrusedw = wr_ptr - rd_ptr_bin_wr;
    assign rdusedw = wr_ptr_bin_rd - rd_ptr;

endmodule

