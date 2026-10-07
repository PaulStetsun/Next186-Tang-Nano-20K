// ====================================================================
// sdc_pc.v - USB Floppy & Flash Storage Controller for Next186 SoC
// Connects 80186 I/O ports 0x0270-0x0277 to RP2040 Companion SPI Target 3 (SDC)
// Provides 512-byte sector FIFO with 16-bit fast REP INSW / OUTSW support
// Uses 2x Gowin_SP_256x8 dedicated BSRAM blocks (0 LUT overhead, 0 timing issues)
// ====================================================================

`timescale 1ns / 1ps

module sdc_pc (
    input             clk,          // 21.6 MHz CPU clock
    input             reset,

    // 80186 I/O bus interface (Ports 0x0270 - 0x0277)
    input             CS,           // IORQ && CPU_CE && (PORT_ADDR[15:3] == 16'h0270 >> 3)
    input             WR,
    input             WORD,         // 1 = 16-bit access, 0 = 8-bit access
    input      [2:0]  addr,         // PORT_ADDR[2:0] (0..7)
    input      [15:0] din,          // CPU_DOUT
    output reg [15:0] dout,         // data to CPU bus
    output            oe,           // output enable for PORT_IN mux

    // SPI interface from mcu_spi.v (Target 3: SDC)
    input             mcu_strobe,   // pulsed for each incoming SPI byte
    input             mcu_start,    // 1 for first command byte of SPI transaction
    input      [7:0]  data_in,      // byte from MCU
    output reg [7:0]  data_out,     // byte to MCU
    output reg        irq           // active-low IRQ to Pico (pin 51)
);

    // CPU registers
    reg        busy;
    reg        drq;
    reg        err;
    reg        is_write;
    reg        sel_drive;           // 0 = Floppy A:, 1 = USB Flash D:
    reg [31:0] lba;
    reg [7:0]  sector_count;
    reg [7:0]  cpu_ptr;             // 0..255 word pointer
    reg        cpu_bodd;
    reg        pending_req;

    // SPI state
    reg [7:0]  spi_cmd;
    reg [9:0]  spi_cnt;
    reg [7:0]  spi_subcmd;
    reg [7:0]  spi_img_id;
    reg [8:0]  spi_ptr;             // 0..511 byte pointer for MCU transfers

    assign oe = CS && ~WR;

    // ----------------------------------------------------------------
    // 512-byte Sector Buffer using 2x Gowin_SP_256x8 BSRAM Primitives
    // Bank Low (even bytes) + Bank High (odd bytes)
    // ----------------------------------------------------------------
    wire [7:0] ram_addr = busy ? spi_ptr[8:1] : cpu_ptr;
    wire       spi_wr = (mcu_strobe && spi_cmd == 8'h08 && spi_subcmd == 8'h02 && spi_cnt >= 10'd2) ||
                        (mcu_strobe && spi_cmd == 8'h05 && spi_cnt >= 10'd4 && spi_cnt < 10'd516);
    wire       cpu_wr = CS && WR && (addr == 3'd7);

    wire wre_lo = busy ? (spi_wr && ~spi_ptr[0]) : (cpu_wr && (WORD || ~cpu_bodd));
    wire wre_hi = busy ? (spi_wr &&  spi_ptr[0]) : (cpu_wr && (WORD ||  cpu_bodd));

    wire [7:0] din_lo = busy ? data_in : din[7:0];
    wire [7:0] din_hi = busy ? data_in : (WORD ? din[15:8] : din[7:0]);

    wire [7:0] dout_lo;
    wire [7:0] dout_hi;

    Gowin_SP_256x8 ram_lo_inst (
        .dout(dout_lo),
        .clk(clk),
        .oce(1'b1),
        .ce(1'b1),
        .reset(reset),
        .wre(wre_lo),
        .ad(ram_addr),
        .din(din_lo)
    );

    Gowin_SP_256x8 ram_hi_inst (
        .dout(dout_hi),
        .clk(clk),
        .oce(1'b1),
        .ce(1'b1),
        .reset(reset),
        .wre(wre_hi),
        .ad(ram_addr),
        .din(din_hi)
    );

    wire [15:0] cpu_fifo_q = {dout_hi, dout_lo};
    wire [7:0]  spi_fifo_q = spi_ptr[0] ? dout_hi : dout_lo;

    // ----------------------------------------------------------------
    // CPU Read Port Bus Mux
    // ----------------------------------------------------------------
    wire [15:0] status_reg = {8'h00, ~busy, 2'b00, 1'b0, 1'b1, err, drq, busy};

    always @(*) begin
        case (addr)
            3'd0: dout = status_reg;
            3'd1: dout = {15'd0, sel_drive};
            3'd2: dout = {8'h00, lba[7:0]};
            3'd3: dout = {8'h00, lba[15:8]};
            3'd4: dout = {8'h00, lba[23:16]};
            3'd5: dout = {8'h00, lba[31:24]};
            3'd6: dout = {8'h00, sector_count};
            3'd7: dout = WORD ? cpu_fifo_q : (cpu_bodd ? {8'h00, cpu_fifo_q[15:8]} : {8'h00, cpu_fifo_q[7:0]});
            default: dout = 16'h0000;
        endcase
    end

    // ----------------------------------------------------------------
    // Control State Machine (CPU registers & SPI transactions)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            busy         <= 1'b0;
            drq          <= 1'b0;
            err          <= 1'b0;
            is_write     <= 1'b0;
            sel_drive    <= 1'b0;
            lba          <= 32'd0;
            sector_count <= 8'd1;
            cpu_ptr      <= 8'd0;
            cpu_bodd     <= 1'b0;
            pending_req  <= 1'b0;
            irq          <= 1'b1;         // active-low idle high
            data_out     <= 8'h00;
            spi_cmd      <= 8'h00;
            spi_cnt      <= 10'd0;
            spi_subcmd   <= 8'h00;
            spi_img_id   <= 8'h00;
            spi_ptr      <= 9'd0;
        end else begin
            // ------------------------------------------------------------
            // CPU Port Control
            // ------------------------------------------------------------
            if (CS && WR) begin
                case (addr)
                    3'd0: begin
                        if (din[7:0] == 8'h01) begin
                            // CMD: READ SECTOR
                            busy        <= 1'b1;
                            drq         <= 1'b0;
                            err         <= 1'b0;
                            is_write    <= 1'b0;
                            cpu_ptr     <= 8'd0;
                            cpu_bodd    <= 1'b0;
                            pending_req <= 1'b1;
                            irq         <= 1'b0; // signal Pico
                        end else if (din[7:0] == 8'h02) begin
                            // CMD: WRITE SECTOR
                            busy        <= 1'b1;
                            drq         <= 1'b0;
                            err         <= 1'b0;
                            is_write    <= 1'b1;
                            cpu_ptr     <= 8'd0;
                            cpu_bodd    <= 1'b0;
                            pending_req <= 1'b1;
                            irq         <= 1'b0;
                        end else if (din[7:0] == 8'h03) begin
                            // CMD: RESET FIFO / CONTROLLER
                            busy        <= 1'b0;
                            drq         <= 1'b1;
                            err         <= 1'b0;
                            is_write    <= 1'b0;
                            cpu_ptr     <= 8'd0;
                            cpu_bodd    <= 1'b0;
                            pending_req <= 1'b0;
                            irq         <= 1'b1;
                        end
                    end
                    3'd1: sel_drive    <= din[0];
                    3'd2: lba[7:0]     <= din[7:0];
                    3'd3: lba[15:8]    <= din[7:0];
                    3'd4: lba[23:16]   <= din[7:0];
                    3'd5: lba[31:24]   <= din[7:0];
                    3'd6: sector_count <= din[7:0];
                    3'd7: begin
                        // FIFO data write (advance pointer)
                        if (WORD) begin
                            cpu_ptr <= cpu_ptr + 8'd1;
                        end else begin
                            cpu_bodd <= ~cpu_bodd;
                            if (cpu_bodd) cpu_ptr <= cpu_ptr + 8'd1;
                        end
                    end
                endcase
            end else if (CS && ~WR && addr == 3'd7) begin
                // FIFO data read (advance pointer)
                if (WORD) begin
                    cpu_ptr <= cpu_ptr + 8'd1;
                end else begin
                    cpu_bodd <= ~cpu_bodd;
                    if (cpu_bodd) cpu_ptr <= cpu_ptr + 8'd1;
                end
            end

            // ------------------------------------------------------------
            // SPI Target 3 (SDC) Packet Processing
            // ------------------------------------------------------------
            if (mcu_strobe) begin
                if (mcu_start) begin
                    spi_cmd <= data_in;
                    spi_cnt <= 10'd0;
                    spi_ptr <= 9'd0;

                    case (data_in)
                        8'h01: data_out <= 8'h80; // SPI_SDC_STATUS: card ready
                        8'h08: data_out <= 8'h80; // SPI_SDC_IMAGE: ready
                        default: data_out <= 8'h00;
                    endcase
                end else begin
                    spi_cnt <= spi_cnt + 10'd1;

                    // --- Command 1: SPI_SDC_STATUS ---
                    if (spi_cmd == 8'h01) begin
                        case (spi_cnt)
                            10'd0: begin
                                if (pending_req)
                                    data_out <= {is_write, 5'b00000, sel_drive ? 2'b10 : 2'b01};
                                else
                                    data_out <= 8'h00;
                            end
                            10'd1: data_out <= lba[31:24];
                            10'd2: data_out <= lba[23:16];
                            10'd3: data_out <= lba[15:8];
                            10'd4: begin
                                data_out <= lba[7:0];
                                irq <= 1'b1; // acknowledge IRQ
                            end
                            default: data_out <= 8'h00;
                        endcase
                    end

                    // --- Command 8: SPI_SDC_IMAGE ---
                    else if (spi_cmd == 8'h08) begin
                        if (spi_cnt == 10'd0) begin
                            spi_subcmd <= data_in;
                            data_out <= 8'h80;
                        end else if (spi_cnt == 10'd1) begin
                            spi_img_id <= data_in;
                            data_out <= 8'h80;
                            spi_ptr  <= 9'd0;
                            if (spi_subcmd == 8'hEE) begin
                                // Subcommand 0xEE: Device Error
                                busy        <= 1'b0;
                                drq         <= 1'b0;
                                err         <= 1'b1;
                                pending_req <= 1'b0;
                            end
                        end else begin
                            if (spi_subcmd == 8'h02) begin
                                // Subcommand 0x02: STREAM WRITE (MCU -> FPGA RAM)
                                spi_ptr <= spi_ptr + 9'd1;
                                if (spi_ptr == 9'd511) begin
                                    busy        <= 1'b0;
                                    drq         <= 1'b1;
                                    pending_req <= 1'b0;
                                    cpu_ptr     <= 8'd0;
                                    cpu_bodd    <= 1'b0;
                                end
                                data_out <= 8'h00;
                            end else if (spi_subcmd == 8'h00) begin
                                case (spi_cnt)
                                    10'd2: data_out <= 8'h80;
                                    10'd3: data_out <= 8'h00;
                                    10'd4: data_out <= 8'h01;
                                    default: data_out <= 8'h00;
                                endcase
                            end
                        end
                    end

                    // --- Command 3: SPI_SDC_MCU_READ (MCU reads sector from FPGA RAM) ---
                    else if (spi_cmd == 8'h03) begin
                        if (spi_cnt < 10'd4) begin
                            data_out <= 8'h00;
                            spi_ptr  <= 9'd0;
                        end else if (spi_cnt == 10'd4) begin
                            data_out <= 8'h00; // ready
                        end else if (spi_cnt >= 10'd5 && spi_cnt < 10'd517) begin
                            data_out <= spi_fifo_q;
                            spi_ptr  <= spi_ptr + 9'd1;

                            if (spi_cnt == 10'd516) begin
                                busy        <= 1'b0;
                                drq         <= 1'b1;
                                pending_req <= 1'b0;
                            end
                        end else begin
                            data_out <= 8'h00;
                        end
                    end

                    // --- Command 5: SPI_SDC_MCU_WRITE ---
                    else if (spi_cmd == 8'h05) begin
                        if (spi_cnt < 10'd4) begin
                            data_out <= 8'h00;
                            spi_ptr  <= 9'd0;
                        end else if (spi_cnt >= 10'd4 && spi_cnt < 10'd516) begin
                            spi_ptr <= spi_ptr + 9'd1;
                            data_out <= 8'h00;

                            if (spi_ptr == 9'd511) begin
                                busy        <= 1'b0;
                                drq         <= 1'b1;
                                pending_req <= 1'b0;
                                cpu_ptr     <= 8'd0;
                                cpu_bodd    <= 1'b0;
                            end
                        end else begin
                            data_out <= 8'h00;
                        end
                    end else begin
                        data_out <= 8'h00;
                    end
                end
            end
        end
    end

endmodule
