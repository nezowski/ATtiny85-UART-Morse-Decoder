
.include "tn85def.inc"  ; Include the ATtiny85 definitions

;	This is simple text to morse code translator
;	Connect speaker to pin 6 (PB1)
;	Sent message is below. You can send all letters of alphabet and space

.equ CURRENT_CHARACTER = SRAM_START
.equ ZERO_COUNT = SRAM_START + 1


.def temp_reg = r16

.cseg
.org 0x0000
    rjmp RESET			; Reset - Address 0
	reti				; INT0 (address 01)
	reti				; Pin Change Interrupt Request 0        
	reti				; Timer/Counter1 Compare Match A
	reti				; Timer/Counter1 Overflow
	reti				; Timer/Counter0 Overflow
	reti				; EEPROM Ready
	reti				; Analog Comparator
	reti				; ADC Conversion Complete
	reti				; Timer/Counter1 Compare Match B
	rjmp TIMER0_A_ISR	; Timer/Counter0 Compare Match A
	reti				; Timer/Counter0 Compare Match B
	reti				; Watchdog Time-out
	reti				; USI START
	reti				; USI Overflow
	
; to use an interrupt, change the "reti" above to rjmp
	
message: .db "GARNUCHY"
	nop

TIMER0_A_ISR:
	set					; set T flag to inform about an interupt
	reti

						; TIMER1 A -> 563Hz GENERATOR; TIMER0 B -> 60ms DELAY
						;
RESET:
	ldi temp_reg, 0
	sts CURRENT_CHARACTER, temp_reg
	sts ZERO_COUNT, temp_reg

	ldi temp_reg, (1 << PB1) | (1 << PB0)
	out DDRB, temp_reg			; setting pin 0 and 1 as outputs  
    ldi temp_reg, 0x00
	out PORTB, temp_reg			; clearing its outputs

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

	clr temp_reg
	ldi r17, 'A'				; for calucating letters


	sei
	rjmp FIRST_BOOT
	


LOOP:
	brtc LOOP						; wait for T bit to be set
	clt
	
	lds temp_reg, ZERO_COUNT

	cpi temp_reg, 3
	breq NEXT_CHAR
	cpi temp_reg, 7
	breq NEXT_CHAR					; if there are 3 (another character) or 7 (space) zeros in a row load another character to X register
	rjmp NEXT_ELEMENT				; if not just send another element

NEXT_CHAR:

	lds temp_reg, CURRENT_CHARACTER
	inc temp_reg					; increment CURRENT_CHAR and store it to RAM
	sts CURRENT_CHARACTER, temp_reg
FIRST_BOOT:
	ldi ZL, low(message*2)
	ldi ZH, high(message*2)			; get message label address
	lds temp_reg, CURRENT_CHARACTER	; check what character should be transmitted now
	add ZL, temp_reg				; take into account which letter to read

	lpm r0, Z						; read a letter
	
	ldi temp_reg, 0x20
	cp r0, temp_reg					; check if loaded letter isnt space
	breq SEND_SPACE					; sets X register to 0

	ldi temp_reg, 0
	cp r0, temp_reg					; check if loaded letter isnt 0 (nop at end of message)
	breq INFINITE_LOOP				; send it straight to hell


	sub r0, r17				; convert from ascii to 0 - 25 number


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

INFINITE_LOOP:
	cbi PORTB, 0
	cli
	rcall BEEP_OFF
DO_NOTHING:
	rjmp DO_NOTHING

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
    .dw 0b0000000000000111  ; T
    .dw 0b0000000001110101  ; U
    .dw 0b0000000111010101  ; V
    .dw 0b0000000111011101  ; W
    .dw 0b0000011101010111  ; X
    .dw 0b0001110111010111  ; Y
    .dw 0b0000010101110111  ; Z
