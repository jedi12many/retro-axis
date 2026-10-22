; REU DMA timing probe (C64 + REU). Research only, not engine code.
; Build: cl65 -t c64 -C c64-asm.cfg -u __EXEHDR__ -o reu-timing.prg reu-timing.s
; Run:   x64sc -reu -reusize 512 -limitcycles 4000000 -exitscreenshot out.png reu-timing.prg
;
; Each test is timed with CIA2 timer A (free running, 1 tick = 1 PHI2
; cycle). The empty-test overhead is subtracted. Results are printed as
; hex cycle counts, one per screen row, and copied to $c000 (2 bytes each).

REU   = $df00
N     = 1000              ; bytes per transfer
DST   = $4000

        .segment "CODE"
start:  sei
        lda #$7f
        sta $dc0d
        sta $dd0d
        lda #$ff                  ; timer A: free running, max latch
        sta $dd04
        sta $dd05
        lda #$11
        sta $dd0e
        ; fill $4000.. with a pattern, stash it once so verify can pass
        ldx #0
:       txa
        sta DST,x
        sta DST+$100,x
        sta DST+$200,x
        sta DST+$300,x
        inx
        bne :-
        ldx #14                   ; sprites at y = 60, x = 24 + 24*n
:       lda #60
        sta $d001,x
        txa
        asl
        asl
        adc #24
        sta $d000,x
        dex
        dex
        bpl :-
        ldy #0                    ; test number
@loop:  sty tno
        jsr setup
        ldy tno
        lda pre011,y              ; screen on/off, sprites on/off
        sta $d011
        lda pre015,y
        sta $d015
@w2:    lda $d011                 ; wait for raster line 60 (inside the
        bmi @w2                   ; display window, so badlines and sprite
@w1:    lda $d012                 ; DMA hit the screen-on tests) so the
        cmp #60                   ; start point is the same for every test
        bne @w1
        lda $dd04                 ; t0 (lo first; hi re-read below)
        ldx $dd05
        sta t0
        stx t0+1
        ldy tno
        lda cmd,y
        beq :+                    ; 0 = overhead test: no DMA
        sta REU+1                 ; execute immediately (no $ff00 trigger)
:       lda $dd04
        ldx $dd05
        sta t1
        stx t1+1
        ; elapsed = t0 - t1 (timer counts down)
        lda t0
        sec
        sbc t1
        sta el
        lda t0+1
        sbc t1+1
        sta el+1
        lda tno
        asl
        tax
        lda el
        sta $c000,x
        lda el+1
        sta $c001,x
        lda REU                   ; status (bit 5 = verify fault)
        sta $c040,x
        jsr print
        ldy tno
        iny
        cpy #NT
        bne @loop
        lda #$1b
        sta $d011
done:   inc $d020
        jmp done

setup:  lda #<DST                 ; C64 address
        sta REU+2
        lda #>DST
        sta REU+3
        lda #0                    ; REU address $000000
        sta REU+4
        sta REU+5
        sta REU+6
        lda #<N
        sta REU+7
        lda #>N
        sta REU+8
        ldy tno
        lda fix,y
        sta REU+10
        lda REU                   ; clear status
        rts

; print el as 4 hex digits plus the test label at row tno
print:  lda tno
        tax
        lda rowlo,x
        sta $fb
        lda rowhi,x
        sta $fc
        ldy #0
        lda el+1
        jsr hex2
        lda el
        jsr hex2
        rts
hex2:   pha
        lsr
        lsr
        lsr
        lsr
        jsr hex1
        pla
        and #$0f
hex1:   tax
        lda hexd,x
        sta ($fb),y
        iny
        rts

hexd:   .byte $30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$01,$02,$03,$04,$05,$06
rowlo:  .repeat 16, I
        .byte <($0400+I*40)
        .endrepeat
rowhi:  .repeat 16, I
        .byte >($0400+I*40)
        .endrepeat

; tests: 0 overhead | 1 stash | 2 fetch | 3 swap | 4 verify (equal)
;        5 fetch, C64 address fixed (fill) | 6 fetch, REU address fixed
;        7 fetch with screen on | 8 fetch, screen on + 8 sprites
NT = 9
cmd:    .byte $00, $90, $91, $92, $93, $91, $91, $91, $91
fix:    .byte $00, $00, $00, $00, $00, $80, $40, $00, $00
pre011: .byte $0b, $0b, $0b, $0b, $0b, $0b, $0b, $1b, $1b
pre015: .byte $00, $00, $00, $00, $00, $00, $00, $00, $ff

        .segment "BSS"
tno:    .res 1
t0:     .res 2
t1:     .res 2
el:     .res 2
