import {window as wixWindow} from '@wix/site-window';
import {registerTicketElement} from './element.js';
registerTicketElement(window, () => wixWindow.viewMode());
