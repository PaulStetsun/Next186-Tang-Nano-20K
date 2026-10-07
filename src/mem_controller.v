`default_nettype none
// mem_controller.v — Tang Nano 20K variant (rev.2 — single-owner SDRAM arbiter)
//
// Drop-in replacement for the 9K version. External module port list and
// external protocol contract (sys_CMD / sdraddr / sys_cmd_ack / sys_DOUT /
// sys_rd_data_valid, and the CPU-side addr/din/dout/wmask/ce) are kept
// IDENTICAL to the original 9K mem_controller.v, so system.v does NOT need
// to change.
//
// Internally, PSRAM_Memory_Interface_HS_Top_B32 (9K hard IP) is replaced by
// sdram32 (see sdram32.v) wrapping the Tang Nano 20K's embedded SDR SDRAM.
// Boot ROM / boot RAM / BIOS ROM sections are UNCHANGED from the 9K source.
//
// Design note: ALL requests to sdram32 (CPU read/write, VGA prefetch read,
// refresh) are issued from a single arbiter always-block below, so sdr_rd/
// sdr_wr/sdr_refresh/sdr_addr/sdr_din/sdr_dqm each have exactly one driver.
// CPU and VGA logic only set request flags and read back result flags.
//
// STATUS: structurally complete, NOT simulated, NOT yet verified on
// hardware. Known open item before trusting this: the vga_req / cpu_req
// handshake is a single-cycle pulse into the arbiter — if the arbiter is
// busy the exact cycle a request pulses, that request can be missed. Low
// probability given relative timescales, but this needs a testbench
// (iverilog/Gowin simulator) pass before synthesis, not just a read-through.
// Also needs real-hardware bring-up for: refresh cadence, VGA prefetch
// throughput margin at the actual clk_mctr frequency, and timing closure.

module mem_controller(
     input  wire [20:0] addr,
     input  wire [8:0]  memmap_mux,
     input  wire [20:0] cpu_phys_dword_in,
     input  wire        is_ems,
     input  wire        ems_flush,
     output wire [31:0] dout,
     input  wire [31:0] din,
     input  wire clk,
     input  wire mreq,
     input  wire [3:0]  wmask,
     output wire ce,
     input  wire cpu_ce,

    // SDRAM ("magic" ports — wire straight through Next186_SoC_20K.v)
    input  wire         reset,
    input  wire         sdram_clk,     // system clock -> sdram32.clk (was psram_clk)
    input  wire         sdram_clk_p,   // phase-shifted clock -> sdram32.clk_sdram (NEW; PLL clkoutp)
    input  wire         pll_lock,
    output wire         ps_calib,      // "memory ready", replaces PSRAM init_calib

    inout  wire [31:0]  IO_sdram_dq,
    output wire [10:0]  O_sdram_addr,
    output wire [1:0]   O_sdram_ba,
    output wire         O_sdram_cs_n,
    output wire         O_sdram_wen_n,
    output wire         O_sdram_ras_n,
    output wire         O_sdram_cas_n,
    output wire         O_sdram_clk,
    output wire         O_sdram_cke,
    output wire [3:0]   O_sdram_dqm,

    // VGA Data Read
    output wire        clk_mctr,
    input  wire        vblnk,
    input  wire [1:0]  sys_CMD,
    input  wire [23:0] sdraddr,
    output reg  [1:0]  sys_cmd_ack,
    output wire [15:0] sys_DOUT,
    output reg         sys_rd_data_valid,
    input wire flush,
    output wire dbg_boot_cs, output wire dbg_bios_cs, output wire [31:0] dbg_rom_dout,
    output wire [7:0] dbg_sdram_state
    );

// ===========================================================================
// Boot ROM / Boot RAM / BIOS ROM — UNCHANGED from 9K source
// ===========================================================================
reg  boot_rom_csd, bios_rom_csd, boot_ram_csd;
reg  move_rom, bios_rom_kill;
reg  xram_csd;
reg [7:0] xram_ad;

reg        cpu_just_done;

always @(posedge clk) begin
    if(reset) begin move_rom <= 0; bios_rom_kill <= 0; end
    else begin
        boot_rom_csd <= boot_rom_cs; bios_rom_csd <= bios_rom_cs;
        boot_ram_csd <= boot_ram_cs; xram_csd <= xram_cs;
        xram_ad <= addr[7:0];
        if(mreq && addr[19:12]==8'hfc && ~WRE) move_rom <= 1;
        if(mreq && addr[19: 0]==20'hffffe && WRE) bios_rom_kill <= 1;
    end
end

wire xram_cs     = mreq && addr[19:8]=={12'hfca}  ? 1'b1 : 1'b0;
wire WRE         = wmask!=4'b0000;
wire boot_ram_cs = mreq && addr[19:10]=={8'hfc,2'b10} ? 1'b1 : 1'b0;
wire boot_rom_cs = mreq && ((addr[19:12]==8'hff && ~move_rom) || addr[19:12]==8'hfc) && ~boot_ram_cs   ? 1'b1 : 1'b0;
wire bios_rom_cs = mreq && ~WRE && (addr[19:16]==4'hf && addr[15:13]==3'b111) && ~bios_rom_kill ? 1'b1 : 1'b0;
wire dram_cs     = ~reset && mreq && ~boot_rom_cs && ~bios_rom_cs && ~boot_ram_cs ? 1'b1 : 1'b0;
assign dbg_boot_cs = boot_rom_csd;
assign dbg_bios_cs = bios_rom_csd;
assign dbg_rom_dout = boot_rom_csd ? boot_rom_dout : (bios_rom_csd ? bios_rom_dout : boot_ram_dout);

// Combinational read data mux (avoiding invalid self-referential wire assignment
// `assign dout = ~ce ? dout : ...` which synthesizes to a stuck latch in Gowin EDA).
assign dout =   boot_rom_csd ? boot_rom_dout :
                boot_ram_csd ? boot_ram_dout :
                bios_rom_csd ? bios_rom_dout :
                dram_dout;

wire [31:0] boot_rom_dout;
Gowin_pROM_boot bootrom(
    .clk(clk), .ad(addr[11:2]), .dout(boot_rom_dout), .oce(1'b1), .ce(1'b1), .reset(1'b0) );

wire [31:0] bios_rom_dout;
Gowin_pROM_bios bios(
    .clk(clk), .ad(addr[12:2]), .dout(bios_rom_dout), .oce(1'b1), .ce(1'b1), .reset(1'b0) );

wire [7:0]  boot_ram_addr = addr[9:2];
wire [31:0] boot_ram_dout;
Gowin_SP_256x8 bootram0(.clk(clk), .ad(boot_ram_addr), .oce(1'b1), .ce(1'b1), .reset(1'b0),
    .din(din[7:0]),   .dout(boot_ram_dout[7:0]),   .wre(wmask[0] && boot_ram_cs && WRE) );
Gowin_SP_256x8 bootram1(.clk(clk), .ad(boot_ram_addr), .oce(1'b1), .ce(1'b1), .reset(1'b0),
    .din(din[15:8]),  .dout(boot_ram_dout[15:8]),  .wre(wmask[1] && boot_ram_cs && WRE) );
Gowin_SP_256x8 bootram2(.clk(clk), .ad(boot_ram_addr), .oce(1'b1), .ce(1'b1), .reset(1'b0),
    .din(din[23:16]), .dout(boot_ram_dout[23:16]), .wre(wmask[2] && boot_ram_cs && WRE) );
Gowin_SP_256x8 bootram3(.clk(clk), .ad(boot_ram_addr), .oce(1'b1), .ce(1'b1), .reset(1'b0),
    .din(din[31:24]), .dout(boot_ram_dout[31:24]), .wre(wmask[3] && boot_ram_cs && WRE) );

// ===========================================================================
// SDRAM core + single arbiter
// ===========================================================================
assign clk_mctr = sdram_clk;

wire        sdr_busy, sdr_data_ready;
reg         sdr_rd, sdr_wr, sdr_refresh;
reg  [22:0] sdr_addr;
reg  [31:0] sdr_din;
reg  [3:0]  sdr_dqm;
wire [31:0] sdr_dout;
wire        sdr_resetn = pll_lock & ~reset;

sdram32 u_sdram(
    .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba),
    .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n), .SDRAM_nRAS(O_sdram_ras_n),
    .SDRAM_nCAS(O_sdram_cas_n), .SDRAM_CLK(O_sdram_clk), .SDRAM_CKE(O_sdram_cke),
    .SDRAM_DQM(O_sdram_dqm),
    .clk(sdram_clk), .clk_sdram(sdram_clk_p), .resetn(sdr_resetn),
    .rd(sdr_rd), .wr(sdr_wr), .refresh(sdr_refresh),
    .addr(sdr_addr), .din(sdr_din), .dqm_in(sdr_dqm),
    .dout(sdr_dout), .data_ready(sdr_data_ready), .busy(sdr_busy)
);

assign ps_calib = init_done;

// Refresh timer: request every ~15us. ~972 cyc @64.8MHz; 900 gives margin.
localparam REFRESH_INTERVAL = 900;
reg [10:0] refresh_cnt;
reg        refresh_req;
always @(posedge sdram_clk) begin
    if (reset) begin
        refresh_cnt <= 0;
        refresh_req <= 0;
    end else begin
        if (refresh_cnt == REFRESH_INTERVAL) begin
            refresh_cnt <= 0;
            refresh_req <= 1;
        end else begin
            refresh_cnt <= refresh_cnt + 1'b1;
        end
        if (sdr_refresh) refresh_req <= 0;
    end
end

// -------------------------------------------------------------------------
// CPU <-> SDRAM clock-domain crossing
// -------------------------------------------------------------------------
// The old implementation sampled dram_cs/addr/din/wmask directly from the
// 16.2MHz CPU domain with the 64.8MHz SDRAM clock.  That created exactly the
// kind of unconstrained CPU-cone -> SDRAM timing paths shown by Gowin STA
// (roughly -20..-25ns setup slack in the previous report).
//
// This version uses a level-independent toggle handshake:
//   CPU domain: latch the complete transaction, toggle cpu_req_toggle, stall
//               the CPU (CE=0) until the SDRAM side acknowledges completion.
//   SDRAM domain: synchronize the request toggle, then copy the already
//                 stable multi-bit payload into local registers before
//                 issuing the SDRAM command.
//   Completion/data return: SDRAM holds read data stable and toggles
//                 cpu_ack_toggle; CPU synchronizes that toggle, captures the
//                 held data, and releases CE.
//
// The payload is therefore never taken from a changing ALU/decoder cone at
// the SDRAM command edge.
// -------------------------------------------------------------------------
reg        cpu_req_toggle;
reg        cpu_busy_cpu;
reg [22:0] cpu_sdr_addr_hold;
reg [31:0] cpu_din_hold;
reg [3:0]  cpu_wmask_hold;
reg        rom_pending_cpu;

reg        cpu_ack_toggle_sdr;
reg [31:0] cpu_rdata_hold_sdr;
reg        cpu_ack_sync1;
reg        cpu_ack_sync2;
reg        cpu_ack_seen;
reg        cpu_read_ack_pending_sdr;
reg [31:0] dram_dout_r;

// ROOT CAUSE FOUND (this session): `ce` was being stalled (cpu_busy_cpu<=1)
// for boot_rom_cs/bios_rom_cs/boot_ram_cs reads. That is NOT what the
// reference 9K mem_controller.v does -- there, `ce` is defined purely as
// `~((psram_cs && ~sddtac) || xram_dis)` and is NEVER pulled low for
// boot/BIOS ROM or boot-RAM reads; those are plain single-cycle-latency
// BRAM reads and the BIU (Next186_BIU_2T_delayread.v) already has its own
// hard-coded "+1T for each memory read" pipeline (the rdi/cedly path) that
// assumes CE stays high across them. Stalling CE for exactly one cycle on
// every boot/BIOS ROM fetch -- which is the overwhelming majority of all
// fetches immediately after reset/POST -- desynchronizes that queue-fill
// pipeline against the extra wait state, corrupting the instruction stream
// almost immediately after boot. This is what produced the garbage text
// ("m8nh6...", then a screen full of repeated garbage/dots): the CPU never
// stalls on real DRAM at that point in boot, it is fed a corrupted
// instruction queue by the ROM path alone.
//
// Fix: only stall CE for the real SDRAM (dram_cs) path, exactly like 9K.
// Boot/BIOS ROM and boot-RAM reads go back to being *not* CE-gated; the
// dout mux (boot_rom_csd/bios_rom_csd/boot_ram_csd, already registered one
// cycle behind cs) supplies the extra cycle exactly as it did on 9K.
// ROOT CAUSE FIX (this session): CE must fall **combinationally** — in the
// exact same clock cycle that dram_cs rises — NOT one registered cycle later.
//
// Why: Next186_BIU_2T_delayread.v captures SDRAM read-data into the
// instruction queue OUTSIDE the `if(CE)` block, via:
//     cedly <= CE;
//     if (rdi && cedly) queue[rpos] <= RAM_DIN;
// This relies on cedly seeing CE=0 on the very first cycle after BIU asserts
// iread (which raises mreq/dram_cs).  On 9K, CE was combinational:
//     assign ce = ~((psram_cs && ~sddtac) || xram_dis);
// so CE fell to 0 in the SAME cycle psram_cs went high, and cedly correctly
// saw 0 on the next posedge — preventing stale RAM_DIN from being latched.
//
// The previous 20K implementation used `assign ce = ~cpu_busy_cpu;` which is
// REGISTERED (cpu_busy_cpu updates via NBA on posedge clk).  CE therefore
// stayed 1 for one extra cycle after dram_cs rose, making cedly=1 on the
// next posedge, and the BIU captured whatever stale/zero value was on
// dram_dout_r from the PREVIOUS transaction — corrupting the instruction
// stream immediately.  This is why instruction fetch from SDRAM never worked
// (data read/write via mon86 was fine because it uses the RAM_RD/RAM_WR path,
// not the rdi/cedly queue-capture path).
//
// Fix: add a combinational term so CE falls immediately when a new SDRAM
// request is about to be taken.  cpu_just_done excludes the "free" cycle
// where the BIU must see CE=1 to consume the returned data.
// 16-entry Write Buffer (FIFO between CPU clk and SDRAM sdram_clk)
reg [20:0] wbuf_addr  [0:15];
reg [31:0] wbuf_din   [0:15];
reg [3:0]  wbuf_wmask [0:15];

reg [4:0]  wbuf_wr_ptr = 5'd0;
reg [4:0]  wbuf_rd_ptr = 5'd0;

// Gray code pointers for cross-domain synchronization
wire [4:0] wbuf_wr_ptr_gray = wbuf_wr_ptr ^ (wbuf_wr_ptr >> 1);
wire [4:0] wbuf_rd_ptr_gray = wbuf_rd_ptr ^ (wbuf_rd_ptr >> 1);

// Synchronize wr_ptr_gray into sdram_clk domain
reg [4:0] wbuf_wr_ptr_sync1 = 5'd0;
reg [4:0] wbuf_wr_ptr_sync2 = 5'd0;
always @(posedge sdram_clk) begin
    if (reset) begin
        wbuf_wr_ptr_sync1 <= 5'd0;
        wbuf_wr_ptr_sync2 <= 5'd0;
    end else begin
        wbuf_wr_ptr_sync1 <= wbuf_wr_ptr_gray;
        wbuf_wr_ptr_sync2 <= wbuf_wr_ptr_sync1;
    end
end

// Gray to binary for wr_ptr in SDRAM domain
wire [4:0] wbuf_wr_ptr_sdr;
assign wbuf_wr_ptr_sdr[4] = wbuf_wr_ptr_sync2[4];
assign wbuf_wr_ptr_sdr[3] = wbuf_wr_ptr_sync2[4] ^ wbuf_wr_ptr_sync2[3];
assign wbuf_wr_ptr_sdr[2] = wbuf_wr_ptr_sync2[4] ^ wbuf_wr_ptr_sync2[3] ^ wbuf_wr_ptr_sync2[2];
assign wbuf_wr_ptr_sdr[1] = wbuf_wr_ptr_sync2[4] ^ wbuf_wr_ptr_sync2[3] ^ wbuf_wr_ptr_sync2[2] ^ wbuf_wr_ptr_sync2[1];
assign wbuf_wr_ptr_sdr[0] = wbuf_wr_ptr_sync2[4] ^ wbuf_wr_ptr_sync2[3] ^ wbuf_wr_ptr_sync2[2] ^ wbuf_wr_ptr_sync2[1] ^ wbuf_wr_ptr_sync2[0];

wire wbuf_avail = (wbuf_wr_ptr_sdr != wbuf_rd_ptr);

// Synchronize rd_ptr_gray into CPU clk domain
reg [4:0] wbuf_rd_ptr_sync1 = 5'd0;
reg [4:0] wbuf_rd_ptr_sync2 = 5'd0;
always @(posedge clk) begin
    if (reset) begin
        wbuf_rd_ptr_sync1 <= 5'd0;
        wbuf_rd_ptr_sync2 <= 5'd0;
    end else begin
        wbuf_rd_ptr_sync1 <= wbuf_rd_ptr_gray;
        wbuf_rd_ptr_sync2 <= wbuf_rd_ptr_sync1;
    end
end

// Gray to binary for rd_ptr in CPU domain
wire [4:0] wbuf_rd_ptr_cpu;
assign wbuf_rd_ptr_cpu[4] = wbuf_rd_ptr_sync2[4];
assign wbuf_rd_ptr_cpu[3] = wbuf_rd_ptr_sync2[4] ^ wbuf_rd_ptr_sync2[3];
assign wbuf_rd_ptr_cpu[2] = wbuf_rd_ptr_sync2[4] ^ wbuf_rd_ptr_sync2[3] ^ wbuf_rd_ptr_sync2[2];
assign wbuf_rd_ptr_cpu[1] = wbuf_rd_ptr_sync2[4] ^ wbuf_rd_ptr_sync2[3] ^ wbuf_rd_ptr_sync2[2] ^ wbuf_rd_ptr_sync2[1];
assign wbuf_rd_ptr_cpu[0] = wbuf_rd_ptr_sync2[4] ^ wbuf_rd_ptr_sync2[3] ^ wbuf_rd_ptr_sync2[2] ^ wbuf_rd_ptr_sync2[1] ^ wbuf_rd_ptr_sync2[0];

wire [4:0] wbuf_count = wbuf_wr_ptr - wbuf_rd_ptr_cpu;
wire wbuf_full  = (wbuf_count >= 5'd14);
wire wbuf_empty = (wbuf_count == 5'd0);

wire dram_wr = dram_cs & WRE;
wire dram_rd = dram_cs & ~WRE;
wire new_dram_req = ~cpu_busy_cpu & ~cpu_just_done & (dram_rd | (dram_wr & wbuf_full));
assign ce = reset ? 1'b1 : ~(cpu_busy_cpu | new_dram_req);
wire [31:0] dram_dout = dram_dout_r;

// 1024-entry register/distributed L1 cache (4096 bytes / 1024 dwords)
reg [31:0]   c_data [0:1023];
reg [10:0]   c_tag  [0:1023];
reg [1023:0] c_valid = 1024'd0;
reg          c_hit_pending = 1'b0;
reg          read_waiting_wbuf = 1'b0;

// 8MB physical SDRAM dword address (provided by ems_map with legacy fallback):
wire [20:0] cpu_phys_dword = cpu_phys_dword_in;

// Cache indexing: 1024 entries -> 10-bit index (addr[11:2])
wire [9:0]  c_idx = addr[11:2];
// Cache tag: upper 11 bits of physical dword address
wire [10:0] c_tag_curr = cpu_phys_dword[20:10];
// Disable broken BSRAM L1 cache (BSRAM 1-cycle latency caused stale data reads and Turbo Pascal compiler corruption)
wire        c_hit = 1'b0;

// CPU-clock side: latch a request only when the CPU is free.  Once latched,
// all payload bits remain frozen until the SDRAM side completes the access.
always @(posedge clk) begin
    if (reset) begin
        cpu_req_toggle    <= 1'b0;
        cpu_busy_cpu      <= 1'b0;
        cpu_just_done     <= 1'b0;
        c_hit_pending     <= 1'b0;
        read_waiting_wbuf <= 1'b0;
        wbuf_wr_ptr       <= 5'd0;
        c_valid           <= 1024'd0;
        cpu_sdr_addr_hold <= 23'd0;
        cpu_din_hold      <= 32'd0;
        cpu_wmask_hold    <= 4'd0;
        rom_pending_cpu   <= 1'b0;
        cpu_ack_sync1     <= 1'b0;
        cpu_ack_sync2     <= 1'b0;
        cpu_ack_seen      <= 1'b0;
        dram_dout_r       <= 32'd0;
    end else begin
        if (flush || ems_flush) c_valid <= 1024'd0;

        cpu_ack_sync1 <= cpu_ack_toggle_sdr;
        cpu_ack_sync2 <= cpu_ack_sync1;

        if (c_hit_pending) begin
            // 2-cycle cache hit completed: release CPU!
            c_hit_pending <= 1'b0;
            cpu_busy_cpu  <= 1'b0;
            cpu_just_done <= 1'b1;
        end else if (cpu_ack_sync2 != cpu_ack_seen) begin
            // SDRAM transaction completed: release CPU and update cache
            cpu_ack_seen  <= cpu_ack_sync2;
            dram_dout_r   <= cpu_rdata_hold_sdr;
            cpu_busy_cpu  <= 1'b0;
            cpu_just_done <= 1'b1;

            if (~is_ems && cpu_wmask_hold == 4'b0000) begin
                // Read miss: populate cache (only non-EMS pages)
                c_data[cpu_sdr_addr_hold[9:0]]  <= cpu_rdata_hold_sdr;
                c_tag[cpu_sdr_addr_hold[9:0]]   <= cpu_sdr_addr_hold[20:10];
                c_valid[cpu_sdr_addr_hold[9:0]] <= 1'b1;
            end else begin
                // Write: invalidate matching cache line to preserve coherency
                if (c_tag[cpu_sdr_addr_hold[9:0]] == cpu_sdr_addr_hold[20:10])
                    c_valid[cpu_sdr_addr_hold[9:0]] <= 1'b0;
            end
        end else if (read_waiting_wbuf) begin
            if (wbuf_empty) begin
                // Write buffer has drained! Now launch the read to SDRAM:
                read_waiting_wbuf <= 1'b0;
                cpu_sdr_addr_hold <= {2'b00, cpu_phys_dword};
                cpu_din_hold      <= din;
                cpu_wmask_hold    <= 4'b0000;
                cpu_req_toggle    <= ~cpu_req_toggle;
            end
        end else if (cpu_just_done) begin
            cpu_just_done <= 1'b0;
        end else if (~cpu_busy_cpu && dram_cs) begin
            if (WRE) begin
                // Write transaction!
                if (!wbuf_full) begin
                    wbuf_addr[wbuf_wr_ptr[3:0]]  <= cpu_phys_dword;
                    wbuf_din[wbuf_wr_ptr[3:0]]   <= din;
                    wbuf_wmask[wbuf_wr_ptr[3:0]] <= wmask;
                    wbuf_wr_ptr <= wbuf_wr_ptr + 1'b1;

                    // Invalidate cache line to preserve coherency
                    c_valid[c_idx] <= 1'b0;
                end else begin
                    // Buffer is full: stall CPU until slot frees
                    cpu_busy_cpu <= 1'b1;
                end
            end else if (c_hit) begin
                // Cache hit! Latch data and stall for exactly 1 cycle (2 cycles total)
                dram_dout_r       <= c_data[c_idx];
                cpu_sdr_addr_hold <= {2'b00, cpu_phys_dword};
                c_hit_pending     <= 1'b1;
                cpu_busy_cpu      <= 1'b1;
            end else begin
                // Read miss!
                if (wbuf_empty) begin
                    cpu_sdr_addr_hold <= {2'b00, cpu_phys_dword};
                    cpu_din_hold      <= din;
                    cpu_wmask_hold    <= 4'b0000;
                    cpu_req_toggle    <= ~cpu_req_toggle;
                    cpu_busy_cpu      <= 1'b1;
                end else begin
                    read_waiting_wbuf <= 1'b1;
                    cpu_busy_cpu      <= 1'b1;
                end
            end
        end else if (cpu_busy_cpu && dram_cs && WRE && !read_waiting_wbuf && !c_hit_pending && (cpu_ack_sync2 == cpu_ack_seen)) begin
                // CPU was stalled because wbuf was full. As soon as a slot is freed:
                if (!wbuf_full) begin
                    wbuf_addr[wbuf_wr_ptr[3:0]]  <= cpu_phys_dword;
                    wbuf_din[wbuf_wr_ptr[3:0]]   <= din;
                    wbuf_wmask[wbuf_wr_ptr[3:0]] <= wmask;
                    wbuf_wr_ptr <= wbuf_wr_ptr + 1'b1;

                    // Invalidate cache line to preserve coherency
                    c_valid[c_idx] <= 1'b0;

                    cpu_busy_cpu  <= 1'b0;
                    cpu_just_done <= 1'b1;
                end
            end
    end
end

// SDRAM-domain request copy.  req_sync2 has already crossed two SDRAM-clock
// stages before the payload is sampled, while the CPU is stalled and holding
// every bus field constant.
reg        req_sync1_sdr;
reg        req_sync2_sdr;
reg        req_seen_sdr;
reg        cpu_req;
reg        cpu_wr_q;
reg [22:0] cpu_sdr_addr_q;
reg [31:0] cpu_din_q;
reg [3:0]  cpu_dqm_q;

// --- Forward declarations for VGA signals used in arbiter ---
reg [15:0] vga_buf   [0:15];
reg [15:0] vga_buf_hi[0:15];
reg [3:0]  vga_fill_idx;
reg [3:0]  vga_out_idx;
reg [23:0] vga_base_addr;
localparam VGA_IDLE=2'd0, VGA_FETCH=2'd1, VGA_STREAM=2'd2;
reg [1:0]  vga_st;
wire       vga_req = (vga_st == VGA_FETCH);
wire [22:0] vga_sdr_word_addr = vga_base_addr[22:0] + {19'b0, vga_fill_idx};

// ---------------------------------------------------------------------
// Single arbiter: the only place that drives sdr_rd/sdr_wr/sdr_refresh/
// sdr_addr/sdr_din/sdr_dqm. Priority: refresh > VGA > CPU.
// ---------------------------------------------------------------------
// Display DMA (VGA) has strict hard-real-time priority over CPU.
// While vga_st == VGA_FETCH, vga_req is held continuously high across
// the entire 8-word burst, preventing CPU memory accesses (e.g. REP MOVSW)
// from interleaving between words and starving the video FIFO.
// ---------------------------------------------------------------------
localparam ARB_IDLE=2'd0, ARB_WAIT=2'd1, ARB_BUSY=2'd2;
reg [1:0] arb_st;
reg       arb_owner_cpu;
reg       arb_owner_wbuf;
reg       vga_grant_rdata;
reg       init_done;

always @(posedge sdram_clk) begin
    if (reset) begin
        req_sync1_sdr   <= 1'b0;
        req_sync2_sdr   <= 1'b0;
        req_seen_sdr    <= 1'b0;
        cpu_req         <= 1'b0;
        cpu_wr_q        <= 1'b0;
        cpu_sdr_addr_q  <= 23'd0;
        cpu_din_q       <= 32'd0;
        cpu_dqm_q       <= 4'hf;
        cpu_ack_toggle_sdr <= 1'b0;
        cpu_rdata_hold_sdr <= 32'd0;
        cpu_read_ack_pending_sdr <= 1'b0;
        arb_st          <= ARB_IDLE;
        arb_owner_wbuf  <= 1'b0;
        wbuf_rd_ptr     <= 5'd0;
        sdr_rd          <= 1'b0;
        sdr_wr          <= 1'b0;
        sdr_refresh     <= 1'b0;
        vga_grant_rdata <= 1'b0;
        init_done       <= 1'b0;
    end else begin
        req_sync1_sdr <= cpu_req_toggle;
        req_sync2_sdr <= req_sync1_sdr;

        sdr_rd <= 1'b0;
        sdr_wr <= 1'b0;
        sdr_refresh <= 1'b0;
        vga_grant_rdata  <= 1'b0;

        // Hold read data for one full SDRAM clock before toggling the CPU ACK.
        // This guarantees the payload is stable independently of the one-cycle
        // data_ready/dq_in window in sdram32.
        if (cpu_read_ack_pending_sdr) begin
            cpu_ack_toggle_sdr <= ~cpu_ack_toggle_sdr;
            cpu_read_ack_pending_sdr <= 1'b0;
        end

        if (~sdr_busy) init_done <= 1'b1;

        // Detect a new CPU transaction after the toggle synchronizer.
        if ((req_sync2_sdr != req_seen_sdr) && ~cpu_req) begin
            req_seen_sdr   <= req_sync2_sdr;
            cpu_sdr_addr_q <= cpu_sdr_addr_hold;
            cpu_din_q      <= cpu_din_hold;
            cpu_dqm_q      <= ~cpu_wmask_hold;
            cpu_wr_q       <= (cpu_wmask_hold != 4'b0000);
            cpu_req        <= 1'b1;
        end

        case (arb_st)
            ARB_IDLE: begin
                if (refresh_req) begin
                    sdr_refresh <= 1'b1;
                    arb_owner_cpu  <= 1'b0;
                    arb_owner_wbuf <= 1'b0;
                    arb_st <= ARB_WAIT;
                end else if (vga_req) begin
                    sdr_addr <= vga_sdr_word_addr;
                    sdr_rd   <= 1'b1;
                    arb_owner_cpu  <= 1'b0;
                    arb_owner_wbuf <= 1'b0;
                    arb_st <= ARB_WAIT;
                end else if (wbuf_avail) begin
                    sdr_addr <= {2'b00, wbuf_addr[wbuf_rd_ptr[3:0]]};
                    sdr_din  <= wbuf_din[wbuf_rd_ptr[3:0]];
                    sdr_dqm  <= ~wbuf_wmask[wbuf_rd_ptr[3:0]];
                    sdr_wr   <= 1'b1;
                    arb_owner_wbuf <= 1'b1;
                    arb_owner_cpu  <= 1'b0;
                    arb_st   <= ARB_WAIT;
                end else if (cpu_req) begin
                    sdr_addr <= cpu_sdr_addr_q;
                    if (cpu_wr_q) begin
                        sdr_din <= cpu_din_q;
                        sdr_dqm <= cpu_dqm_q;
                        sdr_wr  <= 1'b1;
                    end else begin
                        sdr_rd  <= 1'b1;
                    end
                    cpu_req <= 1'b0;
                    arb_owner_cpu  <= 1'b1;
                    arb_owner_wbuf <= 1'b0;
                    arb_st <= ARB_WAIT;
                end
            end
            ARB_WAIT: begin
                arb_st <= ARB_BUSY;
            end
            ARB_BUSY: begin
                if (sdr_data_ready) begin
                    if (arb_owner_cpu) begin
                        cpu_rdata_hold_sdr <= sdr_dout;
                        cpu_read_ack_pending_sdr <= 1'b1;
                    end else begin
                        vga_grant_rdata <= 1'b1;
                    end
                end else if (~sdr_busy) begin
                    if (arb_owner_wbuf) begin
                        wbuf_rd_ptr <= wbuf_rd_ptr + 1'b1;
                        arb_owner_wbuf <= 1'b0;
                    end else if (arb_owner_cpu && cpu_wr_q) begin
                        cpu_rdata_hold_sdr <= sdr_dout;
                        cpu_ack_toggle_sdr <= ~cpu_ack_toggle_sdr;
                    end
                    arb_st <= ARB_IDLE;
                end
            end
        endcase
    end
end

// ---------------------------------------------------------------------
// Debug status byte for port 03FEh (see system.v COM0_DOUT mux).
// Bits are latched in the SDRAM clock domain (where arb_st/sdr_busy/
// sdr_data_ready/cpu_req/arb_owner_cpu actually live) then double-flopped
// into the CPU clock domain, exactly like cpu_ack_toggle_sdr above, so the
// byte the CPU reads via IN AL,0FEh is metastability-safe. cpu_busy_cpu,
// ce and dram_cs already live in the CPU domain and need no crossing.
// Layout (bit7 kept as the pre-existing tx0_bsy in system.v, NOT set here):
//   bit6 = arb_owner_cpu   bit5 = cpu_req (SDRAM-domain, synced)
//   bit4 = sdr_data_ready  bit3 = sdr_busy
//   bit2 = dram_cs         bit1 = cpu_busy_cpu     bit0 = ~ce (i.e. CE==0)
// ---------------------------------------------------------------------
reg arb_owner_cpu_sdr_q, cpu_req_sdr_q, sdr_data_ready_sdr_q, sdr_busy_sdr_q;
always @(posedge sdram_clk) begin
    arb_owner_cpu_sdr_q  <= arb_owner_cpu;
    cpu_req_sdr_q         <= cpu_req;
    sdr_data_ready_sdr_q  <= sdr_data_ready;
    sdr_busy_sdr_q        <= sdr_busy;
end

reg [3:0] dbg_sdr_sync1, dbg_sdr_sync2;
always @(posedge clk) begin
    dbg_sdr_sync1 <= {arb_owner_cpu_sdr_q, cpu_req_sdr_q, sdr_data_ready_sdr_q, sdr_busy_sdr_q};
    dbg_sdr_sync2 <= dbg_sdr_sync1;
end

assign dbg_sdram_state = {1'b0, dbg_sdr_sync2, dram_cs, cpu_busy_cpu, ~ce};

// --- VGA framebuffer streaming pipeline ----------------------------------
reg [15:0] sys_DOUT_r;
assign sys_DOUT = sys_DOUT_r;
`ifdef SIM_DEBUG_VGA
wire [15:0] dbg_buf_sel    = vga_buf[vga_out_idx[3:1]];
wire [15:0] dbg_buf_hi_sel = vga_buf_hi[vga_out_idx[3:1]];
`endif

always @(posedge sdram_clk) begin
    if (reset) begin
        vga_st <= VGA_IDLE; sys_cmd_ack <= 2'b00; sys_rd_data_valid <= 0; sys_DOUT_r <= 16'h0;
        vga_fill_idx <= 4'd0; vga_out_idx <= 4'd0; vga_base_addr <= 24'd0;
    end else begin
        sys_rd_data_valid <= 0;
        case (vga_st)
            VGA_IDLE: if (sys_CMD == 2'b10) begin
                vga_base_addr <= sdraddr;
                vga_fill_idx  <= 4'd0;
                vga_out_idx   <= 4'd0;
                sys_cmd_ack   <= 2'b10;
                vga_st        <= VGA_FETCH;
            end
            VGA_FETCH: begin
                if (vga_grant_rdata) begin
                    vga_buf[vga_fill_idx]    <= sdr_dout[15:0];
                    vga_buf_hi[vga_fill_idx] <= sdr_dout[31:16];
`ifdef SIM_DEBUG_VGA
                    $display("[%0t] VGA_FETCH capture idx=%0d addr=%h sdr_dout=%h -> lo=%h hi=%h",
                        $time, vga_fill_idx, sdr_addr, sdr_dout, sdr_dout[15:0], sdr_dout[31:16]);
`endif
                    if (vga_fill_idx == 4'd7) vga_st <= VGA_STREAM;
                    else begin
                        vga_fill_idx <= vga_fill_idx + 1'b1;
                    end
                end
            end
            VGA_STREAM: begin
                sys_rd_data_valid <= 1;
                sys_DOUT_r <= vga_out_idx[0] ? vga_buf_hi[vga_out_idx[3:1]] : vga_buf[vga_out_idx[3:1]];
`ifdef SIM_DEBUG_VGA
                $strobe("[%0t] VGA_STREAM out_idx=%0d bit0=%b word_idx=%0d buf=%h buf_hi=%h -> sys_DOUT_r(next)=%h",
                    $time, vga_out_idx, vga_out_idx[0], vga_out_idx[3:1],
                    dbg_buf_sel, dbg_buf_hi_sel,
                    vga_out_idx[0] ? dbg_buf_hi_sel : dbg_buf_sel);
`endif
                if (vga_out_idx == 15) begin
                    sys_cmd_ack <= 2'b00;
                    vga_st <= VGA_IDLE;
                end else vga_out_idx <= vga_out_idx + 1'b1;
            end
            default: vga_st <= VGA_IDLE;
        endcase
    end
end

endmodule
`default_nettype wire
