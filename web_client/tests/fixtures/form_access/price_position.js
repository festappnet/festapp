// Real price rendering and embed handshake; no order transport or submission.
import {ThemeService} from '../../../src/services/theme_service.js';
import {PriceWidget} from '../../../src/components/forms/widgets/price_widget.js';
import {EmbedBridge} from '../../../src/services/embed_bridge.js';
import '../../../src/theme_config.css';
import '../../../src/components/forms/form_component.css';
import '../../../src/embed.css';
ThemeService.applyThemeFromModel({primaryColor:'#216445',secondaryColor:'#146475',backgroundMode:'gradient'});
const session=new EventTarget();
session.formModel={blueprint:null,visibleFields:[],payments:{configured:{}}};
session.currentState={totalPrice:1300,totalItems:1,currency:'CZK',metaSurchargeSums:{}};
const bridge=new EmbedBridge();bridge.start();
const widget=new PriceWidget(session,document.getElementById('form-page-container'));widget.render();
window.addEventListener('pagehide',()=>{widget.destroy();bridge.destroy?.();});
