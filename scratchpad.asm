

; used to wait a variable number of samples
; preceded by `ld de, nnnn` which uses 10 t-states
; called with rst 0x08 which uses 11 t-states
; de: number of samples to wait
;
; currently 84 t-states for 1st sample, 81 t-states for subsequent samples
;
.org 0x006
wait_sample_loop:

	bit 0, (hl)				; cycles: 12

.org 0x0008

    ex (sp), hl				; cycles: 19
	ex (sp), hl				; cycles: 19

	; decrement counter
    dec de                  ; cycles: 6
    ld a, d                 ; cycles: 4
    or a, e                 ; cycles: 4
	ret z					; cycles: 11/5
    jr wait_sample_loop 	; cycles: 12


; one byte's worth of sample wait
rst 0x30
ld b, (hl)
inc hl
loop:
djnz do_loop
ex (sp), hl				; cycles: 19
ex (sp), hl				; cycles: 19
ret

do_loop:
	ex (sp), hl				; cycles: 19
	ex (sp), hl				; cycles: 19
	cp a, (hl)				; cycles: 7
	cp a, (hl)				; cycles: 7
	nop						; cycles: 4
	jr loop


; two byte's worth of sample wait
rst 0x08
ld e, (hl)
inc hl
ld d, (hl)
inc hl
jr wait_word_loop


wait_word_loop:
    dec de
    ld a, d
    or a, e
    cp a, (hl)
    ret z
	ex (sp), hl				; cycles: 19
	ex (sp), hl				; cycles: 19
    nop                     ; cycles: 4
    jr wait_word_loop