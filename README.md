chip-tools
==

NextThingCo C.H.I.P. Yocto tools.

This layer contains tools to flash and use the NextThingCo C.H.I.P. boards.


Flashing
--

Two bash scripts are available to flash the C.H.I.P. boards:
* chip-flash-chip.sh: to flash C.H.I.P. board.
* chip-flash-chip-pro.sh: to flash C.H.I.P. Pro board.

Instructions to use them are available in my Github at https://github.com/myfreescalewebpage/meta-chip.


Debug
--

Connecting to the C.H.I.P. boards is possible to access the linux console. Several possibilities exists:
* Throw the USB CDC Gadget interface.
* Throw the 3.3V TTL serial interface.

The 3.3V TTL serial interface is available on pins UART1-TX and UART1-RX on C.H.I.P. boards.

The following schema can be used to interface the 3.3V TTL interface to an RS232 compatible port.

![chip-serial-debug-rs232](https://github.com/myfreescalewebpage/chip-tools/blob/master/chip-serial-debug-rs232.png)

It is also possible to use an FTDI USB to 3.3V TTL converter.


Contributing
--

All contributions are welcome :-)

Use Github Issues to report anomalies or to propose enhancements (labels are available to clearly identify what you are writing) and Pull Requests to submit modifications.
