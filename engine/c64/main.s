; =====================================================================
;  ISO64 engine - C64 platform layer (shared logic in ../common)
;  Isometric multicolor-bitmap renderer, map loader, movement, bump stub
;  Assemble: see build.cmd  (cc65 / ca65)
;
;  Rendering is double buffered. A step copies the previous frame into
;  the hidden buffer shifted by the scroll amount (whole cells), redraws
;  only the newly exposed strip, then flips banks below the viewport.
;
;  REU tier (docs/PLATFORMS.md 4): if an REU answers at $df02-$df05, the
;  whole map is drawn once into REU memory at load and every step just
;  DMA-fetches the viewport window into the hidden buffer instead.
;
;  Data files (made by the browser editor, loaded from sd2iec):
;    TILES   -> $8000   tile graphics
;    SPRITES -> $4400   sprite shapes (copied to $c400 for bank 3)
;    MAP01   -> $4c00   map + entities
;  Formats are documented in docs/DESIGN.md
; =====================================================================

; ---- memory map ------------------------------------------------------
;  $0801-$3dff code        $3e00 COLM  $3f00 ROWM (dirty masks)
;  bank 1: $4000 screen A, $4400 sprites, $4c00 map, $6000 bitmap A
;  $8000-$bfff tiles (BASIC ROM switched out)
;  bank 3: $c000 screen B, $c400 sprites, $c800 colour shadow,
;          $e000 bitmap B (RAM under KERNAL; KERNAL out while drawing)
SCR_A     = $4000
SPR_A     = $4400
MAP       = $4c00
BM_A      = $6000
TILES     = $8000
SCR_B     = $c000
SPR_B     = $c400
SHADOW    = $c800          ; colour RAM image of the frame being drawn
BM_B      = $e000
COLRAM    = $d800
COLM      = $3e00          ; per column: bit0 in viewport, bit1 dirty
ROWM      = $3f00          ; per row:    bit0 in viewport, bit1 dirty

; ---- REU tier --------------------------------------------------------
; World image: screen column c of camera px,py is world column
; c-VP_C0 + 2*(px-py)+62, screen row r is world row r + px+py. That is
; 148 x 82 cells, every viewport window of every px,py in 0..31 inside.
;   $00000 bitmap  82 rows x 1184 bytes (148 cells x 8)
;   $18000 screen  82 rows x 148
;   $1c000 colour  82 rows x 148          total under 128 KB
REU       = $df00
WORLD_W   = 148
WORLD_H   = 82
REU_SCR   = $80            ; hi byte of the screen image in REU bank 1
REU_COL   = $c0            ; hi byte of the colour image in REU bank 1
CMD_STASH = $b0            ; execute, autoload, no $ff00 trigger, C64->REU
CMD_FETCH = $b1            ;                                     REU->C64
reu       = $60            ; 1 = REU tier
wcol      = $61            ; world column of screen column VP_C0
wrow      = $62            ; world row of screen row VP_R0
w8lo      = $63            ; wcol*8
w8hi      = $64
rcmd      = $65
rpage     = $66
rhi       = $67
wbi       = $68
first     = $69            ; 0 until the first frame is drawn
fcol      = $6a            ; window runs: first screen column (8; 7 when
fc8       = $6b            ;   scrolling), fcol*8, cells per run, cells*8,
fn        = $6c            ;   first screen row, last screen row + 1
fn8       = $6d
fr0       = $6e
fr1       = $6f
; smooth scrolling (REU tier)
rx        = $70            ; camera offset still to go: hires pixels (signed)
ry        = $71            ;                            raster lines (signed)
xs        = $72            ; $d016 fine scroll 0-7 of the frame being built
ys        = $73            ; $d011 fine scroll 0-7 (3 = at rest)
sxs       = $74            ; per-frame steps of rx, ry, hy8
sys       = $75
hst       = $76
hy8       = $77            ; hero sprite y offset still to go, 1/8 lines
hyn       = $78            ; hero sprite y at the new position
wc0       = $79            ; wcol/wrow of the new camera
wr0       = $7a
m7        = $7b            ; bitmap masks of the partial columns 7 and 31
m31       = $7c
zz        = $7d            ; partial rows: top keeps lines zz-7, bottom 0..zz-1
ztr       = $7e            ; top partial row (0 or 1; bottom = ztr+18)
ncand     = $7f            ; entities that can show during this step
slot      = $80
ssh       = $81            ; scroll speed: 1<<ssh fine steps per frame
lcw       = $82            ; window whose colours are in colour RAM
lcr       = $83
lc0       = $84
lc1       = $85
zv        = $86            ; 2 bytes: jump vector
SCROLL_SH = 1              ; default ssh: 2 fine steps (4 pixels / 2 lines)
SFLIP_LINE = 250           ; scroll frames flip in the lower border, where
                           ; $d011 can change without making a badline

.include "../common/defs.inc"

; ---- viewport (in character cells) ----------------------------------
VP_C0      = 8
VP_C1      = 31
VP_R0      = 1
VP_R1      = 18
VP_ROWS    = VP_R1-VP_R0+1
CENTER_COL = 18            ; left cell column of the player's tile
CENTER_ROW = 8             ; top cell row of the player's ground diamond
SPR_BASE   = (SPR_A-$4000)/64   ; same value in bank 3 ($c400)
FLIP_LINE  = 210           ; raster line just below the viewport

; ---- KERNAL ----------------------------------------------------------
SETLFS = $ffba
SETNAM = $ffbd
LOAD   = $ffd5
GETIN  = $ffe4

.include "../common/zp.inc"

.segment "CODE"

start:
        lda #$36                  ; BASIC ROM out: tiles use RAM $a000-$bfff
        sta $01
        lda #0
        sta $d020
        sta $d021

        lda #fn_tiles_len
        ldx #<fn_tiles
        ldy #>fn_tiles
        jsr load_file
        lda #fn_spr_len
        ldx #<fn_spr
        ldy #>fn_spr
        jsr load_file
        lda #fn_map_len
        ldx #<fn_map
        ldy #>fn_map
        jsr load_file

        ldx #0                    ; sprite shapes for bank 3
@sc:    lda SPR_A,x
        sta SPR_B,x
        lda SPR_A+$100,x
        sta SPR_B+$100,x
        lda SPR_A+$200,x
        sta SPR_B+$200,x
        lda SPR_A+$300,x
        sta SPR_B+$300,x
        inx
        bne @sc

        jsr init_vic
        lda #SCROLL_SH
        sta ssh
        jsr reu_detect
        beq @stock
        jsr world_build           ; REU tier: pre-render the map once
@stock: lda M_STARTX
        sta px
        lda M_STARTY
        sta py
        jsr render_step
        jsr flip
        jsr place_sprites

main_loop:
        jsr get_move              ; A: 0 nothing, 1 moved, 2 bumped
        beq main_loop
        cmp #1
        bne @spr
        lda reu
        beq @stk
        jsr reu_walk              ; REU tier: scroll there, sprites included
        jmp main_loop
@stk:   jsr render_step
        jsr flip
@spr:   jsr place_sprites
        jmp main_loop

; the next frame into the back buffer: REU fetch, or (stock) the first
; frame drawn in full and later ones scrolled
render_step:
        lda reu
        beq :+
        jmp reu_view
:
        lda first
        beq :+
        jmp render_scroll
:       inc first
        jmp render_full

; ---------------------------------------------------------------------
; load_file: A=name length, X/Y=name address. Loads to the file's own
; load address from the current device (sd2iec), default 8.
; ---------------------------------------------------------------------
load_file:
        jsr SETNAM
        lda #1
        ldx $ba
        cpx #8
        bcs :+
        ldx #8
:       ldy #1
        jsr SETLFS
        lda #0
        jsr LOAD
        bcs load_err
        rts
load_err:
        inc $d020                 ; flashing border = file missing
        jmp load_err

; ---------------------------------------------------------------------
init_vic:
        lda $dd02
        ora #$03
        sta $dd02
        lda $dd00
        and #$fc
        ora #$02                  ; show bank 1 first
        sta $dd00
        lda #0
        sta front
        sta first
        lda #>BM_A
        sta frbm
        lda #>SCR_A
        sta frscr
        lda #>BM_B
        sta bkbm
        lda #>SCR_B
        sta bkscr
        lda #$08                  ; screen at +$0000, bitmap at +$2000
        sta $d018
        lda #$3b                  ; bitmap mode, display on
        sta $d011
        lda #$18                  ; multicolor, 40 columns
        sta $d016
        lda M_BG
        sta $d021
        lda M_BORDER
        sta $d020

        lda #>BM_A
        ldx #$20
        jsr clear_pages
        lda #>BM_B
        ldx #$20
        jsr clear_pages
        lda #>SCR_A
        ldx #4
        jsr clear_pages
        lda #>SCR_B
        ldx #4
        jsr clear_pages
        lda #>SHADOW
        ldx #4
        jsr clear_pages
        lda #>COLRAM
        ldx #4
        jsr clear_pages
        lda #>COLM
        ldx #2
        jsr clear_pages
        lda #<nmi_rti             ; RESTORE while the KERNAL is banked out
        sta $fffa
        lda #>nmi_rti
        sta $fffb

        lda #0
        sta $d025                 ; sprite multicolor 1: black outline
        sta $d017
        sta $d01d
        sta $d01b
        sta $d010
        lda #10
        sta $d026                 ; sprite multicolor 2: skin
        lda #$ff
        sta $d01c
        rts
nmi_rti:
        rti

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
; render_full: whole viewport into the back buffer
; render_scroll: shift the front frame into the back buffer by the last
; step, then redraw only the exposed strip(s)
; Both leave IRQs off and the KERNAL out; flip restores them.
; ---------------------------------------------------------------------
render_full:
        sei
        lda #$35
        sta $01
        jsr view_clear
        jmp draw_all

; whole viewport dirty, and cleared in the back buffer
view_clear:
        jsr view_full
        lda #VP_C0
        sta rc0
        lda #VP_C1
        sta rc1
        lda #VP_R0
        sta rr0
        lda #VP_R1
        sta rr1
        jmp clear_rect

render_scroll:
        sei
        lda #$35
        sta $01
        jsr view_scroll           ; dcol/drow, dirty strips, bounds
        jsr scroll_copy
        jsr clear_dirty
        jmp draw_all

; clear cells rc0..rc1 x rr0..rr1 of the back buffer (bitmap, screen, shadow)
clear_rect:
        ldx rr0
@r:     lda rc0
        asl
        asl
        asl
        clc
        adc row320lo,x
        sta bp
        lda row320hi,x
        adc bkbm
        sta bp+1
        lda rc1
        sec
        sbc rc0
        clc
        adc #1
        asl
        asl
        asl
        tay
        lda #0
@b:
.repeat 8
        dey
        sta (bp),y
.endrepeat
        cpy #0
        bne @b
        lda rc0
        clc
        adc row40lo,x
        sta scp
        sta clp
        lda row40hi,x
        adc #0
        pha
        clc
        adc bkscr
        sta scp+1
        pla
        clc
        adc #>SHADOW
        sta clp+1
        lda rc1
        sec
        sbc rc0
        tay
        lda #0
@s:     sta (scp),y
        sta (clp),y
        dey
        bpl @s
        cpx rr1
        beq @done
        inx
        jmp @r
@done:  rts

; ---------------------------------------------------------------------
; scroll_copy: front -> back, shifted by dcol/drow cells.
; Three 18-row copiers (bitmap, screen, colour) whose operands are
; patched per frame; one pass of X copies the same byte of every row.
; Rows whose source falls outside the viewport copy a clamped row; they
; are dirty and get cleared afterwards.
; ---------------------------------------------------------------------
scroll_copy:
        lda dcol
        bmi @neg
        clc
        adc #VP_C0
        sta cA                    ; first destination column
        lda #VP_C0
        sta cS                    ; first source column
        lda dcol
        jmp @n
@neg:   lda #VP_C0
        sta cA
        sec
        sbc dcol
        sta cS
        lda #0
        sec
        sbc dcol
@n:     sta tmp                   ; |dcol|
        lda #(VP_C1-VP_C0+1)
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
        sec
        sbc #1
        sta s8
        lda cA
        asl
        asl
        asl
        sec
        sbc #1
        sta d8
        ldx cS
        dex
        stx s1
        ldx cA
        dex
        stx d1

        ldx #VP_R0                ; destination row
        lda #0
        sta r6
@pl:    txa                       ; source row = clamp(row - drow, 1, 18)
        sec
        sbc drow
        bmi @lo
        cmp #VP_R0
        bcc @lo
        cmp #(VP_R1+1)
        bcc @ok
        lda #VP_R1
        bne @ok
@lo:    lda #VP_R0
@ok:    sta srow
        ldy r6
        ; bitmap: src = frbm + row320[srow] + cS*8 - 1, dst likewise
        stx tmp
        ldx srow
        lda row320lo,x
        clc
        adc s8
        sta bmc_body+1,y
        lda row320hi,x
        adc frbm
        sta bmc_body+2,y
        lda row40lo,x
        clc
        adc s1
        sta scc_body+1,y
        sta clc_body+1,y
        lda row40hi,x
        adc #0
        sta tmp2
        adc frscr
        sta scc_body+2,y
        lda tmp2
        clc
        adc #>COLRAM
        sta clc_body+2,y
        ldx tmp
        lda row320lo,x
        clc
        adc d8
        sta bmc_body+4,y
        lda row320hi,x
        adc bkbm
        sta bmc_body+5,y
        lda row40lo,x
        clc
        adc d1
        sta scc_body+4,y
        sta clc_body+4,y
        lda row40hi,x
        adc #0
        sta tmp2
        adc bkscr
        sta scc_body+5,y
        lda tmp2
        clc
        adc #>SHADOW
        sta clc_body+5,y
        lda r6
        clc
        adc #6
        sta r6
        inx
        cpx #(VP_R1+1)
        beq :+
        jmp @pl
:       ldx nbytes
        jsr bmc_body
        ldx ncell
        jsr scc_body
        ldx ncell
        jmp clc_body

; operands of row R sit at body+R*6+1 (source) and body+R*6+4 (dest)
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
scc_body: ROWCOPY
clc_body: ROWCOPY

; =====================================================================
;  REU tier
; =====================================================================

; reu_detect: Z clear and reu = 1 if the REU registers hold two test
; patterns (a stock C64 reads open bus at $df00-$dfff)
reu_detect:
        lda #0
        sta reu
        lda #$a5
        jsr @try
        bne @no
        lda #$5a
        jsr @try
        bne @no
        lda #0
        sta REU+9                 ; no REU interrupts
        sta REU+10                ; both addresses count up
        lda #1
        sta reu
@no:    lda reu
        rts
@try:   sta tmp                   ; A = pattern: write $df02-$df05, read back
        ldx #3
@w:     txa
        eor tmp
        sta REU+2,x
        dex
        bpl @w
        ldx #3
@r:     txa
        eor tmp
        cmp REU+2,x
        bne @x
        dex
        bpl @r
        lda #0
@x:     rts

; reu_win: world column/row of the viewport's top-left cell for px,py
reu_win:
        lda px
        sec
        sbc py
        asl
        clc
        adc #62
        sta wcol
        ldx #0
        stx w8hi
        asl
        rol w8hi
        asl
        rol w8hi
        asl
        rol w8hi
        sta w8lo
        lda px
        clc
        adc py
        clc
        adc #VP_R0
        sta wrow
        lda #VP_C0                ; runs cover the viewport
        sta fcol
        lda #(VP_C0*8)
        sta fc8
        lda #(VP_C1-VP_C0+1)
        sta fn
        lda #((VP_C1-VP_C0+1)*8)
        sta fn8
        lda #VP_R0
        sta fr0
        lda #(VP_R1+1)
        sta fr1
        rts

; reu_view: one step = DMA the viewport window into the back buffer
; (bitmap and screen; colour RAM is fetched by flip). Leaves IRQs off and
; the KERNAL out like render_scroll.
reu_view:
        sei
        lda #$35
        sta $01
        jsr reu_win
        lda #CMD_FETCH
        jsr reu_bmp
        lda #CMD_FETCH
        ldx bkscr
        ldy #REU_SCR
        jmp reu_chr

; reu_bmp: A = command; bitmap row runs of fn8 bytes between the back
; buffer (screen rows fr0..fr1-1 from column fcol) and world rows wrow..,
; starting at byte wcol*8 of each
reu_bmp:
        sta rcmd
        lda fn8
        sta REU+7
        lda #0
        sta REU+8
        ldx fr0
        ldy wrow
@r:     lda row320lo,x
        clc
        adc fc8
        sta REU+2
        lda row320hi,x
        adc bkbm
        sta REU+3
        lda w1184lo,y
        clc
        adc w8lo
        sta REU+4
        lda w1184mi,y
        adc w8hi
        sta REU+5
        lda w1184hi,y
        adc #0
        sta REU+6
        lda rcmd
        sta REU+1                 ; the CPU halts while the REU transfers
        iny
        inx
        cpx fr1
        bne @r
        rts

; reu_chr: A = command, X = C64 page (screen, shadow or colour RAM),
; Y = REU_SCR or REU_COL; row runs of fn bytes, rows and columns as reu_bmp
reu_chr:
        sta rcmd
        stx rpage
        sty rhi
        lda fn
        sta REU+7
        lda #0
        sta REU+8
        lda #1
        sta REU+6
        ldx fr0
        ldy wrow
@r:     lda row40lo,x
        clc
        adc fcol
        sta REU+2
        lda row40hi,x
        adc rpage
        sta REU+3
        lda w148lo,y
        clc
        adc wcol
        sta REU+4
        lda w148hi,y
        adc rhi
        sta REU+5
        lda rcmd
        sta REU+1
        iny
        inx
        cpx fr1
        bne @r
        rts

; ---------------------------------------------------------------------
; world_build: draw the whole map once into the REU. The world image is
; tiled with 7 x 5 viewport windows (world columns 0,24,..,120,124 and
; rows 0,18,36,54,64); each is drawn into the back buffer by the normal
; draw code with the camera there, then stashed. A clipped viewport
; render is exactly a window of the unclipped world, so any window
; fetched later matches a direct render. The cameras may lie off the
; map (draw_world, unlike draw_all, copes). The border counts windows.
; ---------------------------------------------------------------------
world_build:
        sei
        lda #$35
        sta $01
        ldx #0
@w:     stx wbi
        stx $d020
        lda wb_px,x
        sta px
        lda wb_py,x
        sta py
        jsr view_clear
        jsr draw_world
        jsr reu_win
        lda #CMD_STASH
        jsr reu_bmp
        lda #CMD_STASH
        ldx bkscr
        ldy #REU_SCR
        jsr reu_chr
        lda #CMD_STASH
        ldx #>SHADOW
        ldy #REU_COL
        jsr reu_chr
        ldx wbi
        inx
        cpx #WB_N
        bne @w
        lda M_BORDER
        sta $d020
        lda #$36
        sta $01
        cli
        rts

; draw_world: every map cell whose tiles can reach the viewport, back to
; front: per ty, the tx with k = (tx-px)-(ty-py) in KLO..KHI and
; s = (tx-px)+(ty-py) in SLO..SHI. Like draw_all, but without its clamp
; on py, so the camera may be off the map (bounds biased +64; every value
; stays in 24..146 for the world_build cameras).
draw_world:
        lda #0
        sta ty
@yl:    lda px
        sec
        sbc py
        clc
        adc ty
        clc
        adc #64
        sta tmp                   ; 64 + ty + px-py
        lda px
        clc
        adc py
        sec
        sbc ty
        clc
        adc #64
        sta tmp2                  ; 64 + px+py - ty
        lda tmp                   ; tx from max(k lower, s lower, 0)
        clc
        adc #<KLO
        sta xlob
        lda tmp2
        clc
        adc #<SLO
        cmp xlob
        bcc :+
        sta xlob
:       lda xlob
        cmp #64
        bcs :+
        lda #64
        sta xlob
:       lda tmp                   ; to min(k upper, s upper, 31)
        clc
        adc #KHI
        sta xhib
        lda tmp2
        clc
        adc #SHI
        cmp xhib
        bcs :+
        sta xhib
:       lda xhib
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
@next:  inc ty
        lda ty
        cmp #32
        bne @yl
        rts

; =====================================================================
;  REU tier: smooth scrolling (docs/PLATFORMS.md 4)
;
;  reu_walk animates the step just taken (mvdx/mvdy; px/py have already
;  moved) at 1<<ssh fine steps per frame: one fine step is 2 hires
;  pixels across and 1 line down, so a straight step takes 16 frames
;  and a diagonal one 8 (half that at ssh = 1). Every frame DMAs the
;  window at the camera position into the back buffer, masks the cells
;  the fine scroll pushes across the viewport edge, and flips at
;  SFLIP_LINE with new $d016/$d011 fine scroll and sprites.
;
;  rx/ry = how far the camera still is from the new position (camera
;  pixel = new*8 - r). With W'/R' = the world column/row shown in screen
;  column 8 / row 1 and the picture shifted right xs, down ys-3:
;    xs = rx & 7          W' = wc0 - (rx >> 3)
;    ys = (ry+3) & 7      R' = wr0 - ((ry+3) >> 3)
;  The fetch covers columns 7-31 (world W'-1..) and the rows that show.
;
;  Edge mask: the viewport is cells 8-31 x 1-18, inside the screen, so
;  the 38-column / 24-row border modes don't fit. Instead the back buffer
;  keeps exactly the pixels that land inside the viewport: column 7 its
;  right xs pixels, column 31 its left 8-xs, the top and bottom partial
;  rows their visible lines, everything else zero (background colour).
; =====================================================================
reu_walk:
        sei
        lda #$35
        sta $01
        jsr reu_win               ; window of the new camera
        lda wcol
        sta wc0
        lda wrow
        sta wr0
        lda #$ff
        sta lcw                   ; colour RAM needs a fetch
        lda mvdx                  ; rx = 16*(mvdx-mvdy) = 8 * cell columns
        sec
        sbc mvdy
        asl
        asl
        asl
        asl
        sta rx
        lda mvdx                  ; ry = 8*(mvdx+mvdy) = 8 * cell rows
        clc
        adc mvdy
        asl
        asl
        asl
        sta ry
        ldy ssh
        lda spdx,y                ; per frame: rx by 2<<ssh, ry by 1<<ssh
        ldx rx
        jsr sgnmul
        sta sxs
        lda spdy,y
        ldx ry
        jsr sgnmul
        sta sys
        ; hero: y = hyn + hy8/8, hy8 from 64*(h new - h old) down to 0
        lda px
        sta tx
        lda py
        sta ty
        jsr height_at
        sta tmp2
        lda #CENTER_ROW
        sec
        sbc tmp2
        asl
        asl
        asl
        clc
        adc #41
        sta hyn
        lda px
        sec
        sbc mvdx
        sta tx
        lda py
        sec
        sbc mvdy
        sta ty
        jsr height_at
        sta tmp
        lda tmp2
        sec
        sbc tmp                   ; -1..1 (one level at most)
        sta tmp
        asl
        asl
        asl
        asl
        asl
        asl
        sta hy8
        ldy ssh                   ; hst = 64/frames: 4<<ssh straight,
        lda hstr,y                ; 8<<ssh diagonal
        ldx rx
        beq :+
        ldx ry
        beq :+
        lda hdia,y
:       ldx tmp
        jsr sgnmul
        sta hst
        jsr cands
@fr:    lda rx
        sec
        sbc sxs
        sta rx
        lda ry
        sec
        sbc sys
        sta ry
        lda hy8
        sec
        sbc hst
        sta hy8
        jsr sframe
        lda rx
        ora ry
        bne @fr
        lda #$36
        sta $01
        cli
        rts

; A = |n|, X = sign source: A, -A or 0
sgnmul: cpx #0
        beq @z
        bpl @p
        eor #$ff
        clc
        adc #1
@p:     rts
@z:     lda #0
        rts

; A = A >> 3, signed
asr3:   cmp #$80
        ror
        cmp #$80
        ror
        cmp #$80
        ror
        rts

; cands: entities that can be on screen during the step (stock rule
; widened by the scroll: columns 4-32, rows -1..20), at the new camera:
; cx2 = sprite x / 2, cy = sprite y
cands:
        lda #0
        sta ncand
        sta ccnt
        lda M_NENT
        beq @d
        sta rcnt
@l:     jsr cand_ent
        lda ccnt
        clc
        adc #8
        sta ccnt
        dec rcnt
        bne @l
@d:     rts

cand_ent:
        ldy ccnt
        lda ENTS+E_TYPE,y
        beq @no
        cmp #ET_TRIGGER
        beq @no
        lda ENTS+E_X,y
        sta tx
        lda ENTS+E_Y,y
        sta ty
        jsr height_at
        sta hgt
        lda tx
        sec
        sbc px
        sta nx
        lda ty
        sec
        sbc py
        sta ny
        lda nx
        sec
        sbc ny
        asl
        clc
        adc #CENTER_COL
        sta ccol
        lda nx
        clc
        adc ny
        clc
        adc #CENTER_ROW
        sec
        sbc hgt
        sta crow
        lda ccol
        sec
        sbc #4
        cmp #29
        bcs @no
        lda crow
        clc
        adc #1
        cmp #22
        bcs @no
        ldx ncand
        lda ccol
        asl
        asl
        clc
        adc #14
        sta cx2,x
        lda crow
        asl
        asl
        asl
        clc
        adc #41
        sta cy,x
        ldy ccnt
        lda ENTS+E_SPR,y
        clc
        adc #SPR_BASE
        sta cpt,x
        lda ENTS+E_COL,y
        sta ccl,x
        inc ncand
@no:    rts

; sframe: build the frame for rx/ry in the back buffer, then flip to it
sframe:
        lda rx
        and #7
        sta xs
        lda ry
        clc
        adc #3
        tax
        and #7
        sta ys
        txa
        jsr asr3
        sta tmp
        lda wr0
        sec
        sbc tmp
        sta wrow                  ; R': world row of screen row 1
        lda rx
        jsr asr3
        sta tmp
        lda wc0
        sec
        sbc tmp
        sec
        sbc #1
        sta wcol                  ; W'-1: world column of screen column 7
        ldx #0                    ; (W' = 0 only with xs = 0: column 7 is
        stx w8hi                  ; masked away, any address will do)
        asl
        rol w8hi
        asl
        rol w8hi
        asl
        rol w8hi
        sta w8lo
        lda #7
        sta fcol
        lda #56
        sta fc8
        lda #25
        sta fn
        lda #200
        sta fn8
        lda #0
        sta zz
        lda ys
        cmp #3
        beq @rest
        bcc @up
        lda #0                    ; ys 4-7, picture down 1-4 lines: rows
        sta fr0                   ; 0-18; row 0 keeps lines zz-7, row 18
        sta ztr                   ; lines 0..zz-1
        lda #19
        sta fr1
        lda #11
        sec
        sbc ys
        sta zz
        dec wrow
        jmp @go
@up:    lda #1                    ; ys 0-2, picture up 1-3 lines: rows
        sta ztr                   ; 1-19; row 1 keeps lines zz-7, row 19
        lda #20                   ; lines 0..zz-1
        sta fr1
        lda #3
        sec
        sbc ys
        sta zz
        jmp @r1
@rest:  lda #19                   ; at rest vertically: rows 1-18
        sta fr1
@r1:    lda #1
        sta fr0
@go:    lda #CMD_FETCH
        jsr reu_bmp
        lda #CMD_FETCH
        ldx bkscr
        ldy #REU_SCR
        jsr reu_chr
        lda fr0                   ; rows that don't show at all: zero
        beq :+
        ldx #0
        jsr zrow
:       lda fr1
        cmp #20
        beq :+
        ldx #19
        jsr zrow
:       jsr colmask
        lda zz
        beq :+
        jsr zlines
:       jsr ssprites
        jmp sflip

; zrow: X = screen row; zero its bitmap columns 7-31 in the back buffer
; by DMA, repeating REU byte $00000 (world column 0 is never drawn)
zrow:   lda row320lo,x
        clc
        adc #56
        sta REU+2
        lda row320hi,x
        adc bkbm
        sta REU+3
        lda #0
        sta REU+4
        sta REU+5
        sta REU+6
        sta REU+8
        lda #200
        sta REU+7
        lda #$40                  ; fixed REU address
        sta REU+10
        lda #CMD_FETCH
        sta REU+1
        lda #0
        sta REU+10
        rts

; colmask: AND columns 7 and 31 of every row with m7/m31 for xs
colmask:
        lda xs
        lsr
        tax
        lda rmask,x
        sta m7
        lda lmask,x
        sta m31
        lda bkbm
        cmp #>BM_A
        beq @a
        lda #<cm_b
        ldx #>cm_b
        bne @s
@a:     lda #<cm_a
        ldx #>cm_a
@s:     sta zv
        stx zv+1
        ldy #7
@l:     jsr jzv
        dey
        bpl @l
        rts
jzv:    jmp (zv)

; zlines: zero lines 0..zz-1 of row ztr and lines zz..7 of row ztr+18
zlines:
        lda ztr
        asl
        ldx bkbm
        cpx #>BM_A
        beq :+
        ora #8
:       tay
        lda zltab,y
        sta zv
        lda zltab+1,y
        sta zv+1
        sty tmp
        lda #0
        tax
@t:     jsr jzv
        inx
        cpx zz
        bne @t
        ldy tmp
        lda zltab+4,y
        sta zv
        lda zltab+5,y
        sta zv+1
        lda #0
        ldx zz
@b:     jsr jzv
        inx
        cpx #8
        bne @b
        rts

; ssprites: hero and entity sprites for this frame into the shadow
ssprites:
        lda #(CENTER_COL*8+28)
        sta shx
        lda hy8
        jsr asr3
        clc
        adc hyn
        sta shy
        lda M_HEROCOL
        sta shc
        lda #SPR_BASE
        sta shp
        lda #1
        sta smk
        sta slot
        lda rx
        cmp #$80
        ror
        sta tmp                   ; rx/2: sprite x moves with the world
        ldx #0
@l:     cpx ncand
        beq @d
        ldy slot
        cpy #8
        beq @d
        lda cx2,x
        clc
        adc tmp
        cmp #46                   ; x 92..252, y 49..185: the stock rule
        bcc @n                    ; (columns 8-28, rows 1-18) in pixels
        cmp #127
        bcs @n
        asl
        sta shx,y
        lda cy,x
        clc
        adc ry
        cmp #49
        bcc @n
        cmp #186
        bcs @n
        sta shy,y
        lda cpt,x
        sta shp,y
        lda ccl,x
        sta shc,y
        lda smk
        ora bitmask,y
        sta smk
        inc slot
@n:     inx
        jmp @l
@d:     rts

; sflip: in the lower border show the back buffer with its fine scroll
; and sprites; colour RAM is fetched only when the window moved
sflip:
@w:     lda $d012
        cmp #SFLIP_LINE
        bne @w
        lda front
        eor #1
        sta front
        beq @a
        lda $dd00                 ; bank 3
        and #$fc
        sta $dd00
        jmp @sw
@a:     lda $dd00                 ; bank 1
        and #$fc
        ora #$02
        sta $dd00
@sw:    lda frbm
        ldx bkbm
        sta bkbm
        stx frbm
        lda frscr
        ldx bkscr
        sta bkscr
        stx frscr
        lda xs
        ora #$18
        sta $d016
        lda ys
        ora #$38
        sta $d011
.repeat 8, I
        lda shx+I
        sta $d000+I*2
        lda shy+I
        sta $d001+I*2
        lda shc+I
        sta $d027+I
        lda shp+I
        sta SCR_A+$3f8+I
        sta SCR_B+$3f8+I
.endrepeat
        lda smk
        sta $d015
        lda wcol
        cmp lcw
        bne @c
        lda wrow
        cmp lcr
        bne @c
        lda fr0
        cmp lc0
        bne @c
        lda fr1
        cmp lc1
        beq sflip_done
@c:     lda wcol
        sta lcw
        lda wrow
        sta lcr
        lda fr0
        sta lc0
        lda fr1
        sta lc1
        lda #CMD_FETCH
        ldx #>COLRAM
        ldy #REU_COL
        jsr reu_chr
sflip_done:
        rts

; column masks: Y = cell line; rows 0-19 of columns 7 and 31
.macro COLMASK B
.repeat 20, R
        lda B+R*320+56,y
        and m7
        sta B+R*320+56,y
        lda B+R*320+248,y
        and m31
        sta B+R*320+248,y
.endrepeat
        rts
.endmacro
cm_a:   COLMASK BM_A
cm_b:   COLMASK BM_B

; line zeroing: A = 0, X = cell line; columns 7-31 of one row
.macro ZLINE B, R
.repeat 25, K
        sta B+R*320+56+K*8,x
.endrepeat
        rts
.endmacro
zl_a0:  ZLINE BM_A, 0
zl_a1:  ZLINE BM_A, 1
zl_a18: ZLINE BM_A, 18
zl_a19: ZLINE BM_A, 19
zl_b0:  ZLINE BM_B, 0
zl_b1:  ZLINE BM_B, 1
zl_b18: ZLINE BM_B, 18
zl_b19: ZLINE BM_B, 19

; ---------------------------------------------------------------------
; flip: at the raster line below the viewport, show the back buffer and
; copy the colour shadow into colour RAM before the beam returns.
; ---------------------------------------------------------------------
flip:
@w:     lda $d012
        cmp #FLIP_LINE
        bne @w
        lda front
        eor #1
        sta front
        beq @a
        lda $dd00                 ; bank 3
        and #$fc
        sta $dd00
        jmp @sw
@a:     lda $dd00                 ; bank 1
        and #$fc
        ora #$02
        sta $dd00
@sw:    lda frbm
        ldx bkbm
        sta bkbm
        stx frbm
        lda frscr
        ldx bkscr
        sta bkscr
        stx frscr
        lda reu
        beq @sh
        lda #CMD_FETCH            ; REU tier: colour RAM straight from the
        ldx #>COLRAM              ; world image (no shadow copy)
        ldy #REU_COL
        jsr reu_chr
        jmp @out
@sh:    ldx #(VP_C1-VP_C0)
@c:
.repeat VP_ROWS, R
        lda SHADOW+(VP_R0+R)*40+VP_C0,x
        sta COLRAM+(VP_R0+R)*40+VP_C0,x
.endrepeat
        dex
        bmi @out
        jmp @c
@out:   lda #$36
        sta $01
        cli
        rts

; ---------------------------------------------------------------------
; draw_tile: A = tile id (1-127), trow = ground row, bcol = left column
; Tile is bottom-aligned: its last 2 cell rows are the floor diamond.
; Record: h, flags, h*4 cell pointers (0 = empty), cell data.
; Only cells that are in the viewport and dirty are visited.
; ---------------------------------------------------------------------
draw_tile:
        asl
        tay
        lda TILES+1,y
        sta sp
        lda TILES+2,y
        sta sp+1
        ldy #0
        lda (sp),y                ; height in cells
        sta rcnt
        lda trow
        clc
        adc #2
        sec
        sbc rcnt
        sta crow
        ; colon = columns (bit C) on screen, coldt = columns on screen + dirty
        ldx bcol
        ldy #0
        sty colon
        sty coldt
.repeat 4, C
        lda COLM+C,x
        lsr
        bcc :+
        pha
        lda colon
        ora #(1<<C)
        sta colon
        pla
        lsr
        bcc :+
        lda coldt
        ora #(1<<C)
        sta coldt
:
.endrepeat
        lda colon
        bne :+
        rts                       ; no column on screen
:       lda bcol
        asl
        asl
        asl
        sta bc8                   ; bcol*8 (bcol is 5..31 here)
        ldy #2                    ; offset of the first cell pointer
@row:   ldx crow
        lda ROWM,x
        lsr
        bcc @skiprow              ; row off screen
        lsr
        lda coldt                 ; clean row: dirty columns only
        bcc :+
        lda colon                 ; dirty row: every column on screen
:       sta cols
        bne @base
@skiprow:
        tya
        clc
        adc #8
        tay
        jmp @next
@base:  lda bc8                   ; row base pointers in the back buffer:
        clc                       ; rbp = bitmap - 3 (cell byte k of column
        adc row320lo,x            ; C is written with index C*8+3+k, which
        sta rbp                   ; is also its index in the cell data once
        lda row320hi,x            ; cp is set to the pointer - C*8)
        adc bkbm
        sta rbp+1
        lda rbp
        sec
        sbc #3
        sta rbp
        bcs :+
        dec rbp+1
:       lda bcol
        clc
        adc row40lo,x
        sta rsp
        sta rhp
        lda row40hi,x
        adc #0
        tax
        adc bkscr
        sta rsp+1
        txa
        clc
        adc #>SHADOW
        sta rhp+1
.repeat 4, C
        lsr cols
        bcs :+
        jmp .ident(.sprintf("@nc%d", C))
:       lda (sp),y                ; cell pointer, 0 = empty
        iny
        ora (sp),y
        bne :+
        dey
        jmp .ident(.sprintf("@nc%d", C))
:       dey
        lda (sp),y
        sec
        sbc #(C*8)
        sta cp
        iny
        lda (sp),y
        sbc #0
        sta cp+1
        dey
        sty ysave
        ; cell: type (1 opaque, 2 masked + colours, 3 masked keep colours),
        ; scr byte, colour byte, 8 bitmap bytes, 8 mask bytes
        ldy #(C*8)
        lda (cp),y
        cmp #3
        beq :+
        ldy #(C*8+1)
        lda (cp),y
        ldy #C
        sta (rsp),y
        ldy #(C*8+2)
        lda (cp),y
        ldy #C
        sta (rhp),y
        ldy #(C*8)
        lda (cp),y
:       ldy #(C*8+3)
        cmp #1
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
        iny
.endrepeat
@next:  inc crow
        dec rcnt
        beq @out
        jmp @row
@out:   rts

; ---------------------------------------------------------------------
; place_sprites: hero = sprite 0, visible entities = sprites 1-7
; sprite x = col*8+28, y = row*8+41 (feet on the diamond centre)
; Pointers go to both screens so either bank shows the same sprites.
; ---------------------------------------------------------------------
place_sprites:
        lda px
        sta tx
        lda py
        sta ty
        jsr height_at
        sta tmp2
        lda #CENTER_ROW
        sec
        sbc tmp2
        asl
        asl
        asl
        clc
        adc #41
        sta $d001
        lda #(CENTER_COL*8+28)
        sta $d000
        lda #SPR_BASE
        sta SCR_A+$3f8
        sta SCR_B+$3f8
        lda M_HEROCOL
        sta $d027
        lda #1
        sta smask
        sta lvl                   ; next free sprite
        lda #0
        sta ccnt                  ; entity offset
        lda M_NENT
        beq @done
        sta rcnt
@el:    jsr place_ent
        lda lvl
        cmp #8
        beq @done
        lda ccnt
        clc
        adc #8
        sta ccnt
        dec rcnt
        bne @el
@done:  lda smask
        sta $d015
        rts

; one entity (offset ccnt) -> next free sprite (lvl) if on screen
place_ent:
        ldy ccnt
        lda ENTS+E_TYPE,y
        beq @no
        cmp #ET_TRIGGER
        bne @go
@no:    rts
@go:
        lda ENTS+E_X,y
        sta tx
        lda ENTS+E_Y,y
        sta ty
        jsr height_at
        sta hgt
        lda tx
        sec
        sbc px
        sta nx
        lda ty
        sec
        sbc py
        sta ny
        lda nx
        sec
        sbc ny
        asl
        clc
        adc #CENTER_COL
        sta ccol
        lda nx
        clc
        adc ny
        clc
        adc #CENTER_ROW
        sec
        sbc hgt
        sta crow
        lda ccol
        sec
        sbc #VP_C0
        cmp #21                   ; cols 8-28 keep x < 256
        bcs @out
        lda crow
        sec
        sbc #VP_R0
        cmp #VP_ROWS
        bcs @out
        lda lvl
        asl
        tax
        lda ccol
        asl
        asl
        asl
        clc
        adc #28
        sta $d000,x
        lda crow
        asl
        asl
        asl
        clc
        adc #41
        sta $d001,x
        ldx lvl
        ldy ccnt
        lda ENTS+E_SPR,y
        clc
        adc #SPR_BASE
        sta SCR_A+$3f8,x
        sta SCR_B+$3f8,x
        lda ENTS+E_COL,y
        sta $d027,x
        lda bitmask,x
        ora smask
        sta smask
        inc lvl
@out:   rts

; ---------------------------------------------------------------------
; get_move: one step per key press or joystick push.
;   Keyboard (screen directions):
;     W / cursor up      up         Q  up-left      E  up-right
;     S / cursor down    down       Z  down-left    C  down-right
;     A / cursor left    left
;     D / cursor right   right
;   Joystick port 2 (map axes): up = y-1, down = y+1, left = x-1,
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
        sta $c6
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

; plat_flash: hit feedback for bump (common/game.s)
plat_flash:
        lda #2
        sta $d020
        ldx #$30
@d1:    ldy #0
@d2:    dey
        bne @d2
        dex
        bne @d1
        lda M_BORDER
        sta $d020
        rts

.include "../common/view.s"
.include "../common/game.s"

; ---------------------------------------------------------------------
.segment "RODATA"

fn_tiles: .byte $54,$49,$4c,$45,$53,$2a             ; "TILES*" (matches TILES and TILES.PRG)
fn_tiles_len = * - fn_tiles
fn_spr:   .byte $53,$50,$52,$49,$54,$45,$53,$2a     ; "SPRITES*"
fn_spr_len = * - fn_spr
fn_map:   .byte $4d,$41,$50,$30,$31,$2a             ; "MAP01*"
fn_map_len = * - fn_map

bitmask:  .byte 1,2,4,8,16,32,64,128

; smooth scrolling: steps per frame by ssh, edge masks by xs/2,
; line-zeroing routines (rows 0, 1, 18, 19 of buffer A, then B)
spdx:     .byte 2,4
spdy:     .byte 1,2
hstr:     .byte 4,8
hdia:     .byte 8,16
rmask:    .byte $00,$03,$0f,$3f       ; column 7: right xs pixels
lmask:    .byte $ff,$fc,$f0,$c0       ; column 31: left 8-xs pixels
zltab:    .word zl_a0,zl_a1,zl_a18,zl_a19,zl_b0,zl_b1,zl_b18,zl_b19

; world_build cameras: window columns d = -31,-19,-7,5,17,29,31 (world
; column 2d+62 = 0,24,..,120,124) x rows s = -1,17,35,53,63 (world row
; s+1); px = (s+d)/2, py = (s-d)/2
WB_N = 35
wb_px:    .lobytes -16,-7,2,11,16, -10,-1,8,17,22, -4,5,14,23,28, 2,11,20,29,34
          .lobytes 8,17,26,35,40, 14,23,32,41,46, 15,24,33,42,47
wb_py:    .lobytes 15,24,33,42,47, 9,18,27,36,41, 3,12,21,30,35, -3,6,15,24,29
          .lobytes -9,0,9,18,23, -15,-6,3,12,17, -16,-7,2,11,16

; REU world row offsets: bitmap row * 1184, screen/colour row * 148
w1184lo:
.repeat WORLD_H, I
        .byte <(I*WORLD_W*8)
.endrepeat
w1184mi:
.repeat WORLD_H, I
        .byte >(I*WORLD_W*8)
.endrepeat
w1184hi:
.repeat WORLD_H, I
        .byte ^(I*WORLD_W*8)
.endrepeat
w148lo:
.repeat WORLD_H, I
        .byte <(I*WORLD_W)
.endrepeat
w148hi:
.repeat WORLD_H, I
        .byte >(I*WORLD_W)
.endrepeat

; cell row offsets (no base: added to the current buffer at run time)
row320lo:
.repeat 25, I
        .byte <(I*320)
.endrepeat
row320hi:
.repeat 25, I
        .byte >(I*320)
.endrepeat
row40lo:
.repeat 25, I
        .byte <(I*40)
.endrepeat
row40hi:
.repeat 25, I
        .byte >(I*40)
.endrepeat

; ---------------------------------------------------------------------
.segment "BSS"

shx:      .res 8                   ; sprite shadow for the next flip
shy:      .res 8
shc:      .res 8
shp:      .res 8
smk:      .res 1
cx2:      .res 32                  ; step candidates (cands)
cy:       .res 32
cpt:      .res 32
ccl:      .res 32
