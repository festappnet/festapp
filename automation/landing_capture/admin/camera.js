// Run via the owned browser's eval --stdin BEFORE opening the scanner camera.
// Only the camera stream is synthetic; real jsQR and scanner RPCs run unchanged.
(async()=>{
 const fixture=await(await fetch('/fixture')).json();
 const qr=await(await fetch('/qr')).json();
 const image=new Image();image.src=qr;await image.decode();
 const canvas=document.createElement('canvas');canvas.width=640;canvas.height=260;
 const context=canvas.getContext('2d');window.captureQRVisible=false;let revealed=0;
 function paint(){
  const bg=context.createLinearGradient(0,0,640,260);bg.addColorStop(0,'#aeb9bf');bg.addColorStop(1,'#6e7e85');context.fillStyle=bg;context.fillRect(0,0,640,260);
  if(window.captureQRVisible){if(!revealed)revealed=performance.now();const progress=Math.min(1,(performance.now()-revealed)/700);context.save();context.translate(320,130+(1-progress)*12);const scale=.88+.12*progress;context.scale(scale,scale);context.rotate(-.025);context.shadowColor='#17232b66';context.shadowBlur=12;context.shadowOffsetY=6;context.fillStyle='#fffdf6';context.fillRect(-230,-105,460,210);context.shadowColor='transparent';context.fillStyle='#263d65';context.fillRect(-230,-105,8,210);context.fillStyle='#253759';context.textAlign='left';context.font='bold 24px sans-serif';context.fillText(document.documentElement.lang==='cs'?'Ples pod':'Ball under',-203,-43);context.fillText(document.documentElement.lang==='cs'?'hvězdami':'the stars',-203,-12);context.font='14px sans-serif';context.fillText('20. 2. 2027 · 19:00',-203,25);context.font='12px sans-serif';context.fillText(document.documentElement.lang==='cs'?'VSTUPENKA · HLAVNÍ SÁL':'TICKET · MAIN HALL',-203,65);context.drawImage(image,43,-87,174,174);context.restore();}else revealed=0;
  requestAnimationFrame(paint)
 }paint();
 navigator.mediaDevices.getUserMedia=async()=>canvas.captureStream(30);
 const pointer=document.createElement('div');pointer.style.cssText='position:fixed;width:18px;height:18px;border:3px solid #263e67;border-radius:50%;background:#ffffffaa;z-index:2147483647;pointer-events:none;left:-30px;top:-30px;transition:left .35s,top .35s';document.body.append(pointer);window.movePointer=(x,y)=>{pointer.style.left=x+'px';pointer.style.top=y+'px'};
})()
