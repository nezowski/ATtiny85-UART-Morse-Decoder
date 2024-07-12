.include "tn85def.inc"  ; Include the ATtiny85 definitions

;	This is simple uart to morse code translator
;	Connect speaker to pin 6 (PB1) and TX from transmitter to pin 3 (PB4)
;	Baud rate is 9600
;	It accepts only upper case letters and spaces, idk what happens if u send anything else

.equ CURRENT_CHARACTER = SRAM_START			; 1 byte
.equ ZERO_COUNT = SRAM_START + 1			; 1 byte, keeps track of how many zeros was sent since last (helps recognizing end of character) 

.equ CURRENT_BIT = SRAM_START + 2			; 1 byte, indicates which bit is currently being sent
.equ BYTE_COUNT = SRAM_START + 3			; 1 byte, indicates which byte is currently being sent by computer (or any other uart device)
.equ BUFFER = SRAM_START + 4				; 1 byte, byte that is currently being sent
.equ RECEIVED_MESSAGE = SRAM_START + 5		; rest of memory, whole received message by uart

.def temp_reg = r16

.cseg
.org 0x0000
    rjmp RESET			; Reset - Address 0
	reti				; INT0 (address 01)
	reti				; Pin Change Interrupt Request 0        
	rjmp TIMER1_ISR		; Timer/Counter1 Compare Match A
	reti				; Timer/Counter1 Overflow
	reti				; Timer/Counter0 Overflow
	reti				; EEPROM Ready
	reti				; Analog Comparator
	reti				; ADC Conversion Complete
	reti				; Timer/Counter1 Compare Match B
	rjmp TIMER0_ISR		; Timer/Counter0 Compare Match A
	reti				; Timer/Counter0 Compare Match B
	reti				; Watchdog Time-out
	reti				; USI START
	reti				; USI Overflow
	
; to use an interrupt, change the "reti" above to rjmp



RESET:
	ldi temp_reg, (1 << PB0) | (1 << PB1)	; PB0 -> LED, PB1 -> Speaker, PB4 -> RX
	out DDRB, temp_reg

	ldi temp_reg, (1 << PB4)	; PB4 input pull-up
	out PORTB, temp_reg

	; TIMER0 104 us period, CTC 0110 1000 (first boot 156us -> 104 of startbit and 52 to read on half of bit)
	; Interrupt OCA

	ldi temp_reg, (1 << WGM01)				; disconnected from output, CTC mode
	out TCCR0A, temp_reg

	;ldi temp_reg, (1 << CS00)				; no prescaling
	;out TCCR0B, temp_reg

	ldi temp_reg, 0x68						; 104us
	out OCR0A, temp_reg

	; TIMER 1  1040 us period, CTC 1110 1010, /4 divider, interrupt OCA

	;ldi temp_reg, (1 << CTC1) | (1 << CS11) | (1 << CS10) for enabling counter
	;out TCCR1, temp_reg

	ldi temp_reg, 0xEA						; 936us
	out OCR1A, temp_reg
	out OCR1C, temp_reg

	ldi r17, 40
	clr temp_reg
	ldi ZL, low(CURRENT_CHARACTER)
	ldi ZH, high(CURRENT_CHARACTER)				; clear 40 bytes in ram 
	CLEAR_LOOP:
	st Z, temp_reg
	adiw ZL, 1
	dec r17
	brne CLEAR_LOOP



HALF_RESET:	
	ldi temp_reg, (1 << OCIE1A) | (1 << OCIE0A)
	out TIMSK, temp_reg						; enable interrupts

	ldi temp_reg, 0
	out TCCR0B, temp_reg					; turn off Timer0

	ldi temp_reg, (1 << CTC1)				; turn off Timer1
	out TCCR1, temp_reg

	; CLEAR SRAM AND TIMER
	clr temp_reg
	sts CURRENT_BIT, temp_reg
	sts BUFFER, temp_reg
	out TCNT0, temp_reg
	out TCNT1, temp_reg

	ser temp_reg
	out TIFR, temp_reg						; clear interrupts flags

	lds temp_reg, BYTE_COUNT
	tst temp_reg				; simply test if this is first loop or in middle of transmission
	brne NEXT






FIRST_LOOP:						; wait for startbit (rx = 0)
	in temp_reg, PINB
	bst temp_reg, PB4
	brts FIRST_LOOP
	rjmp DONE_WAITING

NEXT:							; wait of startbit OR timeout (means that there is no data to send)
	ldi r17, 0
NEXT_LOOP:
	inc r17
	breq SET_UP_MORSE
	in temp_reg, PINB
	bst temp_reg, PB4
	brts NEXT_LOOP

DONE_WAITING:
	ldi temp_reg, (1 << CTC1) | (1 << CS11) | (1 << CS10)
	out TCCR1, temp_reg
	ldi temp_reg, (1 << CS00)				; enabling both timers
	out TCCR0B, temp_reg

	RECEIVING_LOOP:
	cli
	lds temp_reg, CURRENT_BIT			; wait for interrupt OR if CURRENT_BIT is set (flag that means whole frame has been sent)
	bst temp_reg, 7
	brts HALF_RESET			; if whole frame has been sent do a half reset (enable interrupts, turn off timers, clear RAM and timers)
	sei
	rjmp RECEIVING_LOOP




TIMER0_ISR:				;========== TIMER 0 ISR (read) ==========;
	push temp_reg
	push r17
	
	in temp_reg, PINB
	bst temp_reg, 4
	clr temp_reg					; check if 0 or 1 is being sent (1 -> temp_reg = 0x01,  0 -> temp_reg = 0x00
	bld temp_reg, 0
	lds r17, CURRENT_BIT

	inc r17
	sts CURRENT_BIT, r17			;\
	T0_ISR_LOOP:					; |
	dec r17							; |
	breq T0_ISR_END_OF_LOOP			; | temp_reg << r17 operation
	lsl temp_reg					; |
	rjmp T0_ISR_LOOP				; |		let: temp_reg = 0x01, r17 = 5 (6 bit is being sent) -> temp_reg = 0x20
	T0_ISR_END_OF_LOOP:				;/
	
	lds r17, BUFFER

	or r17, temp_reg				; set bit of current byte	let: BUFFER = 0x16 -> 0x36
	sts BUFFER, r17


	pop r17
	pop temp_reg
	reti



TIMER1_ISR:							;========== TIMER 1 ISR (reset) ==========;
	clr temp_reg
	out TIMSK, temp_reg				; disable interrupts

	ser temp_reg
	sts CURRENT_BIT, temp_reg		; set flag for received byte


	ldi ZL, low(RECEIVED_MESSAGE)
	ldi ZH, high(RECEIVED_MESSAGE)	; load start of string

	lds temp_reg, BYTE_COUNT
	add ZL, temp_reg				; add BYTE_COUNT to ensure byte is written to correct place
	adc ZH, r1

	inc temp_reg
	sts BYTE_COUNT, temp_reg		; while BYTE_COUNT is in temp_reg, increment that (prepare for next byte)

	lds temp_reg, BUFFER
	st Z, temp_reg

	reti


SET_UP_MORSE:
	cli		; its pointless to use interrupt service routines as it would require redesign them, much simpler way is just to check for flag

						;============== SETTING UP TIMER1 ==============;
	ldi temp_reg, (1 << CTC1) | (1 << COM1A0) | (1 << CS11) | (1 << CS10)
	out TCCR1, temp_reg			; setting CTC mode; toggle the OC1A output line; Clock/4 prescaler
	ldi temp_reg, 0xE1
	out OCR1A, temp_reg
	out OCR1C, temp_reg			; setting both Output Compare Register C and A to 0xE1, which is around 563Hz with /4 divider

						;============== SETTING UP TIMER0 ==============;
	ldi temp_reg, (1 << WGM01)
	out TCCR0A, temp_reg		; setting CTC mode
	ldi temp_reg, 0xEA
	out OCR0A, temp_reg			; setting Output Compare Register A to 0xEA, which is around 60ms with /8 divider
	ldi temp_reg, (1 << CS02)
	out TCCR0B, temp_reg		; setting prescaler to /8
	ldi temp_reg, (1 << OCIE0A)
	out TIMSK, temp_reg			; enabling Timer/Counter0 A Output Compare Interrupt

	rjmp FIRST_BOOT			; it loads first character in morse to X-register without waiting 60ms

	LOOP:
	in temp_reg, TIFR
	sbrs temp_reg, 4 
	rjmp LOOP						; wait for interrupt flag (60ms has passed)

	ldi temp_reg, 0x40
	out TIFR, temp_reg				; clear flag manually (idk why writing 1 is clearing it but ok)
	
	lds temp_reg, ZERO_COUNT

	cpi temp_reg, 3
	breq NEXT_CHAR
	cpi temp_reg, 7
	breq NEXT_CHAR					; if there are 3 (another character) or 7 (space) zeros in a row load another character to X register
	rjmp NEXT_ELEMENT				; if not just send another element

NEXT_CHAR:

	lds temp_reg, CURRENT_CHARACTER
	inc temp_reg						; increment CURRENT_CHAR and store it to RAM
	sts CURRENT_CHARACTER, temp_reg
FIRST_BOOT:
	ldi ZL, low(RECEIVED_MESSAGE)
	ldi ZH, high(RECEIVED_MESSAGE)		; get message label address
	lds temp_reg, CURRENT_CHARACTER		; check what character should be transmitted now
	add ZL, temp_reg					; take into account which letter to read
	brne NO_OVERFLOW
	inc ZH
	NO_OVERFLOW:

	ld r0, Z						; read a letter
	
	ldi temp_reg, 0x20
	cp r0, temp_reg					; check if loaded letter isnt space
	breq SEND_SPACE					; sets X register to 0

	ldi temp_reg, 0
	cp r0, temp_reg					; check if loaded letter isnt 0 (nop at end of message)
	breq FAR_RESET					; goes to reset vector


	ldi r17, 'A'
	sub r0, r17						; convert from ascii to 0 - 25 number


	lsl r0							; multiply by 2, as each letter takes 2 bytes
	ldi ZL, low(LETTERS*2)
	ldi ZH, high(LETTERS*2)			; load address of LETTERS
	add ZL, r0						; take into account what letter to read
	adc ZH, temp_reg				; adding carry to ZH

	lpm XL, Z+
	lpm XH, Z						; loads letter instruction (. _ _ type shit) into X register
	rjmp NEXT_ELEMENT

SEND_SPACE:
	ldi XL, 0
	ldi XH, 0

NEXT_ELEMENT:
	bst XL, 0						; read what element to send

	ror XH
	ror XL							; prepare register for next element
	andi XH, 0x7F					; dont let to wrap around to elements from same character


	lds temp_reg, ZERO_COUNT


	brts TRANSMISSION_LABEL_1
	rcall BEEP_OFF					; 0 is being trasmitted, zero count is incremented
	inc temp_reg
	rjmp TRANSMISSION_LABEL_0
TRANSMISSION_LABEL_1:
	rcall BEEP_ON					; 1 is being transmitted, zero count is reset
	ldi temp_reg, 0
TRANSMISSION_LABEL_0:

	sts ZERO_COUNT, temp_reg


	clt								; clear T flag, it will be set by an interrupt (60ms time period)
	rjmp LOOP						; END OF LOOP

BEEP_ON:
	sbi PORTB, 0					; turn LED on
	push temp_reg
	in temp_reg, TCCR1
	sbr temp_reg, (1 << COM1A0)		; connects Timer1 Comparator with output pin (PB1) and sets it on toggle
	out TCCR1, temp_reg
	pop temp_reg
	ret

BEEP_OFF:
	cbi PORTB, 0
	push temp_reg
	in temp_reg, TCCR1
	cbr temp_reg, (1 << COM1A0)		; disconnects Timer1 Comparator from output pin (PB1)
	out TCCR1, temp_reg
	pop temp_reg
	ret

FAR_RESET:
	cbi PORTB, 0
	cli
	rcall BEEP_OFF
	ldi ZL, 0
	ldi ZH, 0
	ijmp




LETTERS:
	.dw 0b0000000000011101  ; A
    .dw 0b0000000101010111  ; B
    .dw 0b0000010111010111  ; C
    .dw 0b0000000001010111  ; D
    .dw 0b0000000000000001  ; E
    .dw 0b0000000101110101  ; F
    .dw 0b0000000101110111  ; G
    .dw 0b0000000001010101  ; H
    .dw 0b0000000000000101  ; I
    .dw 0b0001110111011101  ; J
    .dw 0b0000000111010111  ; K
    .dw 0b0000000101011101  ; L
    .dw 0b0000000001110111  ; M
    .dw 0b0000000000010111  ; N
    .dw 0b0000011101110111  ; O
    .dw 0b0000010111011101  ; P
    .dw 0b0001110101110111  ; Q
    .dw 0b0000000001011101  ; R
    .dw 0b0000000000010101  ; S
    .dw 0b0000000000000111	; T
    .dw 0b0000000001110101  ; U
    .dw 0b0000000111010101  ; V
    .dw 0b0000000111011101  ; W
    .dw 0b0000011101010111  ; X
    .dw 0b0001110111010111  ; Y
    .dw 0b0000010101110111	; Z

