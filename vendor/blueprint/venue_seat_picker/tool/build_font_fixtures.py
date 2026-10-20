#!/usr/bin/env python3
"""Offline outline extraction. Build prerequisite: fonttools==4.67.0 (Python).
Runtime consumers need only fixtures.json; no Python, font parsing or downloads.
"""
import hashlib, json
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.basePen import BasePen
ROOT = Path(__file__).resolve().parent.parent
class OutlinePen(BasePen):
    def __init__(self, gs): super().__init__(gs); self.path=[]
    def add(self,op,*pts): self.path.append([op,*[round(v,5) for p in pts for v in p]])
    def _moveTo(self,p): self.add('M',p)
    def _lineTo(self,p): self.add('L',p)
    def _curveToOne(self,a,b,c): self.add('C',a,b,c)
    def _qCurveToOne(self,a,b): self.add('Q',a,b)
    def _closePath(self): self.path.append(['Z'])
    def _endPath(self): pass
fonts={}; manifest=[]
for id,name,family,license in [('fixture:sans','Roboto.ttf','Roboto','Roboto-OFL.txt'),('fixture:serif','Roboto-Slab.ttf','Roboto Slab','Roboto-Slab-LICENSE.txt')]:
    path=ROOT/'assets/layout_fonts'/name
    data=path.read_bytes(); sha=hashlib.sha256(data).hexdigest()
    font=TTFont(path); gs=font.getGlyphSet(); cmap=font.getBestCmap(); glyphs={}
    for cp in list(range(32,592))+list(range(768,880))+[0x2013,0x2014,0x2018,0x2019,0x201c,0x201d,0x2022,0x2026,0x2190,0x2192,0x20ac]:
        if cp not in cmap: continue
        g=gs[cmap[cp]]; pen=OutlinePen(gs); g.draw(pen)
        glyphs[chr(cp)]={'advance':g.width,'path':pen.path}
    fonts[id]={'id':id,'hash':sha,'family':family,'unitsPerEm':font['head'].unitsPerEm,'ascent':font['hhea'].ascent,'descent':font['hhea'].descent,'glyphs':glyphs}
    manifest.append({'id':id,'file':name,'sha256':sha,'license':license,'family':family,'source':'Google Fonts fixture; full copyright in embedded font name table and adjacent license','glyphCount':len(glyphs)})
out=ROOT/'assets/layout_fonts'
(out/'fixtures.json').write_text(json.dumps({'protocol':1,'fonts':fonts},ensure_ascii=False,separators=(',',':')))
(out/'manifest.json').write_text(json.dumps({'protocol':1,'fixtures':manifest},indent=2)+'\n')
print('Built %s font fixtures (%s bytes)'%(len(fonts),(out/'fixtures.json').stat().st_size))
