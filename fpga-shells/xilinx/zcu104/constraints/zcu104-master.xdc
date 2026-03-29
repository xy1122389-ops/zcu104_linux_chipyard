#-------------- Clock ----------------------
# ZCU104 board 125 MHz differential PL clock
set_property PACKAGE_PIN F23        [get_ports {sys_clock_p}]
set_property PACKAGE_PIN E23        [get_ports {sys_clock_n}]
set_property IOSTANDARD LVDS        [get_ports {sys_clock_p}]
set_property IOSTANDARD LVDS        [get_ports {sys_clock_n}]

#-------------- UART on PMOD1 ----------------------
# PMOD1_0 -> TX, PMOD1_1 -> RX
set_property PACKAGE_PIN J9         [get_ports {uart_txd}]
set_property IOSTANDARD LVCMOS33    [get_ports {uart_txd}]
set_property PACKAGE_PIN K9         [get_ports {uart_rxd}]
set_property IOSTANDARD LVCMOS33    [get_ports {uart_rxd}]

#-------------- JTAG on PMOD0_4..0_7 ----------------------
# TDI -> PMOD0_4 -> G6
# TMS -> PMOD0_5 -> H6
# TCK -> PMOD0_6 -> J6
# TDO -> PMOD0_7 -> J7
set_property PACKAGE_PIN G6         [get_ports {jtag_jtag_TDI}]
set_property IOSTANDARD LVCMOS33    [get_ports {jtag_jtag_TDI}]
set_property PACKAGE_PIN H6         [get_ports {jtag_jtag_TMS}]
set_property IOSTANDARD LVCMOS33    [get_ports {jtag_jtag_TMS}]
set_property PACKAGE_PIN J6         [get_ports {jtag_jtag_TCK}]
set_property IOSTANDARD LVCMOS33    [get_ports {jtag_jtag_TCK}]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets [get_ports {jtag_jtag_TCK}]]
set_property PACKAGE_PIN J7         [get_ports {jtag_jtag_TDO}]
set_property IOSTANDARD LVCMOS33    [get_ports {jtag_jtag_TDO}]

#-------------- LED DS39 ----------------------
# DS39 -> GPIO_LED_2_LS -> A5
set_property PACKAGE_PIN A5         [get_ports {gpio_led_2_ls}]
set_property IOSTANDARD LVCMOS33    [get_ports {gpio_led_2_ls}]

#-------------- Bitstream Settings ----------------------
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
