# Next186 / Tang Nano 20K timing constraints
# GW2AR-LV18QN88C8/I7
#
# Gowin TA: internal generated clocks are constrained as clocks on the
# corresponding RTL nets.  Keep each PLL family synchronous internally,
# and make the two PLL families asynchronous to each other.

create_clock -name clk27M -period 37.037 -waveform {0 18.5185} [get_ports {clk27M}]

create_clock -name clk_sys -period 15.432 -waveform {0 7.716} [get_pins {clkgen/rpll_inst/CLKOUT}]
create_clock -name clk_cpu -period 46.296 -waveform {0 23.148} [get_pins {clkgen/rpll_inst/CLKOUTD3}]
create_clock -name clk_tmds -period 7.936 -waveform {0 3.968} [get_pins {u_pll/rpll_inst/CLKOUT}]
create_clock -name clk_pixel -period 39.682 -waveform {0 19.841} [get_pins {u_div_5/clkdiv_inst/CLKOUT}]
create_clock -name clk_aud -period 88.574 -waveform {0 44.287} [get_nets {sys_inst/clk_aud}]

set_clock_groups -asynchronous -group [get_clocks {clk27M}] -group [get_clocks {clk_sys}] -group [get_clocks {clk_cpu}] -group [get_clocks {clk_tmds clk_pixel}] -group [get_clocks {clk_aud}]

# Vendor dual-clock FIFO internal asynchronous pointer/reset paths.
set_false_path -from [get_pins {sys_inst/vga_fifo/fifo_inst/Big.wptr_3_s0/CLK}] -to [get_pins {sys_inst/vga_fifo/fifo_inst/Empty_s0/PRESET}]
set_false_path -from [get_pins {sys_inst/vga_fifo/fifo_inst/Big.wptr_3_s0/CLK}] -to [get_pins {sys_inst/vga_fifo/fifo_inst/rempty_val1_s0/PRESET}]
set_false_path -from [get_pins {sys_inst/vga_fifo/fifo_inst/Big.rptr_1_s0/CLK}] -to [get_pins {sys_inst/vga_fifo/fifo_inst/wfull_val1_s0/PRESET}]
set_false_path -from [get_pins {sys_inst/vga_fifo/fifo_inst/Big.rptr_1_s0/CLK}] -to [get_pins {sys_inst/vga_fifo/fifo_inst/Full_s0/PRESET}]
set_false_path -from [get_pins {sys_inst/vga_fifo/fifo_inst/Big.rptr_8_s0/CLK}] -to [get_pins {sys_inst/vga_fifo/fifo_inst/wfull_val1_s0/PRESET}]
set_false_path -from [get_pins {sys_inst/vga_fifo/fifo_inst/Big.rptr_8_s0/CLK}] -to [get_pins {sys_inst/vga_fifo/fifo_inst/Full_s0/PRESET}]
set_false_path -from [get_pins {sys_inst/vga_fifo/fifo_inst/Big.rptr_9_s0/CLK}] -to [get_pins {sys_inst/vga_fifo/fifo_inst/Empty_s0/PRESET}]
set_false_path -from [get_pins {sys_inst/vga_fifo/fifo_inst/Big.rptr_9_s0/CLK}] -to [get_pins {sys_inst/vga_fifo/fifo_inst/rempty_val1_s0/PRESET}]
