; =====================================================================
;  ISO64 shared game rules (6502). Included by every 6502 platform.
;  Needs from the platform: MAP/TILES (+ common/defs.inc), common/zp.inc,
;  plat_flash (hit feedback).
; =====================================================================

; ---------------------------------------------------------------------
; key_step: A = PETSCII key. If it is a movement key: carry set and
; nx/ny = the target square. Screen directions:
;   W / cursor up      up         Q  up-left      E  up-right
;   S / cursor down    down       Z  down-left    C  down-right
;   A / cursor left    left
;   D / cursor right   right
; ---------------------------------------------------------------------
key_step:
        ldx #(keydx-keys-1)
@kl:    cmp keys,x
        beq @key
        dex
        bpl @kl
        clc
        rts
@key:   lda px
        clc
        adc keydx,x
        sta nx
        lda py
        clc
        adc keydy,x
        sta ny
        sec
        rts

; ---------------------------------------------------------------------
; try_move: attempt to step to nx,ny.
; Returns A = 0 nothing happened, 1 moved (mvdx/mvdy set), 2 bumped
; ---------------------------------------------------------------------
try_move:
        lda nx
        cmp #32
        bcs @no
        lda ny
        cmp #32
        bcs @no
        lda nx
        sta tx
        lda ny
        sta ty
        jsr tile_blocked
        bcs @no
        jsr height_at
        sta tmp2
        lda px
        sta tx
        lda py
        sta ty
        jsr height_at
        sec
        sbc tmp2                  ; climb at most one level
        clc
        adc #1
        cmp #3
        bcs @no
        jsr entity_at
        bcc @move
        jsr bump
        lda #2
        rts
@move:  lda nx
        sec
        sbc px
        sta mvdx
        lda ny
        sec
        sbc py
        sta mvdy
        lda nx
        sta px
        lda ny
        sta py
        lda #1
        rts
@no:    lda #0
        rts


; tx,ty -> idxlo/idxhi (offset into a 32x32 plane)
calc_idx:
        lda ty
        lsr
        lsr
        lsr
        sta idxhi
        lda ty
        asl
        asl
        asl
        asl
        asl
        ora tx
        sta idxlo
        rts

; tx,ty -> A = height 0-3, mpt -> height byte
height_at:
        jsr calc_idx
        lda idxlo
        sta mpt
        lda idxhi
        clc
        adc #>HGT
        sta mpt+1
        ldy #0
        lda (mpt),y
        and #3
        rts


; tx,ty -> carry set if blocked (flag bit, void, or blocking tile)
tile_blocked:
        jsr height_at
        lda (mpt),y
        bmi @yes
        lda idxhi
        clc
        adc #>TERR
        sta mpt+1
        lda (mpt),y
        beq @yes
        jsr tile_flags
        and #1
        bne @yes
        lda idxhi
        clc
        adc #>OBJ
        sta mpt+1
        ldy #0
        lda (mpt),y
        beq @no
        jsr tile_flags
        and #1
        bne @yes
@no:    clc
        rts
@yes:   sec
        rts

; A = tile id -> A = tile flags
tile_flags:
        asl
        tay
        lda TILES+1,y
        sta mp
        lda TILES+2,y
        sta mp+1
        ldy #1
        lda (mp),y
        ldy #0
        rts

; nx,ny -> carry set + Y = record offset if a solid entity is there
entity_at:
        ldx M_NENT
        beq @none
        ldy #0
@l:     lda ENTS+E_TYPE,y
        beq @n
        cmp #ET_TRIGGER
        beq @n
        lda ENTS+E_X,y
        cmp nx
        bne @n
        lda ENTS+E_Y,y
        cmp ny
        bne @n
        sec
        rts
@n:     tya
        clc
        adc #8
        tay
        dex
        bne @l
@none:  clc
        rts

; bump: stand-in for the combat system. Monsters lose 1 hp per bump and
; vanish at 0; items are picked up; NPCs just block.
bump:
        lda ENTS+E_TYPE,y
        cmp #ET_ITEM
        beq @kill
        cmp #ET_MONSTER
        bne @out
        lda ENTS+E_HP,y
        beq @kill
        sec
        sbc #1
        sta ENTS+E_HP,y
        bne @flash
@kill:  lda #0
        sta ENTS+E_TYPE,y
@flash: jmp plat_flash          ; platform hit feedback
@out:   rts


; key -> map step. Screen up = (-1,-1), down = (+1,+1),
; left = (-1,+1), right = (+1,-1); Q/E/Z/C step along one map axis.
;          W   up   S   down A   left D   right Q   E   Z   C
keys:   .byte $57,$91,$53,$11,$41,$9d,$44,$1d,$51,$45,$5a,$43
keydx:  .byte $ff,$ff,$01,$01,$ff,$ff,$01,$01,$ff,$00,$00,$01
keydy:  .byte $ff,$ff,$01,$01,$01,$01,$ff,$ff,$00,$ff,$01,$00
