#-------------- Clock ----------------------
# ZCU104 board 125 MHz differential PL clock
set_property PACKAGE_PIN F23        [get_ports {sys_clock_p}]
set_property PACKAGE_PIN E23        [get_ports {sys_clock_n}]
set_property IOSTANDARD LVDS        [get_ports {sys_clock_p}]
set_property IOSTANDARD LVDS        [get_ports {sys_clock_n}]

#-------------- UART on PMOD1 ----------------------
# PMOD1_0 -> TX, PMOD1_1 -> RX
set_property PACKAGE_PIN J9         [get_ports {uart_tx}]
set_property IOSTANDARD LVCMOS33    [get_ports {uart_tx}]
set_property PACKAGE_PIN K9         [get_ports {uart_rx}]
set_property IOSTANDARD LVCMOS33    [get_ports {uart_rx}]

#-------------- Bitstream Settings ----------------------
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
