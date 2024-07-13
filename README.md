# ATtiny85 UART - Morse Decoder

This project is a simple UART to Morse code translator written in assembly for the ATtiny85 microcontroller. It accepts uppercase letters and spaces (will interpret as space if sent otherwise) sent via UART at a baud rate of 9600 and outputs a 563Hz Morse code signal at 20 words per minute (WPM). There is also version with morse message stored in program memory.

## Hardware Requirements
* ATtinyX5 microcontroller
* Programmer (e.g., Arduino)
* UART interface (e.g., Arduino or USB-to-Serial adapter)
* Buzzer
* Optional: LED
* Connecting wires and breadboard
## Connections
* Buzzer: Connect to PORTB 1 (pin 6).
* UART TX: Connect to PORTB 4 (pin 3).
* LED: Connect to PORTB 0 (pin 5) (optional)

Im GitHub newbie, idk what am I supposed to write here, feel free to do anything with it :)
