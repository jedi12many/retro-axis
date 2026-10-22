// =====================================================================
//  C128 80-column target (VDC, preview)
//  Converts the C64 tileset to VDC hi-res cells and renders a map the way
//  engine/c128 does:
//    - VDC bitmap mode, 640x200, attributes on: every 8x8 cell has a
//      foreground and a background colour (attribute byte bg<<4 | fg, as in
//      text mode the low nibble is the foreground) out of the 16 RGBI colours
//    - a C64 multicolour cell (4 double-wide pixels, 4 colours) becomes an
//      8-pixel hi-res cell: the best fg/bg pair per cell, with 2x2 ordered
//      dithering standing in for the other colours
//    - the same 4x2-cell diamond grid as the C64 (a VDC cell is 8 pixels
//      wide, like a multicolour cell), on a 62x25-cell viewport, with a side
//      panel in columns 62-79
//    - no sprites: hero and monsters are soft sprites drawn into the cells
//  Uses globals from the main editor script at call time (PAL, SPRITES, MW).
// =====================================================================
const VDC_PAL=['#000000','#555555','#0000aa','#5555ff','#00aa00','#55ff55','#00aaaa','#55ffff','#aa0000','#ff5555','#aa00aa','#ff55ff','#aa5500','#ffff55','#aaaaaa','#ffffff'];
const VDC_NAME=['black','dark grey','dark blue','light blue','dark green','light green','dark cyan','light cyan','dark red','light red','dark purple','light purple','brown','yellow','light grey','white'];
const C128={cols:80,rows:25,vp:{c0:0,c1:61,r0:0,r1:24},centerCol:29,centerRow:11,panelCol:62};
const CTILES_ADDR=0x9800,CTILES_MAX=0x2800,CSPR_ADDR=0x9100;
const C128_BAYER=[0,2,3,1];   // 2x2 ordered dither: pixel lit when level (0-4) > BAYER[(y&1)*2+(x&1)]

const vdcRgb=h=>[parseInt(h.slice(1,3),16),parseInt(h.slice(3,5),16),parseInt(h.slice(5,7),16)];
// luma + chroma distance: hue counts as much as brightness, so the C64's soft
// greens and browns map to green and brown dithers rather than to greys
const vdcYuv=c=>{const y=.299*c[0]+.587*c[1]+.114*c[2];return[y,c[2]-y,c[0]-y];};
const vdcDist=(p,q)=>{const a=vdcYuv(p),b=vdcYuv(q);return(a[0]-b[0])**2+(a[1]-b[1])**2+(a[2]-b[2])**2;};
const vdcLum=i=>{const c=vdcRgb(VDC_PAL[i]);return .299*c[0]+.587*c[1]+.114*c[2];};
// pairs (bg darker than fg) and, per pair and C64 colour, the best dither level 0-4
let C128_FIT=null;
function c128Fit(){
  if(C128_FIT)return C128_FIT;
  const pairs=[];
  for(let bg=0;bg<16;bg++)for(let fg=0;fg<16;fg++){
    if(vdcLum(fg)<=vdcLum(bg))continue;
    const a=vdcRgb(VDC_PAL[bg]),b=vdcRgb(VDC_PAL[fg]),lvl=[],err=[];
    PAL.forEach(h=>{const q=vdcRgb(h);let bl=0,be=1e18;
      for(let t=0;t<=4;t++){const e=vdcDist([0,1,2].map(k=>(a[k]*(4-t)+b[k]*t)/4),q);if(e<be){be=e;bl=t;}}
      lvl.push(bl);err.push(be);});
    pairs.push({bg,fg,lvl,err});
  }
  return C128_FIT=pairs;
}
function c128Nearest(c64col){const q=vdcRgb(PAL[c64col]);let b=0;
  for(let v=1;v<16;v++)if(vdcDist(vdcRgb(VDC_PAL[v]),q)<vdcDist(vdcRgb(VDC_PAL[b]),q))b=v;return b;}
// per map: background of empty cells, border, side panel text / background
function c128Defaults(m){return{bg:c128Nearest(m.bg),border:c128Nearest(m.border),pfg:15,pbg:2};}
function c128Settings(m){if(!m.c128)m.c128=c128Defaults(m);return m.c128;}
// map header bytes $0e-$0f (docs/PLATFORMS.md 3): empty-cell background << 4 |
// border (R26), and the panel's attribute byte (background << 4 | text)
function c128Header(m){const g=m.c128||c128Defaults(m);return[(g.bg<<4)|g.border,(g.pbg<<4)|g.pfg];}
const c128Attr=(fg,bg)=>(bg<<4)|fg;

// C128 version of a tile: px = 32 hi-res pixels per line (-1 transparent,
// 0 background, 1 foreground), cells = [{fg, bg, own}]. t.c128 holds a
// hand-edited version; otherwise it is converted from the C64 tile with the
// map's background colour (pixel value 00).
const C128_CACHE=new WeakMap();
function c128AutoTile(t,c64bg){
  const key=c64bg+'|'+t.h+'|'+t.px.join(',')+'|'+JSON.stringify(t.cells),hit=C128_CACHE.get(t);
  if(hit&&hit.key===key)return hit.data;
  const fit=c128Fit(),px=new Array(32*8*t.h).fill(-1),cells=[];
  for(let r=0;r<t.h;r++)for(let c=0;c<4;c++){
    const cc=t.cells[r*4+c],cols=[c64bg,cc.c1,cc.c2,cc.c3],n=[0,0,0,0];
    for(let y=0;y<8;y++)for(let i=0;i<4;i++){const v=t.px[(r*8+y)*16+c*4+i];if(v>=0)n[v]++;}
    let best=fit[0],be=1e18;
    for(const p of fit){let e=0;for(let k=0;k<4;k++)if(n[k])e+=n[k]*p.err[cols[k]];if(e<be){be=e;best=p;}}
    cells.push({fg:best.fg,bg:best.bg,own:cc.own||'auto'});
    for(let y=0;y<8;y++)for(let i=0;i<4;i++){const v=t.px[(r*8+y)*16+c*4+i];if(v<0)continue;
      const lv=best.lvl[cols[v]];
      for(let j=0;j<2;j++){const x=c*8+i*2+j;px[(r*8+y)*32+x]=lv>C128_BAYER[(y&1)*2+(x&1)]?1:0;}}
  }
  const data={px,cells};C128_CACHE.set(t,{key,data});return data;
}
const c128TileData=(t,c64bg)=>t.c128||c128AutoTile(t,c64bg);
function c128Editable(t,c64bg){if(!t.c128)t.c128=JSON.parse(JSON.stringify(c128AutoTile(t,c64bg)));return t.c128;}
// keep a hand-edited version in step when the tile height changes (bottom aligned)
function c128Resize(t,d){
  if(!t.c128)return;const v=t.c128;
  if(d>0){v.px=new Array(d*256).fill(-1).concat(v.px);v.cells=Array.from({length:4*d},()=>({...v.cells[0]})).concat(v.cells);}
  else if(d<0){v.px=v.px.slice(-d*256);v.cells=v.cells.slice(-d*4);}
}
// tile -> VDC cells: type (0 empty, 1 opaque, 2 masked + colours, 3 masked
// keep colours), attribute bg<<4|fg, 8 bitmap bytes, 8 mask bytes (1 = keep)
function c128EncodeTile(t,c64bg){
  const d=c128TileData(t,c64bg),cells=[];
  for(let r=0;r<t.h;r++)for(let c=0;c<4;c++){
    const bmp=[],mask=[];let trans=0;
    for(let y=0;y<8;y++){let b=0,m=0;
      for(let i=0;i<8;i++){const v=d.px[(r*8+y)*32+c*8+i];
        if(v<0){trans++;m|=128>>i;}else if(v)b|=128>>i;}
      bmp.push(b);mask.push(m);}
    const cc=d.cells[r*4+c];let type;
    if(trans===64)type=0;else if(trans===0)type=1;
    else type=cc.own==='own'?2:cc.own==='keep'?3:((64-trans)>=32?2:3);
    cells.push({type,attr:c128Attr(cc.fg,cc.bg),fg:cc.fg,bg:cc.bg,bmp,mask});
  }
  return{h:t.h,cells};
}

// ---- side panel ------------------------------------------------------------
// 8x8 font for ASCII 32-95 (5x7 glyphs, bits 7-3 of rows 0-6); exported with the figures
const C128_GLYPHS={
  ' ':[0,0,0,0,0,0,0],'!':[4,4,4,4,4,0,4],'"':[10,10,0,0,0,0,0],'#':[10,10,31,10,31,10,10],"'":[12,4,8,0,0,0,0],
  '(':[2,4,8,8,8,4,2],')':[8,4,2,2,2,4,8],'*':[0,4,21,14,21,4,0],'+':[0,4,4,31,4,4,0],',':[0,0,0,0,12,4,8],
  '-':[0,0,0,31,0,0,0],'.':[0,0,0,0,0,12,12],'/':[0,1,2,4,8,16,0],':':[0,12,12,0,12,12,0],';':[0,12,12,0,12,4,8],
  '<':[2,4,8,16,8,4,2],'=':[0,0,31,0,31,0,0],'>':[8,4,2,1,2,4,8],'?':[14,17,1,2,4,0,4],
  '0':[14,17,19,21,25,17,14],'1':[4,12,4,4,4,4,14],'2':[14,17,1,2,4,8,31],'3':[31,2,4,2,1,17,14],'4':[2,6,10,18,31,2,2],
  '5':[31,16,30,1,1,17,14],'6':[6,8,16,30,17,17,14],'7':[31,1,2,4,8,8,8],'8':[14,17,17,14,17,17,14],'9':[14,17,17,15,1,2,12],
  'A':[14,17,17,31,17,17,17],'B':[30,17,17,30,17,17,30],'C':[14,17,16,16,16,17,14],'D':[30,17,17,17,17,17,30],
  'E':[31,16,16,30,16,16,31],'F':[31,16,16,30,16,16,16],'G':[14,17,16,23,17,17,15],'H':[17,17,17,31,17,17,17],
  'I':[14,4,4,4,4,4,14],'J':[7,2,2,2,2,18,12],'K':[17,18,20,24,20,18,17],'L':[16,16,16,16,16,16,31],
  'M':[17,27,21,21,17,17,17],'N':[17,17,25,21,19,17,17],'O':[14,17,17,17,17,17,14],'P':[30,17,17,30,16,16,16],
  'Q':[14,17,17,17,21,18,13],'R':[30,17,17,30,20,18,17],'S':[15,16,16,14,1,1,30],'T':[31,4,4,4,4,4,4],
  'U':[17,17,17,17,17,17,14],'V':[17,17,17,17,17,10,4],'W':[17,17,17,21,21,21,10],'X':[17,17,10,4,10,17,17],
  'Y':[17,17,17,10,4,4,4],'Z':[31,1,2,4,8,16,31],'[':[14,8,8,8,8,8,14],']':[14,2,2,2,2,2,14],'_':[0,0,0,0,0,0,31],
};
function c128Font(){const f=new Uint8Array(64*8);
  for(let c=0;c<64;c++){const g=C128_GLYPHS[String.fromCharCode(32+c)];if(g)g.forEach((v,y)=>f[c*8+y]=v<<3);}
  return f;}
// static panel text (column, row, text); the engine prints the same
const C128_PANEL=[[64,1,'ISO64'],[64,2,'C128 VDC'],[64,8,'Q W E'],[64,9,'A + D'],[64,10,'Z S C']];
const C128_SEP=0x40;   // separator line: this byte on every line of column 62
function c128MapName(m){const nm=m.name.toUpperCase().slice(0,16);let s='';
  for(let i=0;i<16;i++){const c=i<nm.length?nm.charCodeAt(i)&127:32;s+=String.fromCharCode(c<32||c>95?32:c);}return s;}
const c128Pos=(x,y)=>'POS '+String(x).padStart(2,'0')+','+String(y).padStart(2,'0');

// ---- renderer --------------------------------------------------------------
// fb: bitmap cell by cell (cell o = row*80+col, byte o*8+line), attributes,
// and per pixel the colour it was drawn to show (-1 = none) for clash counting
function c128NewFB(){const n=C128.cols*C128.rows;return{bmp:new Uint8Array(n*8),attr:new Uint8Array(n),src:new Int8Array(n*64).fill(-1)};}
const c128Project=(x,y,cx,cy)=>{const dx=x-cx,dy=y-cy;return{col:C128.centerCol+2*(dx-dy),row:C128.centerRow+dx+dy};};
const c128CanTouch=(col,row)=>col>=C128.vp.c0-3&&col<=C128.vp.c1&&row>=C128.vp.r0-1&&row<=C128.vp.r1+9;
function c128DrawTile(fb,enc,bcol,grow){
  if(!enc)return;
  let row=grow+2-enc.h;
  for(let r=0;r<enc.h;r++,row++)for(let c=0;c<4;c++){
    const cell=enc.cells[r*4+c],col=bcol+c,vp=C128.vp;
    if(!cell.type||row<vp.r0||row>vp.r1||col<vp.c0||col>vp.c1)continue;
    const o=row*C128.cols+col;
    if(cell.type!==3)fb.attr[o]=cell.attr;
    for(let i=0;i<8;i++){
      const keep=cell.type===1?0:cell.mask[i];
      fb.bmp[o*8+i]=(fb.bmp[o*8+i]&keep)|cell.bmp[i];
      for(let p=0;p<8;p++)if(!(keep&128>>p))fb.src[o*64+i*8+p]=cell.bmp[i]&128>>p?cell.fg:cell.bg;
    }
  }
}
// soft sprite: sprite pixel (i, sy) covers hi-res pixels X+2i, X+2i+1 on line Y+sy.
// o (outline) = background bit, x (body) = foreground bit, s (skin) = dithered;
// a cell with body or skin pixels takes the figure colour as its foreground
function c128DrawSprite(fb,sid,fg,X,Y){
  const rows=(SPRITES[sid]||SPRITES[0])[1],vp=C128.vp;
  rows.forEach((line,sy)=>{line=line.padEnd(12,'.').slice(0,12);
    for(let i=0;i<12;i++){const ch=line[i];if(ch==='.')continue;
      for(let j=0;j<2;j++){const x=X+2*i+j,y=Y+sy,col=x>>3,row=y>>3;
        if(x<0||y<0||col<vp.c0||col>vp.c1||row<vp.r0||row>vp.r1)continue;
        const o=row*C128.cols+col,b=128>>(x&7),on=ch==='x'||(ch==='s'&&!((x+y)&1));
        fb.bmp[o*8+(y&7)]=on?fb.bmp[o*8+(y&7)]|b:fb.bmp[o*8+(y&7)]&~b;
        fb.src[o*64+(y&7)*8+(x&7)]=ch==='x'?fg:-1;
        if(ch!=='o')fb.attr[o]=(fb.attr[o]&0xf0)|fg;}}});
}
function c128Text(fb,col,row,s,font){
  for(let k=0;k<s.length;k++){const c=s.charCodeAt(k),g=c<32||c>95?0:c-32;
    for(let i=0;i<8;i++)fb.bmp[(row*C128.cols+col+k)*8+i]=font[g*8+i];}
}
function c128Render(m,tiles,cx,cy){
  const g=m.c128||c128Defaults(m),enc=tiles.map(t=>t?c128EncodeTile(t,m.bg):null),fb=c128NewFB(),vp=C128.vp,font=c128Font();
  for(let r=0;r<C128.rows;r++)for(let c=0;c<C128.cols;c++)fb.attr[r*C128.cols+c]=c<C128.panelCol?c128Attr(0,g.bg):c128Attr(g.pfg,g.pbg);
  for(let y=0;y<MW;y++)for(let x=0;x<MW;x++){
    const i=y*MW+x,h=m.hgt[i]&3,{col,row}=c128Project(x,y,cx,cy);
    if(!c128CanTouch(col,row))continue;
    if(m.terr[i]){for(let l=0;l<h;l++)c128DrawTile(fb,enc[m.slab],col,row-l);c128DrawTile(fb,enc[m.terr[i]],col,row-h);}
    if(m.obj[i])c128DrawTile(fb,enc[m.obj[i]],col,row-h);
  }
  // soft sprites, back to front, hero last
  const H=(x,y)=>m.hgt[y*MW+x]&3,spr=[];
  for(const e of m.ents){if(!e.type||e.type===4)continue;const p=c128Project(e.x,e.y,cx,cy);
    spr.push({d:e.x+e.y,sid:e.sprite&3,fg:c128Nearest(e.color),col:p.col,row:p.row-H(e.x,e.y)});}
  spr.sort((a,b)=>a.d-b.d);
  spr.push({sid:0,fg:c128Nearest(m.hero),col:C128.centerCol,row:C128.centerRow-H(cx,cy)});
  for(const s of spr)c128DrawSprite(fb,s.sid,s.fg,s.col*8+4,s.row*8-9);
  // side panel
  for(let r=0;r<C128.rows;r++)for(let i=0;i<8;i++)fb.bmp[(r*C128.cols+C128.panelCol)*8+i]=C128_SEP;
  for(const [c,r,s] of C128_PANEL)c128Text(fb,c,r,s,font);
  c128Text(fb,64,4,c128MapName(m),font);
  c128Text(fb,64,6,c128Pos(cx,cy),font);
  // colour clash: cells where a pixel shows another colour than it was drawn with
  let clash=0;const clashCells=[];
  for(let r=vp.r0;r<=vp.r1;r++)for(let c=vp.c0;c<=vp.c1;c++){
    const o=r*C128.cols+c,a=fb.attr[o];let bad=false;
    for(let k=0;k<64&&!bad;k++){const s=fb.src[o*64+k];if(s<0)continue;
      const shown=fb.bmp[o*8+(k>>3)]&128>>(k&7)?a&15:a>>4;if(shown!==s)bad=true;}
    if(bad){clash++;clashCells.push(o);}
  }
  return{fb,clash,clashCells,sprites:spr.length};
}
function c128ToImage(fb,img){
  const d=img.data,W=C128.cols*8,P=VDC_PAL.map(vdcRgb);
  for(let row=0;row<C128.rows;row++)for(let col=0;col<C128.cols;col++){
    const o=row*C128.cols+col,a=fb.attr[o];
    for(let y=0;y<8;y++){const b=fb.bmp[o*8+y];
      for(let p=0;p<8;p++){const c=P[b&128>>p?a&15:a>>4],i=((row*8+y)*W+col*8+p)*4;
        d[i]=c[0];d[i+1]=c[1];d[i+2]=c[2];d[i+3]=255;}}}
}
// ---- export -----------------------------------------------------------------
// ctiles.prg -> $9800. Same layout as the C64 TILES file (count, pointer table,
// records of h, flags, cell pointers) but VDC cells:
//   type (1 opaque, 2 masked + attribute, 3 masked keep attribute), attribute
//   byte (bg<<4 | fg), 8 bitmap bytes, 8 mask bytes unless opaque
function c128ExportTiles(tiles,c64bg){
  const n=tiles.length-1,out=[CTILES_ADDR&255,CTILES_ADDR>>8,n],ptrs=[0,0],recs=[];
  let addr=CTILES_ADDR+1+2*(n+1);
  for(let i=1;i<=n;i++){
    const e=c128EncodeTile(tiles[i],c64bg),tbl=2+e.cells.length*2,r=[e.h,tiles[i].flags],data=[];
    e.cells.forEach(c=>{
      if(!c.type){r.push(0,0);return;}
      const a=addr+tbl+data.length;r.push(a&255,a>>8);
      data.push(c.type,c.attr,...c.bmp);if(c.type!==1)data.push(...c.mask);});
    r.push(...data);ptrs.push(addr&255,addr>>8);addr+=r.length;recs.push(r);}
  out.push(...ptrs);recs.forEach(r=>out.push(...r));
  return new Uint8Array(out);
}
// csprites.prg -> $9100. Figures pre-shifted to where the engine draws them:
// a figure at tile column col / row row covers a 4x4 block of cells from
// (col, row-2), starting 4 hi-res pixels in and 7 lines down.
//   $9100 + s*256 + cell*16 : 8 bitmap bytes, 8 mask bytes  (cell = cy*4+cx)
//   $9500 + s*16 + cell     : bit 0 body/skin pixels (takes the colour), bit 1 any pixels
//   $9540                   : C64 colour -> nearest RGBI colour (16 bytes)
//   $9600                   : panel font, ASCII 32-95, 8 bytes each
function c128ExportSprites(){
  const b=new Uint8Array(2+0x700);b[0]=CSPR_ADDR&255;b[1]=CSPR_ADDR>>8;
  SPRITES.slice(0,4).forEach(([,rows],s)=>{
    const bmp=new Uint8Array(16*8),mask=new Uint8Array(16*8).fill(255),fl=new Uint8Array(16);
    rows.forEach((line,sy)=>{line=line.padEnd(12,'.').slice(0,12);
      for(let i=0;i<12;i++){const ch=line[i];if(ch==='.')continue;
        for(let j=0;j<2;j++){const X=4+2*i+j,Y=7+sy,cell=(Y>>3)*4+(X>>3),k=cell*8+(Y&7),bit=128>>(X&7);
          mask[k]&=~bit;if(ch==='x'||(ch==='s'&&!((X+Y)&1)))bmp[k]|=bit;
          fl[cell]|=ch==='o'?2:3;}}});
    for(let c=0;c<16;c++){const o=2+s*256+c*16;b.set(bmp.subarray(c*8,c*8+8),o);b.set(mask.subarray(c*8,c*8+8),o+8);b[2+0x400+s*16+c]=fl[c];}
  });
  for(let c=0;c<16;c++)b[2+0x440+c]=c128Nearest(c);
  b.set(c128Font(),2+0x500);
  return b;
}
