/*
    mcu_spi.v — SPI slave for FPGA Companion
    MODE1, Gowin-safe (no decls inside always)

    Byte stream while CSN low:
      byte0  = TARGET  (0=SYS 1=HID 2=OSD 3=SDC)  — not forwarded
      byte1  = COMMAND — forwarded with mcu_start=1
      byte2+ = PAYLOAD — forwarded with mcu_start=0

    mcu_start = (spi_in_cnt == 1)  while the command byte is being delivered.
    (Upstream used ==2 which is off-by-one vs SPI.md and breaks HID/SYS parsing.)
*/

module mcu_spi (
  input        clk,
  input        reset,

  input        spi_io_ss,
  input        spi_io_clk,
  input        spi_io_din,
  output reg   spi_io_dout,

  output reg       mcu_sys_strobe,
  output reg       mcu_hid_strobe,
  output reg       mcu_osd_strobe,
  output reg       mcu_sdc_strobe,
  output reg       mcu_start,
  input      [7:0] mcu_sys_din,
  input      [7:0] mcu_hid_din,
  input      [7:0] mcu_osd_din,
  input      [7:0] mcu_sdc_din,
  output     [7:0] mcu_dout,

  // diagnostic: pulses high for ~1ms after any SPI transaction
  output reg       spi_activity
);

  reg [3:0] spi_cnt;
  reg [7:0] spi_data_in;
  reg [6:0] spi_sr_in;
  reg       spi_data_in_ready;
  reg [7:0] spi_in_data;
  reg [7:0] spi_target;
  reg [3:0] spi_in_cnt;
  reg [1:0] spi_data_in_readyD;
  reg [15:0] activity_cnt;

  assign mcu_dout  = spi_in_data;

  // SPI bit capture (MODE1: sample on falling edge)
  always @(negedge spi_io_clk or posedge spi_io_ss) begin
    if (spi_io_ss) begin
      spi_cnt <= 4'd0;
    end else begin
      spi_cnt   <= spi_cnt + 4'd1;
      spi_sr_in <= { spi_sr_in[5:0], spi_io_din };
      if (spi_cnt[2:0] == 3'd7) begin
        spi_data_in       <= { spi_sr_in, spi_io_din };
        spi_data_in_ready <= ~spi_data_in_ready;
      end
    end
  end

  always @(posedge clk) begin
    if (reset) begin
      spi_data_in_readyD <= 2'b00;
      spi_in_cnt         <= 4'd0;
      spi_target         <= 8'd0;
      mcu_sys_strobe     <= 1'b0;
      mcu_hid_strobe     <= 1'b0;
      mcu_osd_strobe     <= 1'b0;
      mcu_sdc_strobe     <= 1'b0;
      mcu_start          <= 1'b0;
      spi_activity       <= 1'b0;
      activity_cnt       <= 16'd0;
    end else begin
      spi_data_in_readyD <= { spi_data_in_readyD[0], spi_data_in_ready };

      mcu_sys_strobe <= 1'b0;
      mcu_hid_strobe <= 1'b0;
      mcu_osd_strobe <= 1'b0;
      mcu_sdc_strobe <= 1'b0;
      mcu_start      <= 1'b0;

      // activity LED stretch
      if (activity_cnt != 16'd0) begin
        activity_cnt <= activity_cnt - 16'd1;
        spi_activity <= 1'b1;
      end else begin
        spi_activity <= 1'b0;
      end

      if (spi_io_ss) begin
        spi_in_cnt <= 4'd0;
      end else if (spi_data_in_readyD[1] ^ spi_data_in_readyD[0]) begin
        // new complete SPI byte in clk domain
        activity_cnt <= 16'd20000;   // ~1ms @ 18–20 MHz

        if (spi_in_cnt == 4'd0) begin
          // TARGET byte — remember, do not strobe targets
          spi_target <= spi_data_in;
        end else begin
          // COMMAND (cnt==1, mcu_start=1) or PAYLOAD (cnt>=2, mcu_start=0)
          if (spi_target == 8'd0) mcu_sys_strobe <= 1'b1;
          if (spi_target == 8'd1) mcu_hid_strobe <= 1'b1;
          if (spi_target == 8'd2) mcu_osd_strobe <= 1'b1;
          if (spi_target == 8'd3) mcu_sdc_strobe <= 1'b1;
          spi_in_data <= spi_data_in;
          mcu_start   <= (spi_in_cnt == 4'd1);
        end
        if (spi_in_cnt != 4'd15)
          spi_in_cnt <= spi_in_cnt + 4'd1;
      end
    end
  end

  wire [7:0] in_byte =
      (spi_target == 8'd0) ? mcu_sys_din :
      (spi_target == 8'd1) ? mcu_hid_din :
      (spi_target == 8'd2) ? mcu_osd_din :
      (spi_target == 8'd3) ? mcu_sdc_din :
      8'h00;

  always @(posedge spi_io_clk or posedge spi_io_ss) begin
    if (spi_io_ss)
      spi_io_dout <= 1'b0;
    else
      spi_io_dout <= in_byte[~spi_cnt[2:0]];
  end

endmodule
