// ===========================================================================
// ems_map.v — Hardware LIM EMS 4.0/3.2 Banking Controller for Next186 SoC
//
// Provides four independent 16-KB page windows in the 64-KB Page Frame
// (default at segment 0xE000, optionally 0xD000) mapping to any of the 448
// 16-KB pages (7MB) in the 8MB SDRAM.
//
// Ports:
//   0x0260 (R/W): Slot 0 physical page register (16KB page 0..511)
//   0x0262 (R/W): Slot 1 physical page register (16KB page 0..511)
//   0x0264 (R/W): Slot 2 physical page register (16KB page 0..511)
//   0x0266 (R/W): Slot 3 physical page register (16KB page 0..511)
//   0x0268 (R/W): Status/Control:
//                 Write bit 0: enable EMS (1=active, 0=pass-through)
//                 Write bit 1: frame base (0=0xE000, 1=0xD000)
//                 Read: 16'h454D (EM ASCII signature)
//   0x026A (RO) : Total EMS 16-KB pages available (448 = 7MB)
//   0x026C (RO) : Base physical 16-KB page index of EMS pool (64 = 1MB)
// ===========================================================================

module ems_map(
    input  wire        CLK,
    input  wire        RST,

    // CPU I/O Bus
    input  wire [15:0] PORT_ADDR,
    input  wire [15:0] CPU_DOUT,
    input  wire        IORQ,
    input  wire        WR,
    input  wire        WORD,
    input  wire        CPU_CE,
    output wire [15:0] PORT_DOUT,
    output wire        PORT_OE,
    output reg         ems_flush,

    // Memory Address Translation
    input  wire [20:0] ADDR,
    input  wire [6:0]  memmap_mux,
    output wire [20:0] cpu_phys_dword,
    output wire        is_ems
);

    // 4 physical page registers (9 bits each -> 0..511 = 8MB at 16KB per page)
    reg [8:0] ems_page [0:3];
    reg       ems_enable;
    reg       ems_base_d000;

    // I/O decode: ports 0x0260 - 0x026F
    wire ems_io_sel = (PORT_ADDR[15:4] == 12'h026);
    assign PORT_OE  = ems_io_sel;

    wire ems_we = ems_io_sel && IORQ && CPU_CE && WR;

    // Port Read Mux
    reg [15:0] port_dout_r;
    always @(*) begin
        case (PORT_ADDR[3:1])
            3'b000: port_dout_r = {7'b0, ems_page[0]};
            3'b001: port_dout_r = {7'b0, ems_page[1]};
            3'b010: port_dout_r = {7'b0, ems_page[2]};
            3'b011: port_dout_r = {7'b0, ems_page[3]};
            3'b100: port_dout_r = 16'h454D; // EM signature for auto-detection
            3'b101: port_dout_r = 16'd448;  // Total 16KB pages = 448 (7168 KB)
            3'b110: port_dout_r = 16'd64;   // Base physical page = 64 (1MB mark)
            default: port_dout_r = 16'h0000;
        endcase
    end
    assign PORT_DOUT = port_dout_r;

    // Port Write Logic
    always @(posedge CLK) begin
        if (RST) begin
            ems_enable    <= 1'b0;
            ems_base_d000 <= 1'b0;
            ems_page[0]   <= 9'd64; // Default to first 4 pages of EMS pool
            ems_page[1]   <= 9'd65;
            ems_page[2]   <= 9'd66;
            ems_page[3]   <= 9'd67;
            ems_flush     <= 1'b0;
        end else begin
            ems_flush <= 1'b0;
            if (ems_we) begin
                ems_flush <= 1'b1; // Invalidate cache lines on any map register change
                case (PORT_ADDR[3:1])
                    3'b000, 3'b001, 3'b010, 3'b011: begin
                        if (WORD) begin
                            ems_page[PORT_ADDR[2:1]] <= CPU_DOUT[8:0];
                        end else begin
                            if (~PORT_ADDR[0])
                                ems_page[PORT_ADDR[2:1]][7:0] <= CPU_DOUT[7:0];
                            else
                                ems_page[PORT_ADDR[2:1]][8]   <= CPU_DOUT[0];
                        end
                    end
                    3'b100: begin // Port 0x0268
                        if (WORD || ~PORT_ADDR[0]) begin
                            ems_enable    <= CPU_DOUT[0];
                            ems_base_d000 <= CPU_DOUT[1];
                        end
                    end
                    default: ;
                endcase
            end
        end
    end

    // Address Translation
    wire [3:0] ems_seg = ems_base_d000 ? 4'hD : 4'hE;
    assign is_ems = ems_enable && (ADDR[20:16] == {1'b0, ems_seg});

    wire [1:0]  slot             = ADDR[15:14];
    wire [8:0]  cur_page         = ems_page[slot];
    wire [20:0] ems_phys_dword   = {cur_page, ADDR[13:2]};
    wire [20:0] legacy_phys_dword= {memmap_mux[6:0], ADDR[15:2]};

    assign cpu_phys_dword = is_ems ? ems_phys_dword : legacy_phys_dword;

endmodule
