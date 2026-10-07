`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: opl3seq.v
// Description: Part of the Next186 SoC PC project, OPL3 
// Version 1.0
// Creation date: 13:55:57 02/27/2017
//
// Author: Nicolae Dumitrache 
// e-mail: ndumitrache@opencores.org
//
/////////////////////////////////////////////////////////////////////////////////
// 
// Copyright (C) 2017 Nicolae Dumitrache
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
// Port0 (R) = 4'b0000, Addr[1:0], qempty, ready 
// Port1 (R) = Value[7:0], advance queue
//
// OPL3 timers are not implemented, only the IRQ and FT1, flags are simulated for Adlib detection 
///////////////////////////////////////////////////////////////////////////////////

module opl3(
    input clk, // 50Mhz (min 45Mhz)
    input cpu_clk,
    input [1:0]addr,
    input [7:0]din,
    output [7:0]dout,
    input ce,
    input wr,
    output [15:0]left,
    output [15:0]right,
    input stb44100,
    input reset
    );
	 
	wire seq_wr;
	wire [11:0]seq_addr;
	wire [15:0]seq_rdata;
	wire [15:0]seq_wdata;
    wire [15:0]CPU_ADDR;
	wire [7:0]CPU_DIN;
	wire [7:0]CPU_DOUT;
    wire CPU_WR;
    wire CPU_MREQ; 
    wire CPU_IORQ; 
    reg [1:0]read = 2'b00;
    wire ready;
    reg CE = 1'b0;
    wire [9:0]qdata;
    wire qempty;
    reg [7:0] reg_addr = 0;
    reg t1_mask = 0;
    reg t2_mask = 0;
    reg t1_start = 0;
    reg t2_start = 0;
    reg t1_flag = 0;
    reg t2_flag = 0;
    reg [7:0] t1_data = 0;
    reg [7:0] t2_data = 0;
    reg [7:0] t1_cnt = 0;
    reg [5:0] t1_prescale = 0;

    assign dout = (addr == 2'b00) ? { (t1_flag | t2_flag), t1_flag, t2_flag, 5'b00000 } : 8'h00;
  
/* ////    
   opl3_mem ram_inst (
     .clock(clk), // input clka
     .wren_a(CPU_MREQ & CPU_WR & CE), // input [0 : 0] wea
     .address_a(CPU_ADDR[12:0]), // input [12 : 0] addra
     .data_a(CPU_DOUT), // input [7 : 0] dina
     .q_a(CPU_DIN), // output [7 : 0] douta
     .wren_b(seq_wr), // input [3 : 0] web
     .address_b({seq_addr}), // input [11 : 0] addrb
     .data_b(seq_wdata), // input [15 : 0] dinb
     .q_b(seq_rdata) // output [15 : 0] doutb
   );
*/
/* ////	
    opl3_in in_queue (  // fall through
        .wrclk(cpu_clk),
        .data({addr, din}),
        .wrreq(ce && wr),
        .rdclk(clk),
        .q(qdata),
        .rdreq(CE && CPU_IORQ && !CPU_WR && CPU_ADDR[0]),
        .rdempty(qempty)
    );
*/	
    assign left = 16'h0000;
    assign right = 16'h0000;
    assign ready = 1'b1;

	always @(posedge cpu_clk) begin
        if (reset) begin
            reg_addr <= 8'h00;
            t1_mask <= 1'b0;
            t2_mask <= 1'b0;
            t1_start <= 1'b0;
            t2_start <= 1'b0;
            t1_flag <= 1'b0;
            t2_flag <= 1'b0;
            t1_cnt <= 8'h00;
            t1_prescale <= 6'h00;
        end else begin
            // Prescaler / counter for Timer 1
            if (t1_start) begin
                t1_prescale <= t1_prescale + 1'b1;
                // Advance timer on read of port 388h or when prescaler ticks
                if ((ce && !wr && addr == 2'b00) || (&t1_prescale)) begin
                    if (t1_cnt == 8'hff) begin
                        if (!t1_mask) t1_flag <= 1'b1;
                        t1_cnt <= t1_data;
                    end else begin
                        t1_cnt <= t1_cnt + 1'b1;
                    end
                end
            end

            if (ce && wr) begin
                if (!addr[0]) begin
                    // Port 0x388 / 0x38A: Address register
                    reg_addr <= din;
                end else begin
                    // Port 0x389 / 0x38B: Data register
                    if (reg_addr == 8'h02) begin
                        t1_data <= din;
                    end else if (reg_addr == 8'h03) begin
                        t2_data <= din;
                    end else if (reg_addr == 8'h04) begin
                        if (din[7]) begin
                            t1_flag <= 1'b0;
                            t2_flag <= 1'b0;
                        end
                        t1_mask  <= din[6];
                        t2_mask  <= din[5];
                        t2_start <= din[1];
                        t1_start <= din[0];
                        if (din[0] && !t1_start) begin
                            t1_cnt <= t1_data;
                            t1_prescale <= 6'h00;
                        end
                    end
                end
            end
        end
	end
 
endmodule
