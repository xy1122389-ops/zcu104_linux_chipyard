#-------------- Clock / Reset ----------------------
# ZCU104 125MHz differential clock on HDMI SI5395 output (PL side)
# User clock: 125 MHz on HDMI si5395 - use onboard 125MHz osc on CC pins
# sys_clk → HDMI_SI5395_LOL_N / HDMI_SI5395_LOL_P  (not ideal)
# Better: use the 125 MHz PL USER SI570 via J83
# For bring-up we use the PL 300 MHz CLK from PS (FCLK_CLK0), or
# the USER_SI570 ref at 300 MHz on HDMI port.
# ZCU104 has a 300 MHz PL clock on H11/G11 (DIFF_SSTL12)

set_property IOSTANDARD DIFF_SSTL12 [get_ports sys_diff_clock_clk_p]
set_property PACKAGE_PIN H11        [get_ports sys_diff_clock_clk_p]
set_property PACKAGE_PIN G11        [get_ports sys_diff_clock_clk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sys_diff_clock_clk_n]
create_clock -period 3.333 -name sys_diff_clk [get_ports sys_diff_clock_clk_p]

# CPU_RESET (PB3 - active low, pulled high)
set_property PACKAGE_PIN M11        [get_ports reset]
set_property IOSTANDARD LVCMOS33    [get_ports reset]

#-------------- UART ----------------------
# ZCU104 UART via USB-UART bridge (CP2108) on J164 connector
# TX → D11, RX → B11  (LVCMOS18)
set_property PACKAGE_PIN J9        [get_ports uart_txd]
set_property IOSTANDARD LVCMOS33    [get_ports uart_txd]
set_property PACKAGE_PIN K9        [get_ports uart_rxd]
set_property IOSTANDARD LVCMOS33    [get_ports uart_rxd]

#-------------- JTAG (PMOD J55 / FMC) ----------------------
# Use PMOD connector J55 for JTAG debug
# Bank 68 is HP → must use LVCMOS18 (not LVCMOS33)
set_property PACKAGE_PIN H12        [get_ports jtag_TCK]
set_property IOSTANDARD LVCMOS18    [get_ports jtag_TCK]
set_property PACKAGE_PIN E10        [get_ports jtag_TMS]
set_property IOSTANDARD LVCMOS18    [get_ports jtag_TMS]
set_property PACKAGE_PIN D10        [get_ports jtag_TDO]
set_property IOSTANDARD LVCMOS18    [get_ports jtag_TDO]
set_property PACKAGE_PIN C11        [get_ports jtag_TDI]
set_property IOSTANDARD LVCMOS18    [get_ports jtag_TDI]

#-------------- SD Card (PMOD J55 or onboard) ----------------------
# Bank 67/68 are HP → must use LVCMOS18 (not LVCMOS33)
set_property PACKAGE_PIN   F11      [get_ports spi_cs]
set_property IOSTANDARD LVCMOS18    [get_ports spi_cs]
set_property PACKAGE_PIN E12        [get_ports spi_sck]
set_property IOSTANDARD LVCMOS18    [get_ports spi_sck]
set_property PACKAGE_PIN D12        [get_ports spi_dq[0]]
set_property IOSTANDARD LVCMOS18    [get_ports spi_dq[0]]
set_property PACKAGE_PIN C12        [get_ports spi_dq[1]]
set_property IOSTANDARD LVCMOS18    [get_ports spi_dq[1]]

#-------------- Bitstream Settings ----------------------
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
