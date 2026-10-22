; =====================================================================
;  ISO64 engine - VIC-20 platform layer (PAL, +32K). Shared logic in ../common
;
;  Character-mode renderer. The map is composed into an off-screen buffer
;  of 22x18 cells (8 bytes each) with the same scroll copy + strip redraw
;  as the C64. Then "emit" turns every viewport cell, with soft sprites
;  laid over it, into a character: each distinct 8x8 pattern gets a code
;  in the hidden frame's half of the character set (0-111 or 112-223).
;  Flipping $9002 bit 7 switches screen, colour RAM and that half at once.
;  Per-cell labels carried with the compose buffers let unchanged cells
;  skip the hash (see emit).
;
;  Data files (from the browser editor, loaded from sd2iec):
;    VTILES   -> $7000   VIC-20 tiles
;    VSPRITES -> $3800   pre-shifted figures + colour table
;    MAP01    -> $4000   the shared map file (loaded relocated)
;  Layout: docs/PLATFORMS.md section 6.
; =====================================================================

SCR_A     = $1000          ; shown when $9002 bit 7 = 0, colour RAM $9400
SCR_B     = $1200          ; shown when $9002 bit 7 = 1, colour RAM $9600
COL_A     = $9400
COL_B     = $9600
CHARS     = $1400          ; 256 characters
COLM      = $1c00          ; per column: bit0 in viewport, bit1 dirty
ROWM      = $1d00          ; per row:    bit0 in viewport, bit1 dirty
HASH      = $1e00          ; pattern hash -> code+1 (0 = empty)
COL4      = $1f00          ; per tile column bcol: on screen (bits 0-3), dirty (4-7)
HV        = $1f20          ; hash of each character code's pattern (codes 0-223)
VSPR      = $3800          ; figures: s*256 + cell*16 = 8 bitmap + 8 mask
VSPR_X    = $3c00          ; s*16 + cell: 1 if the cell has body pixels
C2V       = $3c40          ; C64 colour -> VIC-20 cell colour
OV        = $3d00          ; per viewport cell: overlay slot + 1
SLOTFG    = $3e90          ; overlay slot colours
SLOTCELL  = $3f30          ; overlay slot -> cell index, low bytes
SLOTCELLH = $4e00          ; ... high bytes
VISLIST   = $4ea0          ; visible entities, depth sorted (record offsets)
VISD      = $4ec0          ; ... and their depth
SLOTLO    = $4f00          ; overlay slot addresses (built by init_vic)
SLOTHI    = $4f70
MAP       = $4000
CB_A      = $5000          ; compose buffer A: 396 cells x 8 bytes
CC_A      = $5c60          ; ... and its cell colours
CB_B      = $5e00          ; compose buffer B
CC_B      = $6a60
SLOTS     = $6c00          ; overlay slots, 8 bytes each
REMAP     = $6f80          ; emit: label -> code this frame ($ff = not yet)
FRCLS     = $6ff0          ; front buffer's labels (word)
CLS_A     = $34e8          ; per buffer cell: label = the code its pattern got
CLS_B     = $3674          ; when the buffer was last emitted ($ff = unknown)
TILES     = $7000

.include "../common/defs.inc"

M_VBG     = MAP+$0b
M_VBORDER = MAP+$0c
M_VAUX    = MAP+$0d

; ---- viewport ---------------------------------------------------------
VP_C0      = 0
VP_C1      = 21
VP_R0      = 0
VP_R1      = 17
VP_ROWS    = VP_R1-VP_R0+1
VP_COLS    = VP_C1-VP_C0+1
VP_CELLS   = VP_ROWS*VP_COLS
CENTER_COL = 9
CENTER_ROW = 7
CODES      = 112           ; characters per frame
TEXT_CH    = 224           ; blank character outside the viewport
MAXSLOT    = 112           ; 7 figures of 16 cells
FLIP_RAST  = 114           ; $9004 (raster/2): just below the viewport

VIC_COLS  = $9002
VIC_RAST  = $9004
VIC_MEM   = $9005
VIC_AUX   = $900e
VIC_COL   = $900f

SETLFS = $ffba
SETNAM = $ffbd
LOAD   = $ffd5
GETIN  = $ffe4

.include "../common/zp.inc"

; VIC-20 only ($60-$8f)
fcb    = $60               ; front / back compose bitmap
bcb    = $62
frcc   = $64               ; front / back compose colours
bkcc   = $66
bkcls  = $68               ; back buffer's labels
scrp   = $6a
colp   = $6c
ovp    = $6e
chp    = $70
chunk  = $72               ; emit: cells 0-255 / 256-395
lim    = $73
cbase  = $74
next   = $75
ccolv  = $76
nslot  = $77
spx    = $78
spy    = $79
sid    = $7a
sfg    = $7b
sprp   = $7c
celli  = $7e
nvis   = $80
tcp    = $82
bc16   = $84
rcp    = $86
ccx    = $88
ccy    = $89
slp    = $8a
tcc    = $8c
clsp   = $8e
hsave  = spx               ; emit: hash of the pattern being looked up
obase  = spy               ; emit: first code of the shown half
rend   = ctype             ; scroll_copy: row after the last one copied
jrow   = cscr              ; scroll_copy: copier row slot holding the jmp
rcb    = rsp               ; draw_tile: bkcc + bcol

; ---------------------------------------------------------------------
.segment "LOADADDR"
        .word $1201
.segment "STUB"
        .word stub_end            ; 10 SYS8192
        .word 10
        .byte $9e, $38, $31, $39, $32, 0
stub_end:
        .word 0

.segment "CODE"
start:
        lda #0
        sta tcp+1                 ; tcp+1 = 0: load to the file's own address
        lda #fn_vt_len
        ldx #<fn_vt
        ldy #>fn_vt
        jsr load_file
        lda #fn_vs_len
        ldx #<fn_vs
        ldy #>fn_vs
        jsr load_file
        lda #<MAP                 ; the map file is shared with the C64:
        sta tcp                   ; load it relocated
        lda #>MAP
        sta tcp+1
        lda #fn_map_len
        ldx #<fn_map
        ldy #>fn_map
        jsr load_file

        jsr init_vic
        jsr prep_tiles
        jsr prep_sprites
        lda M_STARTX
        sta px
        lda M_STARTY
        sta py
        jsr render_full
        jsr emit
        jsr flip

main_loop:
        jsr get_move              ; A: 0 nothing, 1 moved, 2 bumped
        beq main_loop
        cmp #1
        bne @bump
        jsr render_scroll
        jsr emit
        jsr flip
        jmp main_loop
@bump:  jsr swap_cb               ; same map picture, new figures:
        jsr emit                  ; emit the current buffer again
        jsr flip
        jmp main_loop

; ---------------------------------------------------------------------
; load_file: A = name length, X/Y = name. tcp = destination, or tcp+1 = 0
; to load to the file's own address. Flashes the border if missing.
load_file:
        jsr SETNAM
        ldx $ba
        cpx #8
        bcs :+
        ldx #8
:       ldy #1
        lda tcp+1
        beq :+
        ldy #0
:       lda #1
        jsr SETLFS
        lda #0
        ldx tcp
        ldy tcp+1
        jsr LOAD
        bcs load_err
        rts
load_err:
        inc VIC_COL
        jmp load_err

; ---------------------------------------------------------------------
init_vic:
        lda #$cd                  ; screen $1000(+$200), characters $1400
        sta VIC_MEM
        lda #VP_COLS              ; 22 columns, bit 7 = 0: screen A shown
        sta VIC_COLS
        lda M_VBG
        asl
        asl
        asl
        asl
        ora #8
        ora M_VBORDER
        sta VIC_COL
        lda M_VAUX
        asl
        asl
        asl
        asl
        sta VIC_AUX
        lda #0
        sta front
        sta jrow

        jsr fill_pages_at_14      ; characters, masks, hash
        lda #>OV                  ; overlay table
        ldx #2
        jsr clear_pages
        lda #>CB_A                ; both compose buffers + colours
        ldx #28
        jsr clear_pages
        ldx #(VP_CELLS/2)         ; compose colours: multicolour, colour 0
        lda #8
@cc:    sta CC_A-1,x
        sta CC_A+VP_CELLS/2-1,x
        sta CC_B-1,x
        sta CC_B+VP_CELLS/2-1,x
        dex
        bne @cc
        ldx #0                    ; both screens blank (text character)
@sc:    lda #TEXT_CH
        sta SCR_A,x
        sta SCR_A+$100,x
        sta SCR_B,x
        sta SCR_B+$100,x
        lda #8
        sta COL_A,x
        sta COL_A+$100,x
        sta COL_B,x
        sta COL_B+$100,x
        inx
        bne @sc
        lda #$ff                  ; CLS_A and CLS_B are adjacent
        ldy #(VP_CELLS/2)
@cl:    sta CLS_A-1,y
        sta CLS_A+VP_CELLS/2-1,y
        sta CLS_B-1,y
        sta CLS_B+VP_CELLS/2-1,y
        dey
        bne @cl
        lda #<CLS_A
        sta bkcls
        lda #>CLS_A
        sta bkcls+1
        lda #<CLS_B
        sta FRCLS
        lda #>CLS_B
        sta FRCLS+1
        ldx #0                    ; overlay slot addresses
        lda #<SLOTS
        sta bp
        lda #>SLOTS
@sl:    sta SLOTHI,x
        pha
        lda bp
        sta SLOTLO,x
        clc
        adc #8
        sta bp
        pla
        adc #0
        inx
        cpx #MAXSLOT
        bne @sl
        lda #<CB_A                ; first frame is composed into A
        sta bcb
        lda #>CB_A
        sta bcb+1
        lda #<CB_B
        sta fcb
        lda #>CB_B
        sta fcb+1
        lda #<CC_A
        sta bkcc
        lda #>CC_A
        sta bkcc+1
        lda #<CC_B
        sta frcc
        lda #>CC_B
        sta frcc+1
        rts

; clear 12 pages from $1400 (characters, COLM, ROWM, HASH)
fill_pages_at_14:
        lda #>CHARS
        ldx #12
; A = first page, X = page count
clear_pages:
        sta bp+1
        lda #0
        sta bp
        tay
@l:     sta (bp),y
        iny
        bne @l
        inc bp+1
        dex
        bne @l
        rts

; ---------------------------------------------------------------------
render_full:
        jsr view_full
        lda #VP_C0
        sta rc0
        lda #VP_C1
        sta rc1
        lda #VP_R0
        sta rr0
        lda #VP_R1
        sta rr1
        jsr clear_rect
        jsr build_col4
        jmp draw_all

render_scroll:
        jsr view_scroll
        jsr build_col4
        jsr scroll_copy
        jsr clear_dirty
        jmp draw_all

swap_cb:
        ldx fcb
        lda bcb
        sta fcb
        stx bcb
        ldx fcb+1
        lda bcb+1
        sta fcb+1
        stx bcb+1
        ldx frcc
        lda bkcc
        sta frcc
        stx bkcc
        ldx frcc+1
        lda bkcc+1
        sta frcc+1
        stx bkcc+1
        ldx FRCLS
        lda bkcls
        sta FRCLS
        stx bkcls
        ldx FRCLS+1
        lda bkcls+1
        sta FRCLS+1
        stx bkcls+1
        rts

; clear cells rc0..rc1 x rr0..rr1 of the back compose buffer
; (bitmap 0, colour 8 = multicolour colour 0, label unknown)
clear_rect:
        ldx rr0
        lda rc0                   ; bp = bcb + cbrow[rr0] + rc0*8
        asl
        asl
        asl
        clc
        adc cbrowlo,x
        sta bp
        lda cbrowhi,x
        adc #0
        sta bp+1
        lda bp
        clc
        adc bcb
        sta bp
        lda bp+1
        adc bcb+1
        sta bp+1
        lda rc0                   ; clp = bkcc + row22[rr0] + rc0, mp = labels
        clc
        adc row22lo,x
        sta clp
        lda row22hi,x
        adc #0
        sta clp+1
        lda clp
        clc
        adc bkcls
        sta mp
        lda clp+1
        adc bkcls+1
        sta mp+1
        lda clp
        clc
        adc bkcc
        sta clp
        lda clp+1
        adc bkcc+1
        sta clp+1
        lda rc1
        sec
        sbc rc0
        sta ncell                 ; cells - 1
        clc
        adc #1
        asl
        asl
        asl
        sta nbytes
        lda rr1
        sec
        sbc rr0
        sta rcnt                  ; rows - 1
@r:     ldy nbytes
        lda #0
@b:
.repeat 8                         ; one cell per pass
        dey
        sta (bp),y
.endrepeat
        bne @b                    ; (Z from the last dey)
        ldy ncell
@s:     lda #8
        sta (clp),y
        lda #$ff
        sta (mp),y
        dey
        bpl @s
        dec rcnt
        bmi @done
        lda bp                    ; next row
        clc
        adc #<(VP_COLS*8)
        sta bp
        bcc :+
        inc bp+1
:       lda clp
        clc
        adc #VP_COLS
        sta clp
        bcc :+
        inc clp+1
:       lda mp
        clc
        adc #VP_COLS
        sta mp
        bcc @r
        inc mp+1
        jmp @r
@done:  rts

; ---------------------------------------------------------------------
; scroll_copy: front compose -> back compose, shifted by dcol/drow cells.
; Three 18-row copiers (bitmap, colour, labels) with operands patched
; per step. The labels lie at a fixed distance from the colours:
; s1/d1 = FRCLS - frcc, mp = bkcls - bkcc.
; ---------------------------------------------------------------------
scroll_copy:
        lda FRCLS
        sec
        sbc frcc
        sta s1
        lda FRCLS+1
        sbc frcc+1
        sta d1
        lda bkcls
        sec
        sbc bkcc
        sta mp
        lda bkcls+1
        sbc bkcc+1
        sta mp+1
        lda dcol
        bmi @neg
        sta cA                    ; first destination column
        lda #0
        sta cS                    ; first source column
        lda dcol
        jmp @n
@neg:   lda #0
        sta cA
        sec
        sbc dcol
        sta cS
@n:     sta tmp                   ; |dcol|
        lda #VP_COLS
        sec
        sbc tmp
        sta ncell
        asl
        asl
        asl
        sta nbytes
        lda cS
        asl
        asl
        asl
        sta s8
        lda cA
        asl
        asl
        asl
        sta d8

        lda #(VP_R1+1)            ; dirty rows are not copied: rows drow..17
        ldx drow                  ; (new rows on top) or 0..17+drow (bottom)
        bpl :+
        clc
        adc drow
        ldx #VP_R0
:       sta rend
        lda #0
        sta r6
@pl:    txa                       ; source row = row - drow
        sec
        sbc drow
        sta srow
        stx tmp
        ldy srow
        ; bitmap source: fcb + cbrow[srow] + cS*8 - 1
        lda cbrowlo,y
        clc
        adc s8
        sta tcp
        lda cbrowhi,y
        adc #0
        sta tcp+1
        lda tcp
        clc
        adc fcb
        sta tcp
        lda tcp+1
        adc fcb+1
        sta tcp+1
        jsr tcp_minus1
        ldy r6
        lda tcp
        sta bmc_body+1,y
        lda tcp+1
        sta bmc_body+2,y
        ; colour source: fcc + row22[srow] + cS - 1
        ldy srow
        lda row22lo,y
        clc
        adc cS
        sta tcp
        lda row22hi,y
        adc #0
        sta tcp+1
        lda tcp
        clc
        adc frcc
        sta tcp
        lda tcp+1
        adc frcc+1
        sta tcp+1
        jsr tcp_minus1
        ldy r6
        lda tcp
        sta ccc_body+1,y
        clc
        adc s1
        sta lcc_body+1,y
        lda tcp+1
        sta ccc_body+2,y
        adc d1
        sta lcc_body+2,y
        ; bitmap destination: bcb + cbrow[row] + cA*8 - 1
        ldy tmp
        lda cbrowlo,y
        clc
        adc d8
        sta tcp
        lda cbrowhi,y
        adc #0
        sta tcp+1
        lda tcp
        clc
        adc bcb
        sta tcp
        lda tcp+1
        adc bcb+1
        sta tcp+1
        jsr tcp_minus1
        ldy r6
        lda tcp
        sta bmc_body+4,y
        lda tcp+1
        sta bmc_body+5,y
        ; colour destination: bcc + row22[row] + cA - 1
        ldy tmp
        lda row22lo,y
        clc
        adc cA
        sta tcp
        lda row22hi,y
        adc #0
        sta tcp+1
        lda tcp
        clc
        adc bkcc
        sta tcp
        lda tcp+1
        adc bkcc+1
        sta tcp+1
        jsr tcp_minus1
        ldy r6
        lda tcp
        sta ccc_body+4,y
        clc
        adc mp
        sta lcc_body+4,y
        lda tcp+1
        sta ccc_body+5,y
        adc mp+1
        sta lcc_body+5,y
        lda r6
        clc
        adc #6
        sta r6
        ldx tmp
        inx
        cpx rend
        beq :+
        jmp @pl
:       ldy jrow                  ; end the copiers after the last row
        lda #$bd                  ; (jrow 0 = no jmp: row 0 is lda abs,x)
        sta bmc_body,y
        sta ccc_body,y
        sta lcc_body,y
        ldy r6
        cpy #(VP_ROWS*6)
        bne :+
        ldy #0
:       sty jrow                  ; (Z from cpy / ldy)
        beq @cp
        lda #$4c                  ; jmp to the copier's dex
        sta bmc_body,y
        sta ccc_body,y
        sta lcc_body,y
        lda #<(bmc_body+VP_ROWS*6)
        sta bmc_body+1,y
        lda #>(bmc_body+VP_ROWS*6)
        sta bmc_body+2,y
        lda #<(ccc_body+VP_ROWS*6)
        sta ccc_body+1,y
        lda #>(ccc_body+VP_ROWS*6)
        sta ccc_body+2,y
        lda #<(lcc_body+VP_ROWS*6)
        sta lcc_body+1,y
        lda #>(lcc_body+VP_ROWS*6)
        sta lcc_body+2,y
@cp:    ldx nbytes
        jsr bmc_body
        ldx ncell
        jsr ccc_body
        ldx ncell
        jmp lcc_body

tcp_minus1:
        lda tcp
        bne :+
        dec tcp+1
:       dec tcp
        rts

; operands of row slot R sit at body+R*6+1 (source) and body+R*6+4 (dest);
; a jmp to the dex may end the copy early (scroll_copy, jrow)
.macro ROWCOPY
:
.repeat VP_ROWS
        lda $ffff,x
        sta $ffff,x
.endrepeat
        dex
        bne :-
        rts
.endmacro
bmc_body: ROWCOPY
ccc_body: ROWCOPY
lcc_body: ROWCOPY

; ---------------------------------------------------------------------
; draw_tile: A = tile id, trow = ground row, bcol = left column (-3..21).
; Draws the tile's visible, dirty cells into the back compose buffer.
; Record: h, flags, h*4 cell pointers (hi byte 0 = empty), cell data:
;   type, colour byte, 8 bitmap bytes, 8 mask bytes (not for type 1)
; prep_tiles has already taken column*8 off each cell pointer, so cell
; byte k of column C has index C*8+2+k in both the cell data and the
; compose row (rbp = row base - 2).
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
        lda bcol                  ; bc16 = bcb + bcol*8 - 2, rcb = bkcc + bcol
        clc                       ; (bcol signed)
        adc #3
        tax
        lda bc8lo,x
        clc
        adc bcb
        sta bc16
        lda bc8hi,x
        adc bcb+1
        sta bc16+1
        lda bcol
        clc
        adc bkcc
        sta rcb
        lda bcsgn,x
        adc bkcc+1
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
        adc row22lo,x
        sta rcp
        lda rcb+1
        adc row22hi,x
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

; build_col4: COL4[bcol] for bcol -3..21 from COLM: bit C = column bcol+C
; on screen, bit 4+C = on screen and dirty. Built right to left:
; COL4[x] = (COL4[x+1] << 1, minus column x+4) | column x
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
; build_overlays: lay the figures over copies of the cells they touch
; (overlay slots), back to front: entities by depth x+y, the hero last
; ---------------------------------------------------------------------
build_overlays:
        lda #0
        sta nslot
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
        ldx ENTS+E_COL,y
        lda C2V,x
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
        ldx M_HEROCOL
        lda C2V,x
        sta sfg
        lda px
        sta tx
        lda py
        sta ty
        ; fall through

; figure sid in colour sfg standing on map square tx,ty
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
        adc #8
        cmp #17
        bcs @out
        lda nx
        clc
        adc ny
        clc                       ; s = dx+dy in -12..15 (raised ground near
        adc #12                   ; the bottom edge can still show)
        cmp #28
        bcs @out
        jsr height_at
        sta hgt
        lda nx
        sec
        sbc ny
        asl
        clc
        adc #CENTER_COL
        sta spx                   ; left cell column of the 4x4 block
        lda nx
        clc
        adc ny
        clc
        adc #(CENTER_ROW-2)
        sec
        sbc hgt
        sta spy                   ; top cell row of the block
        lda #0
        sta ccy
@cy:    lda spy
        clc
        adc ccy
        cmp #VP_ROWS              ; (negative rows wrap to >= $80)
        bcs @ny
        sta crow
        lda #0
        sta ccx
@cx:    lda spx
        clc
        adc ccx
        cmp #VP_COLS
        bcs @nx
        sta ccol
        jsr fig_cell
@nx:    inc ccx
        lda ccx
        cmp #4
        bne @cx
@ny:    inc ccy
        lda ccy
        cmp #4
        bne @cy
@out:   rts

; one cell (ccx,ccy) of figure sid onto viewport cell ccol,crow.
; Cells without figure pixels (VSPR_X bit 1 clear) change nothing.
fig_cell:
        lda ccy                   ; tmp = cell of the 4x4 block
        asl
        asl
        ora ccx
        sta tmp
        lda sid
        asl
        asl
        asl
        asl
        ora tmp
        sta tmp2                  ; VSPR_X index
        tay
        lda VSPR_X,y
        and #2
        bne :+
        rts
:       lda tmp                   ; image = VSPR + sid*256 + cell*16,
        asl                       ; its mask 8 bytes on (cp)
        asl
        asl
        asl
        sta sprp
        ora #8
        sta cp
        lda sid
        clc
        adc #>VSPR
        sta sprp+1
        sta cp+1
        ldx crow                  ; celli = crow*22 + ccol
        lda row22lo,x
        clc
        adc ccol
        sta celli
        sta ovp                   ; ovp = OV + celli (OV is page aligned)
        lda row22hi,x
        adc #0
        sta celli+1
        adc #>OV
        sta ovp+1
        ldy #0
        lda (ovp),y
        beq :+
        jmp @have
:       lda nslot                 ; new slot from the composed cell
        cmp #MAXSLOT
        bcc :+
        rts
:       tax
        inc nslot
        adc #1                    ; (C = 0)
        sta (ovp),y
        lda celli
        sta SLOTCELL,x
        lda celli+1
        sta SLOTCELLH,x
        lda SLOTLO,x
        sta slp
        lda SLOTHI,x
        sta slp+1
        lda celli                 ; colour = bcc[celli]
        clc
        adc bkcc
        sta tcc
        lda celli+1
        adc bkcc+1
        sta tcc+1
        lda (tcc),y
        sta SLOTFG,x
        lda celli                 ; source = bcb + celli*8
        asl
        sta tcp
        lda celli+1
        rol
        asl tcp
        rol
        asl tcp
        rol
        sta tcp+1
        lda tcp
        clc
        adc bcb
        sta tcp
        lda tcp+1
        adc bcb+1
        sta tcp+1
.repeat 8, K                      ; slot = (cell & mask) | bits
        ldy #K
        lda (tcp),y
        and (cp),y
        ora (sprp),y
        sta (slp),y
.endrepeat
        jmp @col
@have:  tax
        dex                       ; X = slot
        lda SLOTLO,x
        sta slp
        lda SLOTHI,x
        sta slp+1
.repeat 8, K                      ; slot = (slot & mask) | bits
        ldy #K
        lda (slp),y
        and (cp),y
        ora (sprp),y
        sta (slp),y
.endrepeat
@col:   ldy tmp2                  ; body pixels here: the cell takes the colour
        lda VSPR_X,y
        lsr
        bcc :+
        lda sfg
        ora #8
        sta SLOTFG,x
:       rts

; prep_sprites (once): VSPR_X bit 1 = the cell has any figure pixels
prep_sprites:
        ldx #63
@v:     txa                       ; sp = VSPR + (x>>4)*256 + (x&15)*16
        asl
        asl
        asl
        asl
        sta sp
        txa
        lsr
        lsr
        lsr
        lsr
        clc
        adc #>VSPR
        sta sp+1
        ldy #7
@b:     lda (sp),y                ; bitmap all 0
        bne @ne
        dey
        bpl @b
        ldy #15
@m:     lda (sp),y                ; mask all $ff
        cmp #$ff
        bne @ne
        dey
        cpy #8
        bcs @m
        bcc @nx
@ne:    lda VSPR_X,x
        ora #2
        sta VSPR_X,x
@nx:    dex
        bpl @v
        rts
; ---------------------------------------------------------------------
; emit: characters, screen codes and colours of the hidden frame from the
; back compose buffer plus the figure overlays.
; Each buffer keeps a label per cell (CLS): the code, 0-111, that the
; cell's pattern got the last time the buffer was emitted ($ff = unknown).
; Equal labels mean equal patterns, and the labels travel with the scroll
; copy, so a clean cell only needs REMAP[label]; the first cell with a
; label, redrawn cells and overlay cells go through the hash lookup.
; Codes are given out in the same order as a full rehash would.
; ---------------------------------------------------------------------
emit:
        jsr build_overlays
        lda front
        bne @ha
        lda #CODES                ; screen A shown: build frame B
        sta cbase
        lda #<SCR_B
        sta scrp
        lda #>SCR_B
        sta scrp+1
        lda #<COL_B
        sta colp
        lda #>COL_B
        sta colp+1
        jmp @go
@ha:    lda #0
        sta cbase
        lda #<SCR_A
        sta scrp
        lda #>SCR_A
        sta scrp+1
        lda #<COL_A
        sta colp
        lda #>COL_A
        sta colp+1
@go:    lda #CODES
        sec
        sbc cbase
        sta obase
        lda #0
        sta next
        tax
@hc:    sta HASH,x
        sta HASH+$80,x
        inx
        bpl @hc
        lda #$ff
        ldx #CODES
@rc:    sta REMAP-1,x
        dex
        bne @rc
        lda bkcls
        sta clsp
        lda bkcls+1
        sta clsp+1
        lda bkcc
        sta tcc
        lda bkcc+1
        sta tcc+1
        lda #<OV
        sta ovp
        lda #>OV
        sta ovp+1
        lda #0
        sta chunk
        sta lim                   ; cells 0-255 first
        tay

@cell:  lda (ovp),y
        bne @ovl
        lda (clsp),y
        bmi @look                 ; redrawn: look it up
        tax
        lda REMAP,x
        bmi @first                ; first cell with this label
@code:  sta (clsp),y              ; A = code - cbase
        clc
        adc cbase
        sta (scrp),y
        lda (tcc),y
@col:   sta (colp),y
        iny
        cpy lim
        bne @cell
        lda chunk
        bne @end
        inc chunk                 ; then cells 256-395
        lda #<(VP_CELLS-256)
        sta lim
        inc ovp+1
        inc clsp+1
        inc tcc+1
        inc scrp+1
        inc colp+1
        jmp @cell

@first: stx ccx                   ; old label = code in the shown half:
        sty ysave                 ; same pattern, hash already known
        txa
        clc
        adc obase
        tay
        lda chlo,y
        sta cp
        lda chhi,y
        sta cp+1
        ldx HV,y
        jsr lookup_h
        ldy ysave
        bcs @ovf
        ldx ccx
        sta REMAP,x
        jmp @code
@look:  jsr cell_lookup
        bcc @code
@ovf:   lda #$ff                  ; out of characters: reuse the first one
        sta (clsp),y
        lda cbase
        sta (scrp),y
        lda (tcc),y
        jmp @col

@ovl:   tax                       ; figure overlay slot
        dex
        lda SLOTLO,x
        sta cp
        lda SLOTHI,x
        sta cp+1
        lda SLOTFG,x
        sta ccolv
        lda (clsp),y              ; the composed cell keeps its label only
        bmi :+                    ; if it already has a code this frame
        tax
        lda REMAP,x
        sta (clsp),y
:       sty ysave
        jsr lookup
        ldy ysave
        bcc :+
        lda #0
:       clc
        adc cbase
        sta (scrp),y
        lda ccolv
        jmp @col

@end:   ldx nslot                 ; clear the overlay table for next time
        beq @done
@clr:   dex
        lda SLOTCELL,x
        sta ovp                   ; OV is page aligned
        lda SLOTCELLH,x
        clc
        adc #>OV
        sta ovp+1
        lda #0
        tay
        sta (ovp),y
        cpx #0
        bne @clr
@done:  rts

; cell_lookup: lookup of composed cell chunk*256+Y; keeps Y
cell_lookup:
        sty ysave
        lda chunk                 ; cp = bcb + cell*8
        sta cp+1
        tya
        asl
        rol cp+1
        asl
        rol cp+1
        asl
        rol cp+1
        clc
        adc bcb
        sta cp
        lda cp+1
        adc bcb+1
        sta cp+1
        jsr lookup
        ldy ysave
        rts

; lookup: the 8 bytes at (cp) -> A = code - cbase, C = 0; C = 1 when all
; CODES characters are taken by other patterns. New patterns are copied
; into the character set.
lookup:
        ldy #0                    ; hash = sum of the 8 bytes
        clc
        lda (cp),y
.repeat 7, K
        ldy #(K+1)
        adc (cp),y
.endrepeat
        tax
lookup_h:                         ; X = hash of (cp)
        stx hsave
@probe: lda HASH,x
        beq @new
        sta tmp2                  ; candidate code - cbase + 1
        clc
        adc cbase
        tay
        lda chlo-1,y
        sta chp
        lda chhi-1,y
        sta chp+1
.repeat 8, K
        ldy #K
        lda (cp),y
        cmp (chp),y
        bne @miss
.endrepeat
        ldx tmp2
        dex
        txa
        clc
        rts
@miss:  inx
        jmp @probe
@new:   lda next
        cmp #CODES
        bcs @full
        inc next
        sta tmp2
        adc #1                    ; (C = 0)
        sta HASH,x
        lda tmp2
        adc cbase
        tay
        lda hsave
        sta HV,y
        lda chlo,y
        sta chp
        lda chhi,y
        sta chp+1
.repeat 8, K
        ldy #K
        lda (cp),y
        sta (chp),y
.endrepeat
        lda tmp2
        clc
@full:  rts

; ---------------------------------------------------------------------
; flip: below the viewport, show the hidden frame
; ---------------------------------------------------------------------
flip:
@w:     lda VIC_RAST
        cmp #FLIP_RAST
        bne @w
        lda front
        eor #1
        sta front
        beq @a
        lda #(VP_COLS|$80)        ; screen B, colour RAM $9600
        sta VIC_COLS
        jmp swap_cb
@a:     lda #VP_COLS              ; screen A, colour RAM $9400
        sta VIC_COLS
        jmp swap_cb

; ---------------------------------------------------------------------
; get_move: one step per key press or joystick push.
;   Keyboard: same keys as the C64 (common/game.s key_step).
;   Joystick (map axes, as on the C64): up = y-1, down = y+1, left = x-1,
;   right = x+1; diagonals combine both into straight screen moves.
; Returns A = 0 nothing happened, 1 moved, 2 bumped
; ---------------------------------------------------------------------
get_move:
@rel:   jsr read_joy              ; wait for the stick to be released
        bne @rel
@poll:  jsr GETIN                 ; keyboard first
        beq @joy
        jsr key_step
        bcc @joy
        lda #0                    ; drop key repeats queued during the redraw
        sta $c6
        jmp try_move
@joy:   jsr read_joy
        beq @poll
        sta smask
        ldx #0                    ; short settle so diagonals register
@dl:    dex
        bne @dl
        jsr read_joy
        ora smask
        sta smask
        lda px
        sta nx
        lda py
        sta ny
        lsr smask
        bcc :+
        dec ny
:       lsr smask
        bcc :+
        inc ny
:       lsr smask
        bcc :+
        dec nx
:       lsr smask
        bcc :+
        inc nx
:       jmp try_move

; read_joy: A = directions pushed, bit 0 up, 1 down, 2 left, 3 right
; (Z = none). Up/down/left are VIA1 port A bits 2-4; right is VIA2 port B
; bit 7, shared with the keyboard columns, so it is read as an input with
; the KERNAL keyboard scan held off.
read_joy:
        lda $9111
        eor #$ff
        lsr
        lsr
        and #$07
        sta tmp2
        sei
        lda $9122
        tax
        and #$7f
        sta $9122
        ldy $9120
        stx $9122
        cli
        tya
        bmi :+
        lda tmp2
        ora #$08
        rts
:       lda tmp2
        rts

; plat_flash: hit feedback for bump (common/game.s)
plat_flash:
        lda VIC_COL
        pha
        and #$f8
        ora #2                    ; red border
        sta VIC_COL
        ldx #$30
@d1:    ldy #0
@d2:    dey
        bne @d2
        dex
        bne @d1
        pla
        sta VIC_COL
        rts

.include "../common/view.s"
.include "../common/game.s"

; ---------------------------------------------------------------------
.segment "RODATA"

fn_vt:    .byte $56,$54,$49,$4c,$45,$53,$2a             ; "VTILES*"
fn_vt_len = * - fn_vt
fn_vs:    .byte $56,$53,$50,$52,$49,$54,$45,$53,$2a     ; "VSPRITES*"
fn_vs_len = * - fn_vs
fn_map:   .byte $4d,$41,$50,$30,$31,$2a                 ; "MAP01*"
fn_map_len = * - fn_map

cbrowlo:
.repeat VP_ROWS, I
        .byte <(I*VP_COLS*8)
.endrepeat
cbrowhi:
.repeat VP_ROWS, I
        .byte >(I*VP_COLS*8)
.endrepeat
row22lo:
.repeat VP_ROWS, I
        .byte <(I*VP_COLS)
.endrepeat
row22hi:
.repeat VP_ROWS, I
        .byte >(I*VP_COLS)
.endrepeat
bc8lo:                            ; bcol = -3..21: bcol*8 - 2, sign
.repeat 25, I
        .byte <((I-3)*8-2)
.endrepeat
bc8hi:
.repeat 25, I
        .byte >((I-3)*8-2)
.endrepeat
bcsgn:
.repeat 25, I
        .byte >(I-3)
.endrepeat
chlo:
.repeat 224, I
        .byte <(CHARS+I*8)
.endrepeat
chhi:
.repeat 224, I
        .byte >(CHARS+I*8)
.endrepeat

