PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003

TEMP = $0010
value = $0020
mod10 = $0022
message = $0024
tenths = $0040
hundredths = $0041

E = %00010000
RW = %01000000
RS = %00100000

; SDA [7] and SCL [0]
; a 1 = LOW, 1 means OUTPUT, and PORT is set to LOW
; a 0 = HIGH, 0 means INPUT => High-Z w/pull-up
DHCH = %01110000
DHCL = %01110001
DLCH = %11110000
DLCL = %11110001

 .org($A000)
reset:
 ldx #$ff
 txs
 stx DDRB
 stz PORTA
 ldy #DHCH
 sty DDRA
 ldy #0
 sty $600B ;Auxiliary Control Register

 lda #%00111000
 jsr lcd_instruction
 lda #%00001110
 jsr lcd_instruction
 lda #%00000110
 jsr lcd_instruction
 lda #%00000001
 jsr lcd_instruction
 
 

temp_loop:
 stz message
 stz tenths
 stz hundredths
 clc
 
; get temperature from I2C sensor ---------------------------------
 jsr i2c_start
 ldx #2			;sending 2 bytes to periph
write_bytes:
 lda write_vector,x
 jsr i2c_write_byte
 dex
 bne write_bytes
 jsr i2c_release_lines

 jsr i2c_start
 lda read_vector
 jsr i2c_write_byte
read_bytes:
 jsr i2c_read_byte
 sta TEMP
 jsr i2c_write_ack
 jsr i2c_read_byte
 sta TEMP + 1
 jsr i2c_write_nack
 jsr i2c_stop

parse_temp:		;move >0 part to TEMP, <0 to TEMP+1, and sign to TEMP+2
 ldx #4
shiftleft:
 rol TEMP+1
 rol TEMP
 dex
 bne shiftleft
 lda #0
 rol
 sta TEMP+2
 lda TEMP+1
 and #$F0
 sta TEMP+1
 
 lda #"C"
 jsr push_char
 lda #" "  		;degree symbol
 jsr push_char

;very very inelegant way to process the <0 portion of temperature------------------
 clc
 rol TEMP+1
 bcc skiptenths
 lda #5
 sta tenths
skiptenths:
 rol TEMP+1
 bcc skiphundredths
 lda #5
 sta hundredths
 lda tenths
 clc
 adc #2
 sta tenths
skiphundredths:
 lda hundredths
 clc
 adc #"0"
 jsr push_char
 lda tenths
 clc
 adc #"0"
 jsr push_char
 lda #"."
 jsr push_char

; division and %10 to find digits ----------------------------
 lda TEMP
 sta value
 stz value+1
divide:
 stz mod10		;set remainder to zero
 stz mod10 + 1
 clc

 ldx #16
divloop:
 rol value
 rol value + 1
 rol mod10
 rol mod10 + 1
				;a,y = dividend - divisor
 sec
 lda mod10
 sbc #10
 tay 				;save low bytes in Y
 lda mod10 + 1
 sbc #0
 bcc ignore_result 	;branch if dividend < divisor
 sty mod10
 sta mod10 + 1
ignore_result:
 dex
 bne divloop
 rol value
 rol value + 1

; store each digit into a string (message)
 lda mod10
 clc
 adc #"0"
 jsr push_char


 lda value		;if value != 0, then continue dividing
 ora value + 1
 bne divide
 
; add "+" or "-" to begining of string -----------------------------------
 lda TEMP+2
 beq pos_temp	;if = 0, temp is positive
 lda #"-"
pos_temp:
 lda #"+"
 jsr push_char

; set cursor to position 0
 lda #($80 | $00)
 jsr lcd_instruction

; print the message --------------------------------------------------
 ldx #0
print:
 lda message,x
 beq loop
 jsr print_char
 inx
 jmp print

 

loop:
 jmp temp_loop ;take us to begining
 jmp loop ;-----------------------------
 



write_vector:
 .byte($00)
 .byte($05)
 .byte($30)

read_vector:
 .byte($31)
 
print_byte:
 ldx #8
 clc
printbit:
 rol
 pha
 bcs bitsetbyte
 lda #"0"
 jmp bitdonebyte
bitsetbyte:
 lda #"1"
bitdonebyte:
 jsr print_char
 pla
 dex
 bne printbit
 rts
 
push_char:
 ldy #0
char_loop:
 ldx message,y		;get char in string into X
 sta message,y		;pull char off stack and put in string
 iny
 txa
 bne char_loop
 sta message,y		;add null at end of string
 rts

check_bf:
 stz DDRB
bfset:
 ldy #RW
 sty PORTA
 ldy #(RW | E)
 sty PORTA
 ldy PORTB
 bmi bfset
 ldy #RW
 sty PORTA
 ldy #$ff
 sty DDRB
 rts

lcd_instruction:
 jsr check_bf
 sta PORTB
 lda #0
 sta PORTA
 lda #E
 sta PORTA
 lda #0
 sta PORTA
 rts

print_char:
 jsr check_bf
 sta PORTB
 lda #RS
 sta PORTA
 lda #(RS | E)
 sta PORTA
 lda #RS
 sta PORTA
 rts

i2c_read_byte:
 phx
 ldx #8
 lda #0
 clc
readbit:
 ldy #DHCH
 sty DDRA ;maybe put a delay???
 ldy PORTA
 bpl readdone
 inc
readdone:
 rol
 ldy #DHCL
 sty DDRA
 dex
 bne readbit
 ror
 plx
 rts

i2c_write_ack:
 ldy #DLCL
 sty DDRA
 ldy #DLCH
 sty DDRA
 ldy #DLCL
 sty DDRA
 ldy #DHCL
 sty DDRA
 rts

i2c_write_nack:
 ldy #DHCL
 sty DDRA
 ldy #DHCH
 sty DDRA
 ldy #DHCL
 sty DDRA
 rts

i2c_release_lines:
 ldy #DHCH
 sty DDRA
 rts

i2c_stop:
 ldy #DLCL
 sty DDRA
 ldy #DLCH
 sty DDRA
 ldy #DHCH
 sty DDRA
 rts

i2c_write_byte:
 phx
 ldx #8
writebit:
 rol
 bcs bitset
bitclr:		;MSB = 0
 ldy #DLCL
 sty DDRA
 ldy #DLCH
 sty DDRA
 ldy #DLCL
 sty DDRA
 jmp bitdone
bitset:
 ldy #DHCL
 sty DDRA
 ldy #DHCH
 sty DDRA
 ldy #DHCL
 sty DDRA
bitdone:
 dex
 bne writebit
 ldy #DHCL
 sty DDRA
 ldy #DHCH
 sty DDRA
 ldy #DHCL
 sty DDRA
 clc
 plx
 rts


i2c_start:
 ldy #DLCH
 sty DDRA
 ldy #DLCL
 sty DDRA
 rts


 .org($fffc)
 .word(reset)
 .word($0000)
