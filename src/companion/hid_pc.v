/*
 * hid_pc.v
 *
 * FPGA Companion HID target specialised for Next186 (PC/DOS).
 *
 * Companion sends (SPI_TARGET_HID):
 *   CMD 1 (keyboard): one byte  {release, hid_code[6:0]}
 *                     (current firmware masks to 6 bits, we accept 7)
 *   CMD 2 (mouse)   : three bytes  buttons, dx, dy  (same as Atari version)
 *
 * We translate HID usage codes → PS/2 Set-2 make/break scancodes and
 * pulse inject_*_stb so that KB_Mouse_8042 pushes them into its
 * output buffer.  Physical PS/2 pins remain functional as fallback.
 */

module hid_pc (
  input            clk,
  input            reset,

  // from mcu_spi
  input            data_in_strobe,
  input            data_in_start,
  input      [7:0] data_in,
  output reg [7:0] data_out,

  // to KB_Mouse_8042
  output reg       inject_kb_stb,
  output reg [7:0] inject_kb_data,
  output reg       inject_mouse_stb,
  output reg [7:0] inject_mouse_data,

  // IRQ to Companion (active low)
  output reg       irq
);

  // ------------------------------------------------------------------
  // HID usage → Set-2 make code (partial table, covers typical PC keys)
  // Index = HID usage & 0x7F.  0x00 = unmapped / ignore.
  // Extended keys (E0 prefix) are marked by setting bit 8 of the table
  // entry; the state machine emits E0 then the low 8 bits.
  // ------------------------------------------------------------------
  function [8:0] hid2set2;
    input [6:0] hid;
    begin
      case (hid)
        // Letters
        7'h04: hid2set2 = 9'h01C; // A
        7'h05: hid2set2 = 9'h032; // B
        7'h06: hid2set2 = 9'h021; // C
        7'h07: hid2set2 = 9'h023; // D
        7'h08: hid2set2 = 9'h024; // E
        7'h09: hid2set2 = 9'h02B; // F
        7'h0A: hid2set2 = 9'h034; // G
        7'h0B: hid2set2 = 9'h033; // H
        7'h0C: hid2set2 = 9'h043; // I
        7'h0D: hid2set2 = 9'h03B; // J
        7'h0E: hid2set2 = 9'h042; // K
        7'h0F: hid2set2 = 9'h04B; // L
        7'h10: hid2set2 = 9'h03A; // M
        7'h11: hid2set2 = 9'h031; // N
        7'h12: hid2set2 = 9'h044; // O
        7'h13: hid2set2 = 9'h04D; // P
        7'h14: hid2set2 = 9'h015; // Q
        7'h15: hid2set2 = 9'h02D; // R
        7'h16: hid2set2 = 9'h01B; // S
        7'h17: hid2set2 = 9'h02C; // T
        7'h18: hid2set2 = 9'h03C; // U
        7'h19: hid2set2 = 9'h02A; // V
        7'h1A: hid2set2 = 9'h01D; // W
        7'h1B: hid2set2 = 9'h022; // X
        7'h1C: hid2set2 = 9'h035; // Y
        7'h1D: hid2set2 = 9'h01A; // Z

        // Numbers
        7'h1E: hid2set2 = 9'h016; // 1
        7'h1F: hid2set2 = 9'h01E; // 2
        7'h20: hid2set2 = 9'h026; // 3
        7'h21: hid2set2 = 9'h025; // 4
        7'h22: hid2set2 = 9'h02E; // 5
        7'h23: hid2set2 = 9'h036; // 6
        7'h24: hid2set2 = 9'h03D; // 7
        7'h25: hid2set2 = 9'h03E; // 8
        7'h26: hid2set2 = 9'h046; // 9
        7'h27: hid2set2 = 9'h045; // 0

        // Control keys
        7'h28: hid2set2 = 9'h05A; // Enter
        7'h29: hid2set2 = 9'h076; // Escape
        7'h2A: hid2set2 = 9'h066; // Backspace
        7'h2B: hid2set2 = 9'h00D; // Tab
        7'h2C: hid2set2 = 9'h029; // Space
        7'h2D: hid2set2 = 9'h04E; // - _
        7'h2E: hid2set2 = 9'h055; // = +
        7'h2F: hid2set2 = 9'h054; // [ {
        7'h30: hid2set2 = 9'h05B; // ] }
        7'h31: hid2set2 = 9'h05D; // \ |
        7'h33: hid2set2 = 9'h04C; // ; :
        7'h34: hid2set2 = 9'h052; // ' "
        7'h35: hid2set2 = 9'h00E; // ` ~
        7'h36: hid2set2 = 9'h041; // , <
        7'h37: hid2set2 = 9'h049; // . >
        7'h38: hid2set2 = 9'h04A; // / ?

        // Caps Lock + function keys
        7'h39: hid2set2 = 9'h058; // Caps Lock
        7'h3A: hid2set2 = 9'h005; // F1
        7'h3B: hid2set2 = 9'h006; // F2
        7'h3C: hid2set2 = 9'h004; // F3
        7'h3D: hid2set2 = 9'h00C; // F4
        7'h3E: hid2set2 = 9'h003; // F5
        7'h3F: hid2set2 = 9'h00B; // F6
        7'h40: hid2set2 = 9'h083; // F7
        7'h41: hid2set2 = 9'h00A; // F8
        7'h42: hid2set2 = 9'h001; // F9
        7'h43: hid2set2 = 9'h009; // F10
        7'h44: hid2set2 = 9'h078; // F11
        7'h45: hid2set2 = 9'h007; // F12

        // Print / Scroll / Pause (partial – Pause is special sequence)
        7'h46: hid2set2 = 9'h07C; // Print Screen
        7'h47: hid2set2 = 9'h07E; // Scroll Lock
        // 7'h48 Pause/Break is multi-byte, ignored for now

        // Navigation cluster (mapped directly to standard non-E0 scancodes for PC/XT compatibility)
        7'h49: hid2set2 = 9'h070; // Insert  (70)
        7'h4A: hid2set2 = 9'h06C; // Home    (6C)
        7'h4B: hid2set2 = 9'h07D; // Page Up (7D)
        7'h4C: hid2set2 = 9'h071; // Delete  (71)
        7'h4D: hid2set2 = 9'h069; // End     (69)
        7'h4E: hid2set2 = 9'h07A; // Page Dn (7A)
        7'h4F: hid2set2 = 9'h074; // Right   (74)
        7'h50: hid2set2 = 9'h06B; // Left    (6B)
        7'h51: hid2set2 = 9'h072; // Down    (72)
        7'h52: hid2set2 = 9'h075; // Up      (75)

        // Numpad
        7'h53: hid2set2 = 9'h077; // Num Lock
        7'h54: hid2set2 = 9'h04A; // KP /    (4A)
        7'h55: hid2set2 = 9'h07C; // KP *
        7'h56: hid2set2 = 9'h07B; // KP -
        7'h57: hid2set2 = 9'h079; // KP +
        7'h58: hid2set2 = 9'h05A; // KP Enter(5A)
        7'h59: hid2set2 = 9'h069; // KP 1
        7'h5A: hid2set2 = 9'h072; // KP 2
        7'h5B: hid2set2 = 9'h07A; // KP 3
        7'h5C: hid2set2 = 9'h06B; // KP 4
        7'h5D: hid2set2 = 9'h073; // KP 5
        7'h5E: hid2set2 = 9'h074; // KP 6
        7'h5F: hid2set2 = 9'h06C; // KP 7
        7'h60: hid2set2 = 9'h075; // KP 8
        7'h61: hid2set2 = 9'h07D; // KP 9
        7'h62: hid2set2 = 9'h070; // KP 0
        7'h63: hid2set2 = 9'h071; // KP .

        // Application / menu key
        7'h65: hid2set2 = 9'h02F; // App     (2F)

        // Modifiers – Companion sends 0x68+i for the 8 modifier bits
        7'h68: hid2set2 = 9'h014; // L-Ctrl  (Set 2: 14h)
        7'h69: hid2set2 = 9'h012; // L-Shift (Set 2: 12h)
        7'h6A: hid2set2 = 9'h011; // L-Alt   (Set 2: 11h)
        7'h6B: hid2set2 = 9'h01F; // L-GUI   (1F)
        7'h6C: hid2set2 = 9'h014; // R-Ctrl  (14h)
        7'h6D: hid2set2 = 9'h059; // R-Shift
        7'h6E: hid2set2 = 9'h011; // R-Alt   (11h)
        7'h6F: hid2set2 = 9'h027; // R-GUI   (27)

        default: hid2set2 = 9'h000;
      endcase
    end
  endfunction

  // ------------------------------------------------------------------
  // Combinatorial map (avoids "select on function call" Gowin warning)
  // ------------------------------------------------------------------
  wire [8:0] mapped_comb = hid2set2(data_in[6:0]);
  wire signed [8:0] mouse_dy_wire = - $signed({data_in[7], data_in});

  // ------------------------------------------------------------------
  // State machine
  // ------------------------------------------------------------------
  reg [3:0]  state;
  reg [7:0]  command;
  reg        release_flag;
  reg [1:0]  emit_phase;       // 0=idle, 1=E0, 2=make-or-F0, 3=code-after-F0
  reg [7:0]  pending_code;
  reg [8:0]  mapped_r;         // registered result of hid2set2

  // Typematic repeat (hardware repeat for USB keyboard)
  // 500ms delay @ 21.6MHz = 10,800,000 cycles
  // 66.7ms repeat (~15 Hz) = 1,440,000 cycles
  reg [23:0] repeat_timer;
  reg        repeat_active;
  reg [6:0]  repeat_hid_key;
  reg [8:0]  repeat_code;

  // Mouse: build standard 3-byte PS/2 relative packet
  // byte0 = Yovfl | Xovfl | Ysign | Xsign | 1 | Mbtn | Rbtn | Lbtn
  // byte1 = X movement (9-bit 2's complement, low 8)
  // byte2 = Y movement (note: PS/2 Y is opposite to USB HID)
  reg [2:0]  mouse_btns;
  reg signed [8:0] mouse_dx, mouse_dy;
  reg [1:0]  mouse_emit;       // 0=idle, 1=byte0, 2=byte1, 3=byte2
  reg [7:0]  mouse_b0, mouse_b1, mouse_b2;

  always @(posedge clk) begin
    if (reset) begin
      state            <= 4'd0;
      inject_kb_stb    <= 1'b0;
      inject_mouse_stb <= 1'b0;
      data_out         <= 8'h00;
      irq              <= 1'b1;          // inactive (active-low)
      emit_phase       <= 2'd0;
      mouse_emit       <= 2'd0;
      mouse_dx         <= 9'sd0;
      mouse_dy         <= 9'sd0;
      mouse_btns       <= 3'd0;
      repeat_active    <= 1'b0;
      repeat_timer     <= 24'd0;
      repeat_hid_key   <= 7'd0;
      repeat_code      <= 9'd0;
    end else begin
      // default single-cycle strobes
      inject_kb_stb    <= 1'b0;
      inject_mouse_stb <= 1'b0;

      // ---------- keyboard scancode emitter (highest priority) ----------
      if (emit_phase != 2'd0) begin
        case (emit_phase)
          2'd1: begin                        // E0 prefix
            inject_kb_data <= 8'hE0;
            inject_kb_stb  <= 1'b1;
            emit_phase     <= 2'd2;
          end
          2'd2: begin                        // make code or F0
            if (release_flag) begin
              inject_kb_data <= 8'hF0;
              inject_kb_stb  <= 1'b1;
              emit_phase     <= 2'd3;
            end else begin
              inject_kb_data <= pending_code;
              inject_kb_stb  <= 1'b1;
              emit_phase     <= 2'd0;
            end
          end
          2'd3: begin                        // code after F0
            inject_kb_data <= pending_code;
            inject_kb_stb  <= 1'b1;
            emit_phase     <= 2'd0;
          end
          default: emit_phase <= 2'd0;
        endcase
      end
      // ---------- mouse packet emitter ----------
      else if (mouse_emit != 2'd0) begin
        case (mouse_emit)
          2'd1: begin
            inject_mouse_data <= mouse_b0;
            inject_mouse_stb  <= 1'b1;
            mouse_emit        <= 2'd2;
          end
          2'd2: begin
            inject_mouse_data <= mouse_b1;
            inject_mouse_stb  <= 1'b1;
            mouse_emit        <= 2'd3;
          end
          2'd3: begin
            inject_mouse_data <= mouse_b2;
            inject_mouse_stb  <= 1'b1;
            mouse_emit        <= 2'd0;
          end
          default: mouse_emit <= 2'd0;
        endcase
      end
      // ---------- typematic repeat emitter ----------
      else if (repeat_active && !data_in_strobe) begin
        if (repeat_timer == 24'd1) begin
          repeat_timer <= 24'd1_440_000; // ~15 Hz repeat interval
          release_flag <= 1'b0;
          pending_code <= repeat_code[7:0];
          if (repeat_code[8]) begin
            inject_kb_data <= 8'hE0;
            inject_kb_stb  <= 1'b1;
            emit_phase     <= 2'd2;
          end else begin
            inject_kb_data <= repeat_code[7:0];
            inject_kb_stb  <= 1'b1;
          end
        end else begin
          repeat_timer <= repeat_timer - 24'd1;
        end
      end
      // ---------- parse SPI bytes from Companion ----------
      else if (data_in_strobe) begin
        if (data_in_start) begin
          state   <= 4'd0;
          command <= data_in;
        end else begin
          state <= state + 4'd1;

          // CMD 0 – status / version
          if (command == 8'd0) begin
            if (state == 4'd0) data_out <= 8'h01;
            if (state == 4'd1) data_out <= 8'h00;
          end

          // CMD 1 – keyboard (one data byte after the command)
          if (command == 8'd1 && state == 4'd0) begin
            release_flag <= data_in[7];
            mapped_r     <= mapped_comb;
            pending_code <= mapped_comb[7:0];
            if (mapped_comb != 9'h000) begin
              if (mapped_comb[8])
                emit_phase <= 2'd1;          // E0 prefix needed
              else
                emit_phase <= 2'd2;          // direct make/break
            end

            // Hardware typematic repeat tracking
            if (data_in[7]) begin
              // Key release: cancel repeat if released key was repeating
              if (data_in[6:0] == repeat_hid_key) begin
                repeat_active <= 1'b0;
              end
            end else begin
              // Key press: start repeat timer for non-modifier keys (< 0x68)
              if (data_in[6:0] < 7'h68 && mapped_comb != 9'h000) begin
                repeat_active  <= 1'b1;
                repeat_hid_key <= data_in[6:0];
                repeat_code    <= mapped_comb;
                repeat_timer   <= 24'd10_800_000; // 500 ms initial delay
              end
            end
          end

          // CMD 2 – mouse (buttons, dx, dy)
          // Companion sends the same 3-byte format as the Atari HID path:
          //   byte0 = buttons[2:0], byte1 = dx, byte2 = dy (USB HID sense)
          if (command == 8'd2) begin
            if (state == 4'd0) mouse_btns <= data_in[2:0];
            if (state == 4'd1) mouse_dx   <= $signed({data_in[7], data_in});
            if (state == 4'd2) begin
              // PS/2 Y is opposite to USB HID → negate
              // All RHS values are stable (mouse_dx/btns from prior cycles,
              // mouse_dy_wire is current) so the packet is consistent.
              mouse_b0 <= {
                1'b0,                       // Y overflow
                1'b0,                       // X overflow
                mouse_dy_wire[8],           // Y sign (correct 9-bit sign)
                mouse_dx[8],                // X sign
                1'b1,                       // always 1
                mouse_btns[2],              // middle button
                mouse_btns[1],              // right
                mouse_btns[0]               // left
              };
              mouse_b1 <= mouse_dx[7:0];
              mouse_b2 <= mouse_dy_wire[7:0]; // negated Y, low 8 bits
              mouse_emit <= 2'd1;
            end
          end
        end
      end
    end
  end

endmodule
