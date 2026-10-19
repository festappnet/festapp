import { OccasionDetailDialog } from '../../../src/components/occasion/occasion_detail_dialog.js';
import { FeatureService } from '../../../src/components/features/feature_service.js';
import { LocalizationService } from '../../../src/services/localization_service.js';

window.securityFixture = { executed: 0, selected: null, reserved: 0, violations: [] };
document.addEventListener('securitypolicyviolation', e => window.securityFixture.violations.push({directive:e.effectiveDirective,disposition:e.disposition}));
LocalizationService.tr = key => key;
FeatureService.getFeatureDetails = () => ({primaryColor:'123abc', reserveButtonTitle:'<img src=x onerror="window.securityFixture.executed++">'});
window.securityFixture.show = () => OccasionDetailDialog.show({title:'<img src=x onerror="window.securityFixture.executed++">', description:'<h2>Rich heading</h2><p><b>Bold</b><a href="https://example.com">Link</a><img alt="safe" src="data:image/png;base64,iVBORw0KGgo="><img src="x" onerror="window.securityFixture.executed++"><a href="javascript:window.securityFixture.executed++">Bad URL</a></p>',start_time:'2026-10-18',end_time:'2026-10-19',features:[]});
OccasionDetailDialog.handleReserveAction = async () => { window.securityFixture.reserved++; };
window.securityFixture.ready = true;
