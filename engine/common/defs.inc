; ISO64 shared map layout. The platform defines MAP (page aligned) and TILES
; before including this file.

TERR      = MAP+$100       ; 32x32 terrain tile ids
HGT       = MAP+$500       ; 32x32 height (bits 0-1) + flags (bit7 blocked)
OBJ       = MAP+$900       ; 32x32 object tile ids
ENTS      = MAP+$d00       ; 32 entities x 8 bytes

M_STARTX  = MAP+$04
M_STARTY  = MAP+$05
M_NENT    = MAP+$06
M_BG      = MAP+$07
M_BORDER  = MAP+$08
M_SLAB    = MAP+$09
M_HEROCOL = MAP+$0a

; entity record offsets
E_TYPE = 0
E_X    = 1
E_Y    = 2
E_SPR  = 3
E_COL  = 4
E_HP   = 5
E_ATK  = 6
E_DEF  = 7

ET_MONSTER = 1
ET_NPC     = 2
ET_ITEM    = 3
ET_TRIGGER = 4
