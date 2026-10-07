/*
 * sysctrl_pc.v – minimal system-control target for Next186 + FPGA Companion
 *
 * Implements just enough for the Companion to recognise the core and
 * not spam the SPI bus:
 *   CMD 0  SPI_SYS_STATUS  – return core id + coldboot flag
 *   CMD 1  SPI_SYS_LEDS    – accept LED value (ignored for now)
 *   CMD 3  SPI_SYS_BUTTONS – return onboard button state
 *   CMD 5  SPI_SYS_IRQ_CTRL
 *   CMD 6  SPI_SYS_IRQ_SRC
 *
 * Everything else is acknowledged with 0x00 so the MCU does not hang.
 */

module sysctrl_pc (
  input            clk,
  input            reset,

  input            data_in_strobe,
  input            data_in_start,
  input      [7:0] data_in,
  output reg [7:0] data_out,

  // physical buttons (active-high on Tang Nano 20K)
  input      [1:0] buttons,

  // IRQ lines from other targets
  input            hid_irq_n,
  input            sdc_irq_n,

  // interrupt line to Companion (active low)
  output           int_out_n,

  // optional LED mirror
  output reg [1:0] leds
);

  // Core identification – arbitrary unique value so Companion logs it.
  // 0x4E = 'N' for Next186
  localparam [7:0] CORE_ID = 8'h4E;

  reg [3:0] state;
  reg [7:0] command;
  reg       coldboot;
  reg       sys_int;
  reg [1:0] buttons_d, buttons_d2;
  reg       btn_irq_en;

  // any pending system interrupt pulls IRQ low
  assign int_out_n = sys_int ? 1'b0 : 1'b1;

  always @(posedge clk) begin
    if (reset) begin
      state       <= 4'd0;
      data_out    <= 8'h00;
      coldboot    <= 1'b1;
      sys_int     <= 1'b1;          // request attention after reset
      leds        <= 2'b00;
      btn_irq_en  <= 1'b0;
    end else begin
      // button edge detection → raise interrupt
      buttons_d  <= buttons;
      buttons_d2 <= buttons_d;
      if (btn_irq_en && (buttons_d2 != buttons_d)) begin
        sys_int    <= 1'b1;
        btn_irq_en <= 1'b0;
      end

      if (data_in_strobe) begin
        if (data_in_start) begin
          state   <= 4'd0;
          command <= data_in;
        end else begin
          state <= state + 4'd1;

          // ----------------------------------------------------------
          // CMD 0 – STATUS
          // Companion reads several bytes; we return:
          //   byte0 = CORE_ID
          //   byte1 = coldboot (1 on first query after FPGA config)
          //   byte2.. = 0
          // ----------------------------------------------------------
          if (command == 8'd0) begin
            if (state == 4'd0) data_out <= CORE_ID;
            if (state == 4'd1) begin
              data_out <= {7'd0, coldboot};
              coldboot <= 1'b0;          // clear after first read
              sys_int  <= 1'b0;
            end
            if (state >= 4'd2) data_out <= 8'h00;
          end

          // ----------------------------------------------------------
          // CMD 1 – LEDs (two bits)
          // ----------------------------------------------------------
          if (command == 8'd1 && state == 4'd0)
            leds <= data_in[1:0];

          // ----------------------------------------------------------
          // CMD 3 – BUTTONS
          // ----------------------------------------------------------
          if (command == 8'd3) begin
            if (state == 4'd0) begin
              data_out   <= {6'd0, buttons_d2};
              btn_irq_en <= 1'b1;        // re-arm edge detect
              sys_int    <= 1'b0;
            end
          end

          // ----------------------------------------------------------
          // CMD 5 – IRQ_CTRL (ack / mask)
          // ----------------------------------------------------------
          if (command == 8'd5 && state == 4'd0) begin
            sys_int  <= 1'b0;             // simple ack
            data_out <= {4'b0000, ~sdc_irq_n, 1'b0, ~hid_irq_n, sys_int};
          end

          // ----------------------------------------------------------
          // CMD 6 – IRQ_SRC
          // ----------------------------------------------------------
          if (command == 8'd6 && state == 4'd0)
            data_out <= {7'd0, sys_int};

          // all other commands → return 0
        end
      end
    end
  end

endmodule
