
; snompiler
; Joe Kennedy 2024

.define VDP_CONTROL_PORT 0xbf
.define VDP_DATA_PORT 0xbe

.define VDP_WRITE_ADDRESS 0x4000
.define VDP_WRITE_CRAM 0xc000
.define VDP_WRITE_REGISTER 0x8000

.MEMORYMAP
	SLOTSIZE $4000
	DEFAULTSLOT 0
	SLOT 0 $0000			; ROM slot 0.
	SLOT 1 $4000			; ROM slot 1.
	SLOT 2 $8000			; ROM slot 2
	SLOT 3 $C000			; RAM
.ENDME

.ROMBANKMAP
	BANKSTOTAL 1
	BANKSIZE $4000
	BANKS 1
.ENDRO

.BANK 0
.SLOT 0

.org 0x0000
	jp init

; used to wait for >= 256 samples 
; preceded by `ld de, nnnn` which uses 10 t-states
; called with rst 0x08 which uses 11 t-states
.org 0x0008

	; get amount of samples to wait into de
	ld e, (hl)
	dec hl
	ld d, (hl)
	dec hl
	jr wait_word_loop

; used when writing one psg update per sample
; falls through to code which waits for < 256 samples
.org 0x0010
    outd					; cycles: 16
	ex (sp), hl				; cycles: 19
	ex (sp), hl				; cycles: 19
	push de					; cycles: 11
	inc de					; cycles: 6
	pop de					; cycles: 10

; used to wait for < 256 samples
; called with rst 0x30 which uses 11 t-states
; the number of samples to wait is in the data, pointed at by hl
; one sample will take 80 t-states, then the rest will all take 81 t-states
.org 0x0018

	; get number of samples to wait from data into b
	; and move data pointer along
	ld b, (hl)
	dec hl

	; djnz if b > 0 and waste another sample's worth of time
	wait_byte_loop:
	djnz wait_byte_time_waste

	; waste more time to round out the sample
	ex (sp), hl				; cycles: 19
	ex (sp), hl				; cycles: 19
	ret						; cycles: 11

; used when writing one psg update per sample
; called with rst 0x18 which uses 11 t-states
; for a total of 81 t-states
.org 0x0020
    outd					; cycles: 16
	ex (sp), hl				; cycles: 19
	ex (sp), hl				; cycles: 19
	dec de					; cycles: 6
	ret						; cycles: 10

; used when writing two psg updates per sample
; called with rst 0x20 which uses 11 t-states
; for a total of 81 t-states
.org 0x0028
	outd				; cycles: 16
	outd				; cycles: 16
	push hl				; cycles: 11
	pop hl				; cycles: 10
	cp a, (hl)			; cycles: 7
	ret					; cycles: 10

; used when writing three psg updates per sample
; called with rst 0x28 which uses 11 t-states
; for a total of 80 t-states
.org 0x0030
	outd				; cycles: 16
	outd				; cycles: 16
	outd				; cycles: 16
	inc (hl)			; cycles: 11	has no effect as data is in rom
	ret					; cycles: 10

; used when writing four psg updates per sample
; called with rst 0x30 which uses 11 t-states
; for a total of 85 t-states
.org 0x0038
	outd				; cycles: 16
	outd				; cycles: 16
	outd				; cycles: 16
	outd				; cycles: 16
	ret                 ; cycles: 10

; this full loop with `ret z` not happening uses 81 cycles
; the first half with the `ret z` happening uses 32 cycles
; added to the cycles for the initial `rst 0x08` call is 32 + 49 = 81 cycles
wait_word_loop:

	cp a, (hl)				; cycles: 7
    dec de					; cycles: 6
    ld a, d					; cycles: 4
    or a, e					; cycles: 4
    ret z					; cycles: 11/5

	bit 0, (hl)				; cycles: 12
	bit 0, (hl)				; cycles: 12
	bit 0, (hl)				; cycles: 12
	cp a, (hl)				; cycles: 7

    jr wait_word_loop		; cycles: 12

; jumped to from the djnz in `rst 0x10` which uses 13 cycles
; for a total of 81 cycles
wait_byte_time_waste:

	ex (sp), hl				; cycles: 19
	ex (sp), hl				; cycles: 19
	cp a, (hl)				; cycles: 7
	cp a, (hl)				; cycles: 7
	nop						; cycles: 4
	jr wait_byte_loop		; cycles 12


.org 0x0066
	retn

.org 0x0080

; preceded by `ld a, n` and `call bank_swap` which use 24 cycles
; which comes to a total of 86 cycles
; a: bank to change to
bank_swap:

    ; change bank in slot 2
    ld (0xffff), a

    ; get start of slot 2 in hl
    ld hl, 0x8000

    ; swap return address with hl
    ex (sp), hl

	; point hl at end of bank where the data starts
	ld hl, 0xbfff

    ; ret jumps to 0x8000
    ret

init:
	di
	im 1

	ld sp, 0xdff0

	; set vdp mode 4
	ld hl, VDP_WRITE_REGISTER | (0 << 8) | 0b00000100
	ld c, VDP_CONTROL_PORT
	out (c), l
	out (c), h

	; disable vdp screens for now
	ld hl, VDP_WRITE_REGISTER | (1 << 8) | 0b10000000
	ld c, VDP_CONTROL_PORT
	out (c), l
	out (c), h
	
	; set vdp nametable base addresses
	ld hl, VDP_WRITE_REGISTER | (2 << 8) | 0xff
	ld c, VDP_CONTROL_PORT
	out (c), l
	out (c), h

	; set sprite table addresses
	ld hl, VDP_WRITE_REGISTER | (5 << 8) | 0xff
	ld c, VDP_CONTROL_PORT
	out (c), l
	out (c), h

	; set sprite tile addresses
	ld hl, VDP_WRITE_REGISTER | (6 << 8) | 0xff
	ld c, VDP_CONTROL_PORT
	out (c), l
	out (c), h

	; clear vram
	ld hl, VDP_WRITE_ADDRESS | 0x0000
	ld c, VDP_CONTROL_PORT
	out (c), l
	out (c), h

	ld c, VDP_DATA_PORT

	ld de, 0x4000
	clear_vram_loop:
		xor a, a
		out (c), a
		dec de
		ld a, d
		or a, e
		jr nz, clear_vram_loop

	; write font to vram
	ld hl, VDP_WRITE_ADDRESS | 0x0400
	ld c, VDP_CONTROL_PORT
	out (c), l
	out (c), h

	ld c, VDP_DATA_PORT

	ld hl, font_bin
	ld de, _sizeof_font_bin
	font_vram_loop:
		ld a, (hl)
		out (c), a
		inc hl
		dec de
		ld a, d
		or a, e
		jr nz, font_vram_loop

	; write palette to cram
	ld hl, VDP_WRITE_CRAM | 0x0000
	ld c, VDP_CONTROL_PORT
	out (c), l
	out (c), h

	ld c, VDP_DATA_PORT

	ld hl, font_palette
	ld b, 16
	font_cram_loop:
		ld a, (hl)
		out (c), a
		inc hl
		djnz font_cram_loop
	

	ld a, 1
	ld b, 1
	call set_vram_write_address

	ld hl, title_string
	call write_string

	ld a, 1
	ld b, 2
	call set_vram_write_address
	call write_string

	; write gd3 strings	
	ld b, 11
	ld hl, 0x4000

	write_gd3_strings_loop:
		push bc
	
		ld a, 15
		sub a, b
		ld b, a

		ld a, 1
		call set_vram_write_address
		call write_string

		pop bc
		djnz write_gd3_strings_loop

	; enable vdp display
	ld hl, VDP_WRITE_REGISTER | (1 << 8) | 0b11000000
	ld c, VDP_CONTROL_PORT
	out (c), l
	out (c), h

	; keep SN output port in c
	ld c, 0x7f

	; point hl at out data 
	ld hl, 0xbfff

	; jump to start of song
    jp 0x8000

; set vdp vram write address
; a: x
; b: y
set_vram_write_address:

	push hl

	; x = x * 2
	add a, a
	ld l, a

	; y = y * 64
	ld a, b
	rrca
	rrca
	ld b, a

	; combine upper bits with l
	and a, 0xc0
	or a, l
	ld l, a

	; isolate correct bits of upper byte
	ld a, b
	and a, 0x3f
	ld h, a

	ld bc, VDP_WRITE_ADDRESS | 0x3800
	add hl, bc

	ld c, VDP_CONTROL_PORT
	out (c), l
	out (c), h

	pop hl

	ret

; write string to vdp
write_string:

	ld c, VDP_DATA_PORT
	write_string_loop:

		; write character
		ld a, (hl)
		out (c), a

		inc hl

		; is it 0? if so we're done
		or a, a
		jr z, write_string_loop_done

		; write empty upper byte
		ld a, 0
		out (c), a
		jr write_string_loop

	write_string_loop_done:
	ret
	
font_bin:
	.incbin "font/plato.bin"
font_palette:
	.incbin "font/plato_pal.bin"
font_palette_end:

title_string:
	.db "snompiler v0.2", 0
	.db "Joe Kennedy 2024", 0

.SMSHEADER
	PRODUCTCODE 26, 70, 2 ; 2.5 bytes
	VERSION 1             ; 0-15
	REGIONCODE 4          ; 3-7
	RESERVEDSPACE 0, 0    ; 2 bytes
	ROMSIZE 0xb           ; 0-15
	CHECKSUMSIZE 32*1024  ; Uses the first this-many bytes in checksum
.ENDSMS