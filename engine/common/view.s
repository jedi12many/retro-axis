; =====================================================================
;  ISO64 shared view logic (6502): which map cells can touch the screen,
;  the dirty strips a scroll step exposes, and back-to-front draw order.
;  Needs from the platform: VP_C0 VP_C1 VP_R0 VP_R1 CENTER_COL CENTER_ROW,
;  COLM/ROWM tables, draw_tile, clear_rect.
;
;  With dx/dy relative to the player, k = dx-dy picks the screen column
;  (col = CENTER_COL + 2k) and s = dx+dy the row (row = CENTER_ROW + s).
;  A map cell's tiles span columns col..col+3 and rows row-9..row+1, so it
;  can touch the viewport when k is in KLO..KHI and s in SLO..SHI.
; =====================================================================
KLO = -((CENTER_COL - (VP_C0 - 3)) / 2)     ; ceil((VP_C0-3-CENTER_COL)/2)
KHI = (VP_C1 - CENTER_COL) / 2
SLO = VP_R0 - 1 - CENTER_ROW
SHI = VP_R1 + 9 - CENTER_ROW
YLO = (KHI - SLO) / 2                       ; dy from -YLO ...
YHI = (SHI - KLO) / 2                       ; ... to +YHI

; view_full: the whole viewport is dirty
view_full:
        lda #(64+VP_C0)
        sta dc0b
        lda #(64+VP_C1)
        sta dc1b
        lda #$ff
        sta dr0b
        lda #0
        sta dr1b
        jsr build_masks
        jmp full_bounds

full_bounds:
        lda #<(64+KLO)
        sta klob
        lda #<(64+KHI)
        sta khib
        lda #<(64+SLO)
        sta slob
        lda #<(64+SHI)
        sta shib
        rts

; view_scroll: from the last step (mvdx/mvdy) work out the scroll in cells
; (dcol, drow), the exposed strips, the dirty masks and the scan bounds
view_scroll:
        lda mvdy                  ; dcol = 2*(dy-dx), drow = -(dx+dy)
        sec
        sbc mvdx
        asl
        sta dcol
        lda #0
        sec
        sbc mvdx
        sec
        sbc mvdy
        sta drow

        lda #$ff
        sta dc0b
        sta dr0b
        lda #0
        sta dc1b
        sta dr1b
        lda dcol
        beq @rows
        bmi @cneg
        lda #(64+VP_C0)           ; content moved right: new columns on the left
        sta dc0b
        clc
        adc dcol
        sec
        sbc #1
        sta dc1b
        jmp @rows
@cneg:  lda #(64+VP_C1+1)         ; moved left: new columns on the right
        clc
        adc dcol
        sta dc0b
        lda #(64+VP_C1)
        sta dc1b
@rows:  lda drow
        beq @go
        bmi @rneg
        lda #(64+VP_R0)           ; moved down: new rows at the top
        sta dr0b
        clc
        adc drow
        sec
        sbc #1
        sta dr1b
        jmp @go
@rneg:  lda #(64+VP_R1+1)         ; moved up: new rows at the bottom
        clc
        adc drow
        sta dr0b
        lda #(64+VP_R1)
        sta dr1b
@go:    jsr build_masks
        jsr full_bounds
        lda dr0b                  ; only a column strip: narrow k
        cmp #$ff
        bne @rb
        lda dcol
        bmi @kr
        clc                       ; strip on the left, columns VP_C0..VP_C0+dcol-1:
        adc #<(VP_C0-1-CENTER_COL) ; k <= floor((VP_C0+dcol-1-CENTER_COL)/2)
        cmp #$80
        ror
        clc
        adc #64
        sta khib
        rts
@kr:    clc                       ; strip on the right, VP_C1+1+dcol..VP_C1:
        adc #<(VP_C1-1-CENTER_COL) ; k >= ceil((VP_C1+dcol-2-CENTER_COL)/2)
        cmp #$80
        ror
        clc
        adc #64
        sta klob
        rts
@rb:    lda dc0b                  ; only a row strip: narrow s
        cmp #$ff
        bne @all
        lda drow
        bmi @sb
        clc                       ; rows at the top: s <= drow + VP_R0+8-CENTER_ROW
        adc #<(64+VP_R0+8-CENTER_ROW)
        sta shib
        rts
@sb:    clc                       ; rows at the bottom: s >= drow + VP_R1-CENTER_ROW
        adc #<(64+VP_R1-CENTER_ROW)
        sta slob
@all:   rts

; clear the dirty strips in the hidden frame (platform clear_rect)
clear_dirty:
        lda dc0b
        cmp #$ff
        beq @ch
        sec
        sbc #64
        sta rc0
        lda dc1b
        sec
        sbc #64
        sta rc1
        lda #VP_R0
        sta rr0
        lda #VP_R1
        sta rr1
        jsr clear_rect
@ch:    lda dr0b
        cmp #$ff
        beq @dr
        sec
        sbc #64
        sta rr0
        lda dr1b
        sec
        sbc #64
        sta rr1
        lda #VP_C0
        sta rc0
        lda #VP_C1
        sta rc1
        jsr clear_rect
@dr:    rts

; COLM/ROWM from the dirty strips (entries outside the viewport stay 0)
build_masks:
        ldx #VP_C0
@c:     txa
        clc
        adc #64
        cmp dc0b
        bcc @cn
        cmp dc1b
        beq @cd
        bcs @cn
@cd:    lda #3
        bne @cs
@cn:    lda #1
@cs:    sta COLM,x
        inx
        cpx #(VP_C1+1)
        bne @c
        ldx #VP_R0
@r:     txa
        clc
        adc #64
        cmp dr0b
        bcc @rn
        cmp dr1b
        beq @rd
        bcs @rn
@rd:    lda #3
        bne @rs
@rn:    lda #1
@rs:    sta ROWM,x
        inx
        cpx #(VP_R1+1)
        bne @r
        rts


; ---------------------------------------------------------------------
; draw_all: every map cell whose tiles can touch the dirty region, back
; to front (y outer, x inner). With dx/dy relative to the player, a cell
; can touch the viewport when k = dx-dy is in [-6,6] (columns) and
; s = dx+dy is in [-8,19] (rows, incl. heights). A lone column strip
; narrows k, a lone row strip narrows s (bounds biased +64).
; ---------------------------------------------------------------------
draw_all:
        lda py
        sec
        sbc #YLO
        bcs :+
        lda #0
:       sta ty
        lda py
        clc
        adc #YHI
        cmp #32
        bcc :+
        lda #31
:       sta y1
@yl:    lda ty                    ; x from px + max(dy+klo, slo-dy)
        sec
        sbc py
        sta dyv
        clc
        adc klob
        sta tmp
        lda slob
        sec
        sbc dyv
        cmp tmp
        bcs :+
        lda tmp
:       clc
        adc px
        cmp #64
        bcs :+
        lda #64
:       sta xlob
        lda dyv                   ; to px + min(dy+khi, shi-dy)
        clc
        adc khib
        sta tmp
        lda shib
        sec
        sbc dyv
        cmp tmp
        bcc :+
        lda tmp
:       clc
        adc px
        cmp #96
        bcc :+
        lda #95
:       sta xhib
        cmp xlob
        bcc @next
        lda xlob
        sec
        sbc #64
        sta tx
        lda xhib
        sec
        sbc #64
        sta x1
@xl:    jsr draw_cell
        lda tx
        cmp x1
        beq @next
        inc tx
        jmp @xl
@next:  lda ty
        cmp y1
        beq @done
        inc ty
        jmp @yl
@done:  rts


; ---------------------------------------------------------------------
; draw_cell: one map cell (slabs, terrain top, object) at tx,ty if any of
; its tiles can touch the dirty region
; ---------------------------------------------------------------------
draw_cell:
        lda tx                    ; col = 18 + 2*(dx-dy), row = 8 + dx+dy
        sec
        sbc px
        sta tmp
        lda ty
        sec
        sbc py
        sta tmp2
        lda tmp
        sec
        sbc tmp2
        asl
        clc
        adc #CENTER_COL
        sta bcol
        lda tmp
        clc
        adc tmp2
        clc
        adc #CENTER_ROW
        sta grow

        lda bcol                  ; columns bcol..bcol+3 vs dirty columns
        clc
        adc #(64+3)
        cmp dc0b
        bcc @rowt
        sec
        sbc #3
        cmp dc1b
        bcc @hit
        beq @hit
@rowt:  lda grow                  ; rows grow-9..grow+1 vs dirty rows
        clc                       ; (8-row tile on height 3; exact clip
        adc #(64+1)               ; happens per cell)
        cmp dr0b
        bcc @done
        sec
        sbc #10
        cmp dr1b
        bcc @hit
        bne @done
@hit:   jsr height_at             ; only now touch the map
        sta hgt
        lda idxhi
        clc
        adc #>TERR
        sta mpt+1
        ldy #0
        lda (mpt),y
        beq @obj
        sta tid
        lda #0
        sta lvl
@sl:    lda lvl                   ; cliff slabs under raised terrain
        cmp hgt
        beq @top
        lda grow
        sec
        sbc lvl
        sta trow
        lda M_SLAB
        jsr draw_tile
        inc lvl
        jmp @sl
@top:   lda grow
        sec
        sbc hgt
        sta trow
        lda tid
        jsr draw_tile
@obj:   lda idxhi
        clc
        adc #>OBJ
        sta mpt+1
        ldy #0
        lda (mpt),y
        beq @done
        pha
        lda grow
        sec
        sbc hgt
        sta trow
        pla
        jsr draw_tile
@done:  rts

