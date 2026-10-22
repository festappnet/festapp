window.__uiSamples ??= [];
window.__watchUI = (stage, detect) => {
  const start=performance.now(); const observer=new MutationObserver(()=>{if(detect()){observer.disconnect();requestAnimationFrame(()=>window.__uiSamples.push({stage,ms:performance.now()-start}));}});
  observer.observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true});
};
window.__click = text => [...document.querySelectorAll('[role=button]')].find(e=>e.textContent===text)?.click();
window.__watchUI('overview',()=>[...document.querySelectorAll('[role=button]')].some(e=>e.textContent==='Vytvořit novou událost'));
window.__click('Odejít'); 'watching';
