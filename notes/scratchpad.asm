

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
