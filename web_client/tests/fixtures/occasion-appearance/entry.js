// Real public page against a disposable loopback backend. No response mocks.
import { AppConfig } from '../../../src/app_config.js';
import { SupabaseService } from '../../../src/services/supabase_service.js';
import { LocalizationService } from '../../../src/services/localization_service.js';
import { ThemeService } from '../../../src/services/theme_service.js';
import { FormPage } from '../../../src/components/forms/form_page.js';
import cs from '../../../../assets/translations/cs.json';
import '../../../src/theme_config.css';

const local = JSON.parse(sessionStorage.getItem('occasion-appearance-local') || 'null');
if (location.hostname !== '127.0.0.1' || local?.url !== 'http://127.0.0.1:56821') throw new Error('Disposable local configuration required');
AppConfig.supabaseUrl=local.url; AppConfig.anonKey=local.anonKey;
AppConfig.organization=1;AppConfig.backendActivationTenantId='';
LocalizationService.currentLocale='cs';LocalizationService.translations=cs;
await SupabaseService.initialize();ThemeService.init();
const link=new URL(location.href).searchParams.get('form');
if(!link) throw new Error('Finalized form link required');
await new FormPage('form-page-container').init(link);
