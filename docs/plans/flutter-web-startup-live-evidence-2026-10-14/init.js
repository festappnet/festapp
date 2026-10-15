window.__auditPerf = {readyMs:null,engineMs:null};
window.addEventListener('festapp-app-ready',()=>{window.__auditPerf.readyMs=performance.now();},{once:true});
window.addEventListener('flutter-first-frame',()=>{window.__auditPerf.engineMs=performance.now();},{once:true});
