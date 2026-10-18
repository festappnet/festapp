import { OccasionDetailDialog } from '../../../src/components/occasion/occasion_detail_dialog.js';
import { BlueprintRenderer } from '../../../src/components/blueprint/blueprint_renderer.js';
import { FeatureService } from '../../../src/components/features/feature_service.js';
import { LocalizationService } from '../../../src/services/localization_service.js';

window.securityFixture = { executed: 0, selected: null, reserved: 0, violations: [] };
document.addEventListener('securitypolicyviolation', e => window.securityFixture.violations.push({directive:e.effectiveDirective,disposition:e.disposition}));
LocalizationService.tr = key => key;
FeatureService.getFeatureDetails = () => ({primaryColor:'123abc', reserveButtonTitle:'<img src=x onerror="window.securityFixture.executed++">'});
const staticSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100" onload="window.securityFixture.executed++"><defs><linearGradient id="gradient"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient><clipPath id="clip"><rect width="100" height="100"/></clipPath><path id="shape" d="M0 0L10 10"/></defs><style>.paint { fill:url(#gradient); stroke:blue }</style><g transform="translate(1,2)" clip-path="url(#clip)"><path class="paint" d="M0 0L100 100"/><text x="10" y="20">Stage</text><use href="#shape"/></g><script>window.securityFixture.executed++</script><foreignObject><img src="x" onerror="window.securityFixture.executed++"/></foreignObject></svg>`;
window.securityFixture.show = () => OccasionDetailDialog.show({title:'<img src=x onerror="window.securityFixture.executed++">', description:'<h2>Rich heading</h2><p><b>Bold</b><a href="https://example.com">Link</a><img alt="safe" src="data:image/png;base64,iVBORw0KGgo="><img src="x" onerror="window.securityFixture.executed++"><a href="javascript:window.securityFixture.executed++">Bad URL</a></p>',start_time:'2026-10-18',end_time:'2026-10-19',features:[]});
OccasionDetailDialog.handleReserveAction = async () => { window.securityFixture.reserved++; };
const renderer = new BlueprintRenderer(document.getElementById('map'));
window.securityFixture.render = (malformed=false) => renderer.render({background_svg:malformed?'<svg><script>':staticSvg,configuration:{dimensions:{width:20,height:20}},objects:[{id:1,title:'A1',x:1,y:1}]},obj=>{window.securityFixture.selected=obj.id;});
window.securityFixture.zoom = () => {renderer.setScalingMode('min');renderer.zoomBy(1.2);renderer.handlePan(-10,-10,0,0);};
window.securityFixture.render();
window.securityFixture.ready = true;
