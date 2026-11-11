window.cmpFailure=null;
try {
 const config={version:1,noAutoLoad:true,lang:'en',storageMethod:'cookie',storageName:'festapp-cmp-test',services:[{name:'analytics',title:'Analytics',purposes:['analytics'],default:false,required:false},{name:'marketing',title:'Marketing',purposes:['marketing'],default:false,required:false}]};
 const manager=window.cmpManager=klaro.getManager(config);
 window.cmpChoose=(analytics,marketing=analytics)=>{manager.updateConsent('analytics',analytics);manager.updateConsent('marketing',marketing);manager.saveAndApplyConsents()};
 window.cmpSource={read:context=>{if(!manager.confirmed)return null;return {processingRevision:window.savedRevision,analytics:manager.savedConsents.analytics===true && manager.getConsent('analytics')===true,marketing:manager.savedConsents.marketing===true && manager.getConsent('marketing')===true}},subscribe:notify=>{const watcher={update:notify};manager.watch(watcher);return ()=>manager.unwatch(watcher)}};
 window.savedRevision='rev-a';
} catch(error){window.cmpFailure=String(error)}
