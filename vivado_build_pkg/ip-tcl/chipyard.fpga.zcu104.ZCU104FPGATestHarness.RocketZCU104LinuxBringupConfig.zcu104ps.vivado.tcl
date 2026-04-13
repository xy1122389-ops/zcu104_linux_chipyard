
      create_ip -vendor xilinx.com -library ip -name zynq_ultra_ps_e \
        -module_name zcu104ps -dir $ipdir -force
      set_property -dict [list \
        CONFIG.PSU_BANK_0_IO_STANDARD {LVCMOS18} \
        CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
        CONFIG.PSU__FPGA_PL0_ENABLE {1} \
        CONFIG.PSU__USE__S_AXI_GP2 {1} \
        CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
        CONFIG.PSU__USE__M_AXI_GP0 {0} \
        CONFIG.PSU__USE__M_AXI_GP1 {0} \
        CONFIG.PSU__USE__M_AXI_GP2 {0} \
        CONFIG.PSU__UART1__PERIPHERAL__ENABLE {1} \
        CONFIG.PSU__UART1__PERIPHERAL__IO {MIO 36 .. 37} \
        CONFIG.PSU__SD1__PERIPHERAL__ENABLE {1} \
        CONFIG.PSU__SD1__PERIPHERAL__IO {MIO 46 .. 51} \
        CONFIG.PSU__SD1__SLOT_TYPE {SD 2.0} \
        CONFIG.PSU__DDRC__MEMORY_TYPE {DDR 4} \
        CONFIG.PSU__DDRC__BUS_WIDTH {64 Bit} \
        CONFIG.PSU__DDRC__DDR4_ADDR_MAPPING {0} \
        CONFIG.PSU__DDRC__DEVICE_CAPACITY {4096 MBits} \
        CONFIG.PSU__DDRC__DRAM_WIDTH {16 Bits} \
        CONFIG.PSU__DDRC__ROW_ADDR_COUNT {15} \
        CONFIG.PSU__DDRC__BG_ADDR_COUNT {1} \
        CONFIG.PSU__DDRC__RANK_ADDR_COUNT {0} \
      ] [get_ips zcu104ps]
      generate_target all [get_ips zcu104ps]
    