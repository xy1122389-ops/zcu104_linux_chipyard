#-------------- Clock ----------------------
# ZCU104 board 125 MHz differential PL clock
set_property PACKAGE_PIN F23        [get_ports {sys_clock_p}]
set_property PACKAGE_PIN E23        [get_ports {sys_clock_n}]
set_property IOSTANDARD LVDS        [get_ports {sys_clock_p}]
set_property IOSTANDARD LVDS        [get_ports {sys_clock_n}]

#-------------- UART on FT4232 Channel D ----------------------
# ZCU104 UG1267 Table 3-18:
#   FPGA TX -> A20 (UART2_TXD_FPGA_RXD -> FT4232 DDBUS1)
#   FPGA RX -> C19 (UART2_RXD_FPGA_TXD -> FT4232 DDBUS0)
# Bank 28 is 1.8V on the ZCU104 board.
set_property PACKAGE_PIN A20        [get_ports {uart_tx}]
set_property IOSTANDARD LVCMOS18    [get_ports {uart_tx}]
set_property PACKAGE_PIN C19        [get_ports {uart_rx}]
set_property IOSTANDARD LVCMOS18    [get_ports {uart_rx}]

#-------------- Bitstream Settings ----------------------
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
