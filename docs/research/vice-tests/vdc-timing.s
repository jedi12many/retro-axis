; VDC 8563/8568 timing probe (C128 mode). Research only, not engine code.
; Build: cl65 -g -t c128 -C c128-asm.cfg -u __EXEHDR__ -Ln vdc.lbl -o vdc-timing.prg vdc-timing.s
; Run:   x128 -80col -moncommands mon.txt -autostart vdc-timing.prg
;        (mon.txt: break at "done", bsave $1300-$133f)
;
; CIA2 timer A counts 1 MHz PHI2 ticks even when the 8502 runs at 2 MHz,
; so every result is real time in microseconds. The empty-test overhead
; (test 0) has to be subtracted. Results: 2 bytes per test at $1300,
; $1320 = 1 if 64 KB VDC RAM answered.

VDCA  = $d600
VDCD  = $d601
N     = 1000

        .segment "CODE"
start:  sei
        lda #$7f
        sta $dc0d
        sta $dd0d
        lda #$ff
        sta $dd04
        sta $dd05
        lda #$11
        sta $dd0e
        jsr det64
        ldy #0
@loop:  sty tno
        lda #0                    ; 1 MHz unless the test says otherwise
        sta $d030
        lda #0                    ; VDC address 0 for every test
        ldx #18
        jsr wreg
        ldx #19
        jsr wreg
        lda $dd04
        ldx $dd05
        sta t0
        stx t0+1
        ldy tno
        lda tlo,y
        sta jv
        lda thi,y
        sta jv+1
        jsr jvec
        lda $dd04
        ldx $dd05
        sta t1
        stx t1+1
        lda #0
        sta $d030
        lda tno
        asl
        tax
        lda t0
        sec
        sbc t1
        sta $1300,x
        lda t0+1
        sbc t1+1
        sta $1301,x
        ldy tno
        iny
        cpy #NT
        bne @loop
done:   inc $d020
        jmp done

jvec:   jmp (jv)

; write A to VDC register X
wreg:   stx VDCA
:       bit VDCA
        bpl :-
        sta VDCD
        rts
; read VDC register X into A
rreg:   stx VDCA
:       bit VDCA
        bpl :-
        lda VDCD
        rts

; 64 KB check: reg 28 bit 4 = 1 (4164 DRAM layout), write $00 at $0000
; and $55 at $8000, read $0000 back. A 16 KB VDC aliases them.
det64:  ldx #28
        jsr rreg
        ora #$10
        jsr wreg
        lda #$00
        jsr setad0
        lda #$00
        ldx #31
        jsr wreg
        lda #$80
        jsr setad0
        lda #$55
        ldx #31
        jsr wreg
        lda #$00
        jsr setad0
        ldx #31
        jsr rreg
        ldy #0
        cmp #$00
        bne :+
        iny
:       sty $1320
        rts
setad0: ldx #18                   ; address A*256
        jsr wreg
        lda #0
        ldx #19
        jmp wreg

; tests ---------------------------------------------------------------
t_none: rts

; CPU writes N bytes through register 31 (address auto-increments)
t_wr1:  ldx #31
        stx VDCA
        ldy #>N
        ldx #<N
@b:     bit VDCA
        bpl @b
        stx VDCD
        dex
        bne @b
        dey
        bpl @b
        rts
t_wr2:  lda #1                    ; same at 2 MHz
        sta $d030
        jmp t_wr1

; CPU reads N bytes through register 31
t_rd1:  ldx #31
        stx VDCA
        ldy #>N
        ldx #<N
@b:     bit VDCA
        bpl @b
        lda VDCD
        dex
        bne @b
        dey
        bpl @b
        rts

; block fill: 1 byte written, then 4 x 250 more by register 30
t_fill: ldx #24
        jsr rreg
        and #$7f                  ; bit 7 = 0: fill
        jsr wreg
        lda #$aa
        ldx #31
        jsr wreg
        ldy #4
@f:     lda #250
        ldx #30
        jsr wreg
        dey
        bne @f
        ldx #31                   ; wait until the last fill is done
        stx VDCA
:       bit VDCA
        bpl :-
        rts

; block copy: 4 x 250 bytes from VDC $4000 to the address in 18/19
t_copy: ldx #24
        jsr rreg
        ora #$80                  ; bit 7 = 1: copy
        jsr wreg
        lda #$40
        ldx #32
        jsr wreg
        lda #$00
        ldx #33
        jsr wreg
        ldy #4
@c:     lda #250
        ldx #30
        jsr wreg
        dey
        bne @c
        ldx #31
        stx VDCA
:       bit VDCA
        bpl :-
        ldx #24                   ; back to fill mode
        jsr rreg
        and #$7f
        jmp wreg

; same block fill with the CPU at 2 MHz (the VDC sets the pace)
t_fill2: lda #1
        sta $d030
        jmp t_fill

; 0 overhead | 1 write 1 MHz | 2 write 2 MHz | 3 read 1 MHz
; 4 fill 1000 | 5 copy 1000 | 6 fill at 2 MHz
NT = 7
tlo:    .byte <t_none, <t_wr1, <t_wr2, <t_rd1, <t_fill, <t_copy, <t_fill2
thi:    .byte >t_none, >t_wr1, >t_wr2, >t_rd1, >t_fill, >t_copy, >t_fill2

        .segment "BSS"
tno:    .res 1
t0:     .res 2
t1:     .res 2
jv:     .res 2
