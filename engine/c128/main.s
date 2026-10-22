; =====================================================================
;  ISO64 engine - C128 80-column platform layer (VDC bitmap, 64 KB VDC
;  RAM, 2 MHz). Shared logic in ../common
;
;  The VDC shows a 640x200 bitmap with attributes: each 8x8 cell has a
;  foreground (attribute bits 0-3) and a background colour (bits 4-7). The viewport is 62x25 cells (the
;  same 4x2-cell diamonds as the C64), with a side panel in columns 62-79.
;
;  VDC RAM holds three full frames: A and B (double buffered display) and
;  C, the clean frame: the map picture without figures. A step:
;    1. view_scroll / draw_all compose only the newly exposed strips, in
;       C128 RAM (the VIC-20's compose code; cells outside the strips are
;       never read, so nothing has to be scroll-copied in RAM)
;    2. hidden frame <- C shifted by the scroll, by VDC block copies
;    3. the strips go up into the hidden frame through $d600/$d601
;    4. C <- hidden frame (one block copy): the clean frame for next step
;    5. figures (soft sprites) are read, masked and written back, back to
;       front, in the hidden frame only
;    6. flip in vertical blank: display start R12/R13 and attribute start
;       R20/R21 switch to the hidden frame
;  Nothing ever writes to the frame on show.
;
;  Data files (from the browser editor, loaded from sd2iec):
;    CTILES   -> $9800   VDC tiles
;    CSPRITES -> $9100   pre-shifted figures, colour table, panel font
;    MAP01    -> $4c00   the shared map file
;  Layout: docs/PLATFORMS.md section 7.
; =====================================================================

; ---- VDC RAM (64 KB: R28 bit 4 set) -----------------------------------
BM_A      = $0000          ; frame A: bitmap 80 x 200 lines
AT_A      = $3e80          ;          attributes 80 x 25
BM_B      = $4800          ; frame B
AT_B      = $8680
BM_C      = $9000          ; clean frame (no figures)
AT_C      = $ce80
FRAME_LEN = 18000          ; bitmap + attributes, contiguous in every frame

; ---- C128 RAM (bank 0) ------------------------------------------------
COLM      = $4000          ; per column: bit0 in viewport, bit1 dirty
ROWM      = $4100          ; per row:    bit0 in viewport, bit1 dirty
COL4      = $4200          ; per tile column bcol: on screen (bits 0-3), dirty (4-7)
VISLIST   = $4300          ; visible entities, depth sorted (record offsets)
VISD      = $4320          ; ... and their depth
LB        = $4340          ; one figure line (4 bytes)
PBUF      = $4348          ; position text
MAP       = $4c00
CB        = $5a00          ; compose bitmap: 62x25 cells x 8 bytes
CC        = $8a80          ; compose attributes: 62x25
CSPR      = $9100          ; figures: s*256 + cell*16 = 8 bitmap + 8 mask
CSPR_F    = $9500          ; s*16 + cell: bit 0 body pixels, bit 1 any pixels
C2R       = $9540          ; C64 colour -> RGBI colour
FONT      = $9600          ; panel font, ASCII 32-95
TILES     = $9800

.include "../common/defs.inc"

M_C128A   = MAP+$0e        ; background of empty cells << 4 | border
M_C128P   = MAP+$0f        ; panel attribute: background << 4 | text
M_NAME    = MAP+$10

; ---- viewport -----------------------------------------------------------
VP_C0      = 0
VP_C1      = 61
VP_R0      = 0
VP_R1      = 24
VP_ROWS    = VP_R1-VP_R0+1
VP_COLS    = VP_C1-VP_C0+1
CENTER_COL = 29
CENTER_ROW = 11
PANEL_COL  = 62
TEXT_COL   = 64
SEP_BYTE   = $40           ; separator line in column 62

VDC_A     = $d600          ; register select / status (7 ready, 5 vblank)
VDC_D     = $d601
MMU_CR    = $ff00
CR_RAM0   = $0e            ; RAM 0 to $bfff, I/O, KERNAL ROM

SETBNK = $ff68
SETLFS = $ffba
SETNAM = $ffbd
LOAD   = $ffd5
GETIN  = $ffe4
SCNKEY = $ff9f
NDX    = $d0               ; keyboard queue length
CINV   = $0314             ; IRQ vector
IRQ_RET = $ff33            ; KERNAL: restore MMU and registers, RTI

.include "../common/zp.inc"

; C128 only ($60-$8f)
vd     = $60               ; VDC address (update / copy destination)
vs     = $62               ; VDC copy source
vn     = $64               ; byte count
hbm    = $66               ; hi byte of the hidden frame's bitmap
hath   = $67               ; hi byte of its attributes (lo byte $80)
r24v   = $68               ; R24 with the copy bit clear
clra   = $69               ; attribute of an empty cell
spx    = $6a               ; figure: left cell column of its 4x4 block
spy    = $6b               ;         top cell row
sid    = $6c
sfg    = $6d               ;         colour
nvis   = $6e
fca    = $6f               ; figure: visible block columns fca..fcb
fcb    = $70
fra    = $71               ;         visible block rows fra..frb
frb    = $72
fnc    = $73               ; bytes per run
fln    = $74               ; line 0-7 in a cell row
fro    = $75
fcell  = $76
tp     = $77               ; text pointer
fp     = $79               ; figure data
bc16   = $7b               ; draw_tile: CB + bcol*8 - 2
rcb    = $7d               ; draw_tile: CC + bcol
rcp    = $7f
dco    = $81               ; shift_copy: destination / source column, row
sco    = $82
dro    = $83
sro    = $84
nrow   = $85
ucnt   = $86
tbh    = $87               ; put_text: frame bitmap hi byte

; ---- VDC access -----------------------------------------------------------
.macro VWAIT                      ; until the VDC is ready
:       bit VDC_A
        bpl :-
.endmacro
.macro VPUT reg                   ; register reg = A (X destroyed)
        ldx #reg
        stx VDC_A
:       bit VDC_A
        bpl :-
        sta VDC_D
.endmacro
.macro VGET reg                   ; A = register reg
        ldx #reg
        stx VDC_A
:       bit VDC_A
        bpl :-
        lda VDC_D
.endmacro

.segment "CODE"

start:
        lda #CR_RAM0
        sta MMU_CR
        lda #$0b                  ; VIC-II display off (it breaks up at 2 MHz)
        sta $d011
        lda #1                    ; 2 MHz
        sta $d030

        lda #fn_ct_len
        ldx #<fn_ct
        ldy #>fn_ct
        jsr load_file
        lda #fn_cs_len
        ldx #<fn_cs
        ldy #>fn_cs
        jsr load_file
        lda #fn_map_len
        ldx #<fn_map
        ldy #>fn_map
        jsr load_file

        sei                       ; own IRQ: keyboard scan only
        lda #<irq
        sta CINV
        lda #>irq
        sta CINV+1
        cli

        ldx #8                    ; position text template
@pt:    lda t_pos,x
        sta PBUF,x
        dex
        bpl @pt
        ldx #0                    ; COLM, ROWM, COL4
        txa
@z:     sta COLM,x
        sta ROWM,x
        sta COL4,x
        inx
        bne @z
        jsr vdc_init
        jsr clean_init
        jsr prep_tiles
        lda #0                    ; frame A on show, B hidden
        sta front
        lda #>BM_B
        sta hbm
        lda #>AT_B
        sta hath
        lda M_STARTX
        sta px
        lda M_STARTY
        sta py
        jsr render_full
        jsr flip

main_loop:
        jsr get_move              ; A: 0 nothing, 1 moved, 2 bumped
        beq main_loop
        cmp #1
        bne @bump
        jsr render_scroll
        jsr flip
        jmp main_loop
@bump:  jsr render_same           ; same map picture, new figures
        jsr flip
        jmp main_loop

irq:    lda $d019                 ; acknowledge VIC and CIA interrupts
        sta $d019
        lda $dc0d
        jsr SCNKEY
        jmp IRQ_RET

; ---------------------------------------------------------------------
; load_file: A = name length, X/Y = name. Loads to the file's own address
; in RAM bank 0 from the current device (default 8). Flashes if missing.
load_file:
        jsr SETNAM
        lda #0
        tax
        jsr SETBNK
        ldx $ba
        cpx #8
        bcs :+
        ldx #8
:       lda #1
        ldy #1
        jsr SETLFS
        lda #0
        jsr LOAD
        bcs load_err
        rts
load_err:
        inc tmp
        lda tmp
        VPUT 26
        jmp load_err

; ---------------------------------------------------------------------
; vdc_init: 64 KB mode, all VDC RAM cleared, bitmap mode with attributes
vdc_init:
        VGET 28                   ; 64 KB of VDC RAM
        ora #$10
        VPUT 28
        VGET 24
        and #$7f
        sta r24v
        lda #0                    ; clear $0000-$fffe
        sta vd
        sta vd+1
        lda #$ff
        sta vn
        sta vn+1
        lda #0
        jsr vfill
        lda #>BM_A                ; show frame A
        VPUT 12
        lda #<BM_A
        VPUT 13
        lda #>AT_A
        VPUT 20
        lda #<AT_A
        VPUT 21
        VGET 25                   ; bitmap mode, attributes on
        and #$0f
        ora #$c0
        VPUT 25
        lda M_C128A               ; border
        and #$0f
        VPUT 26
        rts

; clean_init: frame C = empty viewport + side panel, copied to A and B
clean_init:
        lda M_C128A
        and #$f0
        sta clra
        lda #<AT_C
        sta vd
        lda #>AT_C
        sta vd+1
        lda #25
        sta nrow
@at:    lda #VP_COLS              ; viewport cells: empty
        sta vn
        lda #0
        sta vn+1
        lda clra
        jsr vfill
        lda vd
        clc
        adc #VP_COLS
        sta vd
        bcc :+
        inc vd+1
:       lda #(80-PANEL_COL)       ; panel cells
        sta vn
        lda #0
        sta vn+1
        lda M_C128P
        jsr vfill
        lda vd
        clc
        adc #(80-PANEL_COL)
        sta vd
        bcc :+
        inc vd+1
:       dec nrow
        bne @at
        lda #<(BM_C+PANEL_COL)    ; separator line
        sta vd
        lda #>(BM_C+PANEL_COL)
        sta vd+1
        lda #200
        sta nrow
@sep:   jsr vdc_ua
        lda #SEP_BYTE
        VWAIT
        sta VDC_D
        lda vd
        clc
        adc #80
        sta vd
        bcc @sn
        inc vd+1
@sn:    dec nrow
        bne @sep
        lda #>BM_C
        sta tbh
        ldx #0                    ; static text
@tx:    stx nrow
        lda ptext+3,x
        sta tp
        lda ptext+4,x
        sta tp+1
        ldy ptext+1,x             ; row
        lda ptext+2,x             ; length
        pha
        lda ptext,x               ; column
        tax
        pla
        jsr put_text
        lda nrow
        clc
        adc #5
        tax
        cpx #ptext_len
        bne @tx
        lda #<M_NAME              ; map name
        sta tp
        lda #>M_NAME
        sta tp+1
        ldx #TEXT_COL
        ldy #4
        lda #16
        jsr put_text
        lda #>BM_A                ; A and B start as copies of C
        jsr frame_from_clean
        lda #>BM_B
        ; fall through

; frame_from_clean: frame at hi byte A <- C (bitmap and attributes)
frame_from_clean:
        sta vd+1
        lda #0
        sta vd
        sta vs
        lda #>BM_C
        sta vs+1
        lda #<FRAME_LEN
        sta vn
        lda #>FRAME_LEN
        sta vn+1
        jmp lin_copy

; ---------------------------------------------------------------------
; vdc_ua: update address = vd, then select the data register R31
vdc_ua:
        lda vd+1
        VPUT 18
        lda vd
        VPUT 19
        ldx #31
        stx VDC_A
        rts

; lin_copy: VDC block copy of vn bytes (1-65535) from vs to vd
lin_copy:
        lda r24v
        ora #$80
        VPUT 24
        lda vd+1
        VPUT 18
        lda vd
        VPUT 19
        lda vs+1
        VPUT 32
        lda vs
        VPUT 33
@l:     lda vn+1
        beq @last
        lda #0                    ; 256 bytes
        VPUT 30
        dec vn+1
        jmp @l
@last:  lda vn
        beq @done
        VPUT 30
@done:  rts

; vfill: VDC block fill of vn bytes (1-65535) at vd with A
vfill:  pha
        lda r24v
        VPUT 24
        lda vd+1
        VPUT 18
        lda vd
        VPUT 19
        pla
        VPUT 31                   ; the first byte
        lda vn
        sec
        sbc #1
        sta vn
        bcs @l
        dec vn+1
@l:     lda vn+1
        beq @last
        lda #0
        VPUT 30
        dec vn+1
        jmp @l
@last:  lda vn
        beq @done
        VPUT 30
@done:  rts

; put_text: A = length, X = column, Y = row, tp = ASCII text, into the
; bitmap of the frame whose hi byte is tbh
put_text:
        sta fnc
        txa
        clc
        adc r640lo,y
        sta vd
        lda r640hi,y
        adc tbh
        sta vd+1
        lda #0
        sta fln
@line:  jsr vdc_ua
        ldy #0
@ch:    lda (tp),y                ; glyph = ASCII - 32 (others: space)
        sec
        sbc #32
        bcc @sp
        cmp #64
        bcc @ok
@sp:    lda #0
@ok:    asl                       ; *8 + line (carry: second page)
        asl
        asl
        ora fln
        tax
        bcs @hi
        lda FONT,x
        jmp @put
@hi:    lda FONT+256,x
@put:   VWAIT
        sta VDC_D
        iny
        cpy fnc
        bne @ch
        lda vd
        clc
        adc #80
        sta vd
        bcc @nl
        inc vd+1
@nl:    inc fln
        lda fln
        cmp #8
        bne @line
        rts

; panel_pos: "POS xx,yy" into the hidden frame
panel_pos:
        lda px
        ldy #4
        jsr dec2
        lda py
        ldy #7
        jsr dec2
        lda #<PBUF
        sta tp
        lda #>PBUF
        sta tp+1
        lda hbm
        sta tbh
        ldx #TEXT_COL
        ldy #6
        lda #9
        jmp put_text
; A = 0-99 -> two digits at PBUF+Y
dec2:   ldx #$30
@t:     cmp #10
        bcc @u
        sbc #10
        inx
        bne @t
@u:     ora #$30
        sta PBUF+1,y
        txa
        sta PBUF,y
        rts

; ---------------------------------------------------------------------
render_full:
        jsr view_full
        jsr full_rect
        jsr clear_rect
        jsr build_col4
        jsr draw_all
        jsr render_same_map       ; hidden <- C (panel)
        jsr full_rect
        jsr upload_rect
        jmp finish_frame

render_scroll:
        jsr view_scroll
        jsr build_col4
        jsr clear_dirty
        jsr draw_all
        jsr shift_copy
        jsr upload_dirty
finish_frame:
        jsr panel_pos
        lda #>BM_C                ; C <- hidden: the clean frame
        sta vd+1
        lda hbm
        sta vs+1
        lda #0
        sta vd
        sta vs
        lda #<FRAME_LEN
        sta vn
        lda #>FRAME_LEN
        sta vn+1
        jsr lin_copy
        jmp figures

render_same:
        jsr render_same_map
        jmp figures
render_same_map:
        lda hbm
        jmp frame_from_clean

full_rect:
        lda #VP_C0
        sta rc0
        lda #VP_C1
        sta rc1
        lda #VP_R0
        sta rr0
        lda #VP_R1
        sta rr1
        rts

; rect_ptrs: X = row -> bp = compose bitmap of cell (rc0, row),
; clp = its attribute
rect_ptrs:
        lda rc0
        sta tmp
        lda #0
        sta tmp2
        asl tmp
        rol tmp2
        asl tmp
        rol tmp2
        asl tmp
        rol tmp2
        lda cbrowlo,x
        clc
        adc tmp
        sta bp
        lda cbrowhi,x
        adc tmp2
        sta bp+1
        lda bp
        clc
        adc #<CB
        sta bp
        lda bp+1
        adc #>CB
        sta bp+1
        lda rowwlo,x
        clc
        adc rc0
        sta clp
        lda rowwhi,x
        adc #0
        sta clp+1
        lda clp
        clc
        adc #<CC
        sta clp
        lda clp+1
        adc #>CC
        sta clp+1
        rts

; clear cells rc0..rc1 x rr0..rr1 of the compose buffer (bitmap 0,
; attribute of an empty cell)
clear_rect:
        lda rc1
        sec
        sbc rc0
        sta ncell                 ; cells - 1
        lda rr0
        sta crow
@r:     ldx crow
        jsr rect_ptrs
        ldy ncell
        lda clra
@a:     sta (clp),y
        dey
        bpl @a
        ldx ncell
@c:     lda #0
        ldy #7
@b:     sta (bp),y
        dey
        bpl @b
        lda bp
        clc
        adc #8
        sta bp
        bcc :+
        inc bp+1
:       dex
        bpl @c
        lda crow
        cmp rr1
        beq @done
        inc crow
        jmp @r
@done:  rts

; upload_rect: compose cells rc0..rc1 x rr0..rr1 -> hidden frame
upload_rect:
        lda rc1
        sec
        sbc rc0
        clc
        adc #1
        sta ucnt
        lda rr0
        sta crow
@r:     ldx crow
        jsr rect_ptrs
        lda r640lo,x              ; vd = bitmap of (rc0, row), line 0
        clc
        adc rc0
        sta vd
        lda r640hi,x
        adc hbm
        sta vd+1
        lda #0
        sta fln
@ln:    jsr vdc_ua
        lda bp+1
        pha
        ldy fln
        ldx ucnt
@b:     lda (bp),y                ; byte fln of each cell
        VWAIT
        sta VDC_D
        tya
        clc
        adc #8
        tay
        bcc @bn
        inc bp+1
@bn:    dex
        bne @b
        pla
        sta bp+1
        lda vd
        clc
        adc #80
        sta vd
        bcc @vn
        inc vd+1
@vn:    inc fln
        lda fln
        cmp #8
        bne @ln
        ldx crow                  ; attributes
        lda r80lo,x
        clc
        adc #<AT_A
        sta vd
        lda r80hi,x
        adc hath
        sta vd+1
        lda vd
        clc
        adc rc0
        sta vd
        bcc :+
        inc vd+1
:       jsr vdc_ua
        ldy #0
@at:    lda (clp),y
        VWAIT
        sta VDC_D
        iny
        cpy ucnt
        bne @at
        lda crow
        cmp rr1
        beq @done
        inc crow
        jmp @r
@done:  rts

; upload_dirty: the dirty strips of view_scroll -> hidden frame
upload_dirty:
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
        jsr upload_rect
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
        jsr upload_rect
@dr:    rts

; ---------------------------------------------------------------------
; shift_copy: hidden frame <- C shifted by dcol/drow cells (the part of
; the viewport that is still on screen): one copy per line and per
; attribute row, so the side panel stays where it is.
shift_copy:
        lda dcol
        bmi @cn
        sta dco
        lda #0
        sta sco
        beq @cl
@cn:    lda #0
        sta dco
        sec
        sbc dcol
        sta sco
@cl:    lda drow
        bmi @rn
        sta dro
        lda #0
        sta sro
        beq @rl
@rn:    lda #0
        sta dro
        sec
        sbc drow
        sta sro
@rl:    lda #VP_ROWS
        sec
        sbc dro
        sec
        sbc sro
        sta nrow
        lda #VP_COLS              ; bytes per line
        sec
        sbc dco
        sec
        sbc sco
        sta vn
        lda r24v
        ora #$80
        VPUT 24
        ldx dro                   ; vd = hidden (dco, dro), vs = C (sco, sro)
        lda r640lo,x
        clc
        adc dco
        sta vd
        lda r640hi,x
        adc hbm
        sta vd+1
        ldx sro
        lda r640lo,x
        clc
        adc sco
        sta vs
        lda r640hi,x
        adc #>BM_C
        sta vs+1
        lda nrow                  ; nrow*8 lines
        asl
        asl
        asl
        sta ucnt
@ln:    jsr copy_run
        jsr next_line
        dec ucnt
        bne @ln
        jsr shift_attr_ptrs
        lda vd
        clc
        adc dco
        sta vd
        bcc :+
        inc vd+1
:       lda vs
        clc
        adc sco
        sta vs
        bcc :+
        inc vs+1
:
@ar:    jsr copy_run
        jsr next_line
        dec nrow
        bne @ar
        rts

; vd = hidden attributes of row dro, vs = C's of row sro
shift_attr_ptrs:
        ldx dro
        lda r80lo,x
        clc
        adc #<AT_A
        sta vd
        lda r80hi,x
        adc hath
        sta vd+1
        ldx sro
        lda r80lo,x
        clc
        adc #<AT_C
        sta vs
        lda r80hi,x
        adc #>AT_C
        sta vs+1
        rts

; copy_run: one block copy of vn (1-255) bytes vs -> vd (R24 in copy mode)
copy_run:
        lda vd+1
        VPUT 18
        lda vd
        VPUT 19
        lda vs+1
        VPUT 32
        lda vs
        VPUT 33
        lda vn
        VPUT 30
        rts
next_line:                        ; vd, vs += 80
        lda vd
        clc
        adc #80
        sta vd
        bcc :+
        inc vd+1
:       lda vs
        clc
        adc #80
        sta vs
        bcc :+
        inc vs+1
:       rts

; ---------------------------------------------------------------------
; draw_tile: A = tile id, trow = ground row, bcol = left column (-3..61).
; Draws the tile's visible, dirty cells into the compose buffer.
; Record: h, flags, h*4 cell pointers (hi byte 0 = empty), cell data:
;   type, attribute, 8 bitmap bytes, 8 mask bytes (not for type 1)
; prep_tiles has already taken column*8 off each cell pointer, so cell
; byte k of column C has index C*8+2+k in both the cell data and the
; compose row (rbp = row base - 2).  (Same code as the VIC-20 engine.)
; ---------------------------------------------------------------------
draw_tile:
        asl
        tay
        lda TILES+1,y
        sta sp
        lda TILES+2,y
        sta sp+1
        ldx bcol                  ; index wraps inside the 256-byte table
        lda COL4,x
        bne :+
        rts
:       tax
        and #$0f
        sta colon
        txa
        lsr
        lsr
        lsr
        lsr
        sta coldt
        ldy #0
        lda (sp),y
        sta rcnt
        lda trow
        clc
        adc #2
        sec
        sbc rcnt
        sta crow
        lda bcol                  ; bc16 = CB + bcol*8 - 2, rcb = CC + bcol
        clc
        adc #3
        tax
        lda bc8lo,x
        sta bc16
        lda bc8hi,x
        sta bc16+1
        lda rcblo,x
        sta rcb
        lda rcbhi,x
        sta rcb+1
        ldy #2
@row:   ldx crow
        lda ROWM,x
        lsr
        bcc @skiprow
        lsr
        lda coldt
        bcc :+
        lda colon
:       sta cols
        bne @base
@skiprow:
        tya
        clc
        adc #8
        tay
        jmp @next
@base:  lda bc16
        clc
        adc cbrowlo,x
        sta rbp
        lda bc16+1
        adc cbrowhi,x
        sta rbp+1
        lda rcb
        clc
        adc rowwlo,x
        sta rcp
        lda rcb+1
        adc rowwhi,x
        sta rcp+1
.repeat 4, C
        lsr cols
        bcs :+
        jmp .ident(.sprintf("@nc%d", C))
:       iny
        lda (sp),y                ; pointer hi, 0 = empty cell
        bne :+
        jmp .ident(.sprintf("@ne%d", C))
:       sta cp+1
        dey
        lda (sp),y
        sta cp
        sty ysave
        ldy #(C*8)
        lda (cp),y                ; type
        tax
        cpx #3
        beq :+
        iny
        lda (cp),y
        ldy #C
        sta (rcp),y
:       ldy #(C*8+2)
        cpx #1
        bne :+
.repeat 8
        lda (cp),y
        sta (rbp),y
        iny
.endrepeat
        jmp .ident(.sprintf("@dn%d", C))
:       lda cp
        clc
        adc #8
        sta mp
        lda cp+1
        adc #0
        sta mp+1
.repeat 8
        lda (rbp),y
        and (mp),y
        ora (cp),y
        sta (rbp),y
        iny
.endrepeat
.ident(.sprintf("@dn%d", C)):
        ldy ysave
.ident(.sprintf("@nc%d", C)):
        iny
.ident(.sprintf("@ne%d", C)):
        iny
.endrepeat
@next:  inc crow
        dec rcnt
        beq @out
        jmp @row
@out:   rts

; prep_tiles (once, after loading): cell pointer -= column*8
prep_tiles:
        lda TILES
        beq @done
        sta rcnt
@t:     lda rcnt
        asl
        tay
        lda TILES+1,y
        sta sp
        lda TILES+2,y
        sta sp+1
        ldy #0
        lda (sp),y                ; h rows of 4 cells
        beq @nt
        asl
        asl
        sta ccnt
        ldy #2
@c:     tya                       ; column*8 = ((y-2) & 6) * 4
        sec
        sbc #2
        and #6
        asl
        asl
        sta tmp
        lda (sp),y
        iny
        ora (sp),y
        beq @nc
        dey
        lda (sp),y
        sec
        sbc tmp
        sta (sp),y
        iny
        lda (sp),y
        sbc #0
        sta (sp),y
@nc:    iny
        dec ccnt
        bne @c
@nt:    dec rcnt
        bne @t
@done:  rts

; build_col4: COL4[bcol] for bcol -3..61 from COLM: bit C = column bcol+C
; on screen, bit 4+C = on screen and dirty. Built right to left.
build_col4:
        lda #0
        ldx #(VP_C1+3)
@l:     asl
        and #$ee
        ldy COLM,x
        ora colbits,y
        sta COL4,x
        dex
        cpx #<(VP_C0-4)
        bne @l
        rts
colbits: .byte $00,$01,$00,$11    ; COLM 0, 1 (on screen), 3 (+ dirty)

; ---------------------------------------------------------------------
; figures: soft sprites into the hidden frame, back to front: entities
; by depth x+y (stable), the hero last
; ---------------------------------------------------------------------
figures:
        lda #0
        sta nvis
        lda M_NENT
        beq @hero
        sta rcnt
        lda #0
        sta ccnt                  ; entity record offset
@el:    ldy ccnt
        lda ENTS+E_TYPE,y
        beq @en
        cmp #ET_TRIGGER
        beq @en
        lda ENTS+E_X,y            ; depth = x+y, insertion sort (stable)
        clc
        adc ENTS+E_Y,y
        sta tmp
        ldx nvis
@ins:   cpx #0
        beq @put
        lda VISD-1,x
        cmp tmp
        beq @put
        bcc @put
        sta VISD,x
        lda VISLIST-1,x
        sta VISLIST,x
        dex
        jmp @ins
@put:   lda tmp
        sta VISD,x
        lda ccnt
        sta VISLIST,x
        inc nvis
        lda nvis
        cmp #31
        bcs @hero
@en:    lda ccnt
        clc
        adc #8
        sta ccnt
        dec rcnt
        bne @el
@hero:  ldx #0
@dl:    cpx nvis
        beq @dh
        stx lvl
        ldy VISLIST,x
        lda ENTS+E_SPR,y
        and #3
        sta sid
        lda ENTS+E_COL,y
        and #15
        tax
        lda C2R,x
        sta sfg
        lda ENTS+E_X,y
        sta tx
        lda ENTS+E_Y,y
        sta ty
        jsr place_fig
        ldx lvl
        inx
        jmp @dl
@dh:    lda #0
        sta sid
        lda M_HEROCOL
        and #15
        tax
        lda C2R,x
        sta sfg
        lda px
        sta tx
        lda py
        sta ty
        ; fall through

; place_fig: figure sid in colour sfg standing on map square tx,ty.
; Its 4x4 block of cells, clipped to the viewport, is read from the hidden
; frame line by line, masked and written back.
place_fig:
        lda tx
        sec
        sbc px
        sta nx                    ; dx
        lda ty
        sec
        sbc py
        sta ny                    ; dy
        lda nx                    ; far away? (also keeps the maths in range)
        sec
        sbc ny
        clc
        adc #16
        cmp #33
        bcc :+
        rts
:       lda nx
        clc
        adc ny
        clc
        adc #12
        cmp #31
        bcc :+
        rts
:       jsr height_at
        sta hgt
        lda nx
        sec
        sbc ny
        asl
        clc
        adc #CENTER_COL
        sta spx                   ; -3..61
        lda nx
        clc
        adc ny
        clc
        adc #(CENTER_ROW-2)
        sec
        sbc hgt
        sta spy                   ; -6..27
        clc
        adc #3
        bpl :+
        rts                       ; above the viewport
:       lda spy
        bmi :+
        cmp #(VP_R1+1)
        bcc :+
        rts                       ; below it
:       lda #0                    ; visible block rows fra..frb
        sta fra
        lda spy
        bpl :+
        eor #$ff
        clc
        adc #1
        sta fra
:       lda #VP_R1
        sec
        sbc spy
        cmp #3
        bcc :+
        lda #3
:       sta frb
        lda #0                    ; and columns fca..fcb
        sta fca
        lda spx
        bpl :+
        eor #$ff
        clc
        adc #1
        sta fca
:       lda #VP_C1
        sec
        sbc spx
        cmp #3
        bcc :+
        lda #3
:       sta fcb
        sec
        sbc fca
        clc
        adc #1
        sta fnc
        lda sid                   ; fp = CSPR + sid*256
        clc
        adc #>CSPR
        sta fp+1
        lda #<CSPR
        sta fp
        lda fra
        sta fro
@row:   lda spy                   ; X = screen row
        clc
        adc fro
        tax
        lda spx
        clc
        adc fca
        sta tmp2                  ; first screen column
        clc
        adc r640lo,x
        sta vd
        lda r640hi,x
        adc hbm
        sta vd+1
        lda fro                   ; fcell = (fro*4 + fca) * 16
        asl
        asl
        clc
        adc fca
        asl
        asl
        asl
        asl
        sta fcell
        lda #0
        sta fln
@ln:    jsr vdc_ua                ; read the run
        ldx #0
@rd:    VWAIT
        lda VDC_D
        sta LB,x
        inx
        cpx fnc
        bne @rd
        lda fcell                 ; (run & mask) | figure
        clc
        adc fln
        tay
        ldx #0
@cm:    lda (fp),y
        sta tmp
        tya
        ora #8
        tay
        lda LB,x
        and (fp),y
        ora tmp
        sta LB,x
        tya
        clc
        adc #8
        tay
        inx
        cpx fnc
        bne @cm
        jsr vdc_ua                ; write it back
        ldx #0
@wr:    lda LB,x
        VWAIT
        sta VDC_D
        inx
        cpx fnc
        bne @wr
        lda vd
        clc
        adc #80
        sta vd
        bcc @nl
        inc vd+1
@nl:    inc fln
        lda fln
        cmp #8
        bne @ln
        lda spy                   ; attributes: cells with body pixels take
        clc                       ; the figure colour as foreground (bits 0-3)
        adc fro
        tax
        lda r80lo,x
        clc
        adc #<AT_A
        sta vd
        lda r80hi,x
        adc hath
        sta vd+1
        lda vd
        clc
        adc tmp2
        sta vd
        bcc :+
        inc vd+1
:       jsr vdc_ua
        ldx #0
@ra:    VWAIT
        lda VDC_D
        sta LB,x
        inx
        cpx fnc
        bne @ra
        lda sid                   ; Y = sid*16 + fro*4 + fca
        asl
        asl
        sta tmp
        lda fro
        clc
        adc tmp
        asl
        asl
        clc
        adc fca
        tay
        ldx #0
@ca:    lda CSPR_F,y
        lsr
        bcc @cn
        lda LB,x
        and #$f0
        ora sfg
        sta LB,x
@cn:    iny
        inx
        cpx fnc
        bne @ca
        jsr vdc_ua
        ldx #0
@wa:    lda LB,x
        VWAIT
        sta VDC_D
        inx
        cpx fnc
        bne @wa
        lda fro
        cmp frb
        beq @out
        inc fro
        jmp @row
@out:   rts

; ---------------------------------------------------------------------
; flip: in vertical blank, show the hidden frame
; ---------------------------------------------------------------------
flip:
@w1:    lda VDC_A                 ; wait for the start of vertical blank
        and #$20
        bne @w1
@w2:    lda VDC_A
        and #$20
        beq @w2
        lda front
        eor #1
        sta front
        beq @a
        lda #>BM_B
        VPUT 12
        lda #<BM_B
        VPUT 13
        lda #>AT_B
        VPUT 20
        lda #<AT_B
        VPUT 21
        lda #>BM_A
        sta hbm
        lda #>AT_A
        sta hath
        rts
@a:     lda #>BM_A
        VPUT 12
        lda #<BM_A
        VPUT 13
        lda #>AT_A
        VPUT 20
        lda #<AT_A
        VPUT 21
        lda #>BM_B
        sta hbm
        lda #>AT_B
        sta hath
        rts

; ---------------------------------------------------------------------
; get_move: one step per key press or joystick push (port 2).
;   Keyboard: same keys as the other platforms (common/game.s key_step).
;   Joystick (map axes, as on the C64): up = y-1, down = y+1, left = x-1,
;   right = x+1; diagonals combine both into straight screen moves.
; Returns A = 0 nothing happened, 1 moved (mvdx/mvdy), 2 bumped
; ---------------------------------------------------------------------
get_move:
@rel:   lda $dc00                 ; wait for the stick to be released
        and #$1f
        cmp #$1f
        bne @rel
@poll:  jsr GETIN                 ; keyboard first
        beq @joy
        jsr key_step
        bcc @joy
        lda #0                    ; drop key repeats queued during the redraw
        sta NDX
        jmp try_move
@joy:   lda $dc00
        and #$0f
        cmp #$0f
        beq @poll
        sta tmp
        ldx #0                    ; short settle so diagonals register
@dl:    dex
        bne @dl
        lda $dc00
        and tmp
        and #$0f
        sta tmp
        lda px
        sta nx
        lda py
        sta ny
        lda tmp
        lsr
        bcs :+
        dec ny
:       lsr
        bcs :+
        inc ny
:       lsr
        bcs :+
        dec nx
:       lsr
        bcs :+
        inc nx
:       jmp try_move

; plat_flash: hit feedback for bump (common/game.s): border flashes red
plat_flash:
        lda #9
        VPUT 26
        ldx #$60
@d1:    ldy #0
@d2:    dey
        bne @d2
        dex
        bne @d1
        lda M_C128A
        and #$0f
        VPUT 26
        rts

.include "../common/view.s"
.include "../common/game.s"

; ---------------------------------------------------------------------
.segment "RODATA"

.repeat 256, I                    ; text below is plain ASCII (no PETSCII mapping)
        .charmap I, I
.endrepeat

fn_ct:    .byte $43,$54,$49,$4c,$45,$53,$2a             ; "CTILES*"
fn_ct_len = * - fn_ct
fn_cs:    .byte $43,$53,$50,$52,$49,$54,$45,$53,$2a     ; "CSPRITES*"
fn_cs_len = * - fn_cs
fn_map:   .byte $4d,$41,$50,$30,$31,$2a                 ; "MAP01*"
fn_map_len = * - fn_map

; static panel text: column, row, length, address (editor/c128.js C128_PANEL)
ptext:
        .byte TEXT_COL, 1, 5
        .word t_title
        .byte TEXT_COL, 2, 8
        .word t_sub
        .byte TEXT_COL, 8, 5
        .word t_k1
        .byte TEXT_COL, 9, 5
        .word t_k2
        .byte TEXT_COL, 10, 5
        .word t_k3
ptext_len = * - ptext
t_title:  .byte "ISO64"
t_sub:    .byte "C128 VDC"
t_k1:     .byte "Q W E"
t_k2:     .byte "A + D"
t_k3:     .byte "Z S C"
t_pos:    .byte "POS 00,00"

cbrowlo:                          ; compose row offsets
.repeat VP_ROWS, I
        .byte <(I*VP_COLS*8)
.endrepeat
cbrowhi:
.repeat VP_ROWS, I
        .byte >(I*VP_COLS*8)
.endrepeat
rowwlo:
.repeat VP_ROWS, I
        .byte <(I*VP_COLS)
.endrepeat
rowwhi:
.repeat VP_ROWS, I
        .byte >(I*VP_COLS)
.endrepeat
bc8lo:                            ; bcol = -3..61: CB + bcol*8 - 2, CC + bcol
.repeat VP_COLS+3, I
        .byte <(CB+(I-3)*8-2)
.endrepeat
bc8hi:
.repeat VP_COLS+3, I
        .byte >(CB+(I-3)*8-2)
.endrepeat
rcblo:
.repeat VP_COLS+3, I
        .byte <(CC+I-3)
.endrepeat
rcbhi:
.repeat VP_COLS+3, I
        .byte >(CC+I-3)
.endrepeat
r640lo:                           ; VDC offsets of cell rows: bitmap, attributes
.repeat 26, I
        .byte <(I*640)
.endrepeat
r640hi:
.repeat 26, I
        .byte >(I*640)
.endrepeat
r80lo:
.repeat 26, I
        .byte <(I*80)
.endrepeat
r80hi:
.repeat 26, I
        .byte >(I*80)
.endrepeat
