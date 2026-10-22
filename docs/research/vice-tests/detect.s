; Reads the bytes ISO64 would use to detect machines and tiers.
; Results at $c000: $d030, $d031, $df00 (REU status), $df1d (UCI id),
; then $d030 after writing 1 (2 MHz on a C128 in C64 mode) and the
; raster ticks of a 100-iteration loop at that speed (CIA2 timer A).
; Build: cl65 -g -t c64 -C c64-asm.cfg -u __EXEHDR__ -Ln detect.lbl -o detect.prg detect.s
        .segment "CODE"
start:  sei
        lda $d030
        sta $c000
        lda $d031
        sta $c001
        lda $df00
        sta $c002
        lda $df1d
        sta $c003
        lda #$0b                  ; blank the screen (no badlines)
        sta $d011
        lda #$ff
        sta $dd04
        sta $dd05
        lda #$11
        sta $dd0e
        jsr loop100
        sta $c004
        lda #1
        sta $d030                 ; 2 MHz on a C128 (ignored on a C64)
        lda $d030
        sta $c005
        jsr loop100
        sta $c006
        lda #0
        sta $d030
done:   jmp done
; time 100 x (dex/bne) = ~500 cycles at 1 MHz; returns low byte of ticks/4
loop100: lda $dd04
        sta t0
        ldx #100
:       dex
        bne :-
        lda t0
        sec
        sbc $dd04
        lsr
        lsr
        rts
        .segment "BSS"
t0:     .res 1
