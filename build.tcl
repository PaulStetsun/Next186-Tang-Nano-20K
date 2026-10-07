# Gowin EDA Command-Line Build Script for Next186_S_20K
# Usage: gw_sh.exe build.tcl

open_project Next186_S_20K.gprj
set_option -top_module Next186_SoC
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_done_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_reconfign_as_gpio 1
set_option -use_i2c_as_gpio 1
run all
