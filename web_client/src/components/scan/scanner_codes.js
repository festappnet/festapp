// jsQR decodes one symbol. Mask each located symbol in a private frame copy
// and repeat, so adjacent/rotated codes work without native BarcodeDetector.
export function decodeQRCodes(pixels, width, height, decode, maxCodes = 12) {
    const data = new Uint8ClampedArray(pixels);
    const found = [];
    // After masking a symbol, jsQR can choose finder patterns belonging to
    // different remaining tickets. Overlapping regions give it isolated views.
    const regions=[{x:0,y:0,w:width,h:height}];
    for(let col=0;col<3;col++){const w=Math.ceil(width*.5);regions.push({x:Math.round((width-w)*col/2),y:0,w,h:height});}
    for(let row=0;row<2;row++)for(let col=0;col<3;col++){
        const w=Math.ceil(width*.5),h=Math.ceil(height*.75);
        regions.push({x:Math.round((width-w)*col/2),y:Math.round((height-h)*row),w,h});
    }
    for(let pass=0;pass<2;pass++){
    const before=found.length;
    for(const region of regions)for(let n=0;n<maxCodes && found.length<maxCodes;n++){
        const cropped=new Uint8ClampedArray(region.w*region.h*4);
        for(let y=0;y<region.h;y++)cropped.set(data.subarray(((region.y+y)*width+region.x)*4,((region.y+y)*width+region.x+region.w)*4),y*region.w*4);
        const code=decode(cropped,region.w,region.h,{inversionAttempts:'dontInvert'});
        if (!code?.data || !code.location) break;
        const points=['topLeftCorner','topRightCorner','bottomRightCorner','bottomLeftCorner'].map(k=>code.location[k] && ({x:code.location[k].x+region.x,y:code.location[k].y+region.y}));
        if (points.some(p=>!p || !Number.isFinite(p.x) || !Number.isFinite(p.y))) break;
        found.push({value:code.data,x:Math.min(...points.map(p=>p.x)),y:Math.min(...points.map(p=>p.y))});
        // Only erase the decoded quadrilateral; an axis-aligned rectangle can
        // erase a neighbouring code when the first ticket is rotated.
        const cx=points.reduce((s,p)=>s+p.x,0)/4,cy=points.reduce((s,p)=>s+p.y,0)/4;
        const polygon=points.map(p=>({x:p.x+(p.x>=cx?2:-2),y:p.y+(p.y>=cy?2:-2)}));
        const minX=Math.max(0,Math.floor(Math.min(...polygon.map(p=>p.x)))),maxX=Math.min(width-1,Math.ceil(Math.max(...polygon.map(p=>p.x))));
        const minY=Math.max(0,Math.floor(Math.min(...polygon.map(p=>p.y)))),maxY=Math.min(height-1,Math.ceil(Math.max(...polygon.map(p=>p.y))));
        for(let y=minY;y<=maxY;y++)for(let x=minX;x<=maxX;x++){
            let inside=false;
            for(let i=0,j=3;i<4;j=i++){
                const a=polygon[i],b=polygon[j];
                if((a.y>y)!==(b.y>y) && x<(b.x-a.x)*(y-a.y)/(b.y-a.y)+a.x)inside=!inside;
            }
            if(inside){const i=(y*width+x)*4;data[i]=data[i+1]=data[i+2]=data[i+3]=255;}
        }
    }
    if(found.length===before || found.length>=maxCodes)break;
    }
    const seen=new Set();
    return found.sort((a,b)=>a.y-b.y||a.x-b.x).filter(c=>{if(seen.has(c.value))return false;seen.add(c.value);return true;});
}
