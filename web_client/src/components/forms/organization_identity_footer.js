import { isEmbed } from '../../services/embed_context.js';
import { revealEmbedStep } from '../../services/embed_bridge.js';
import { LocalizationService } from '../../services/localization_service.js';
import { parseOrganizationIdentity } from './organization_identity.js';
const t = key => LocalizationService.tr(`OrganizationVerification.${key}`);
const icon = () => {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('aria-hidden', 'true'); svg.setAttribute('width', '16'); svg.setAttribute('height', '16');
    const path = document.createElementNS(svg.namespaceURI, 'path'); path.setAttribute('fill','currentColor');
    path.setAttribute('d','m23 12-2.44-2.79.34-3.69-3.61-.82L15.4 1.5 12 2.96 8.6 1.5 6.71 4.7 3.1 5.51l.34 3.7L1 12l2.44 2.79-.34 3.7 3.61.82 1.89 3.2 3.4-1.47 3.4 1.46 1.89-3.2 3.61-.82-.34-3.69L23 12zm-13 5-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z'); svg.append(path); return svg;
};
export class OrganizationIdentityFooter {
    constructor(host) { this.host = host; }
    clear() { if (this.dialog?.open) this.dialog.close(); this.dialog?.remove(); this.dialog = null; this.host.replaceChildren(); this.host.hidden = true; }
    render(value) {
        this.clear(); const identity = parseOrganizationIdentity(value); if (!identity) return;
        this.host.hidden = false;
        const button = document.createElement('button'); button.type = 'button'; button.className = 'organization-identity-button';
        button.setAttribute('aria-label', `${t('organizer')}: ${identity.legalName}, ${t('verified')}, ${t('showDetails')}`);
        const words = identity.legalName.split(' '); const last = words.pop();
        button.append(document.createTextNode(`${t('organizer')}: ${words.length ? `${words.join(' ')} ` : ''}`));
        const tail = document.createElement('span'); tail.className = 'organization-identity-tail'; tail.append(document.createTextNode(last), icon()); button.append(tail);
        button.onclick = () => this.open(identity, button); this.host.append(button);
    }
    open(identity, opener) {
        if (this.dialog?.open) return;
        const dialog = document.createElement('dialog'); this.dialog = dialog; dialog.className = 'organization-identity-dialog';
        const heading = document.createElement('h2'); heading.id = 'organization-identity-heading'; heading.append(document.createTextNode(identity.legalName), icon());
        dialog.setAttribute('aria-labelledby',heading.id);
        const close = document.createElement('button'); close.type='button'; close.className='organization-identity-close';
        close.setAttribute('aria-label', t('close')); close.title = t('close'); close.onclick=()=>dialog.close();
        const closeIcon = icon(); closeIcon.setAttribute('width', '24'); closeIcon.setAttribute('height', '24');
        closeIcon.querySelector('path').setAttribute('d', 'M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z');
        close.append(closeIcon);
        const header = document.createElement('div'); header.className = 'organization-identity-header'; header.append(heading, close);
        dialog.append(header);
        const dl = document.createElement('dl'); dialog.append(dl);
        const add = (label,value,href) => { if(!value)return; const dt=document.createElement('dt'); dt.textContent=t(label); const dd=document.createElement('dd');
            const node=document.createElement(href?'a':'span'); node.textContent=value; if(href)node.href=href; dd.append(node); dl.append(dt,dd); };
        add('registrationNumber',identity.registrationNumber); add('vatId',identity.vatId);
        add('address',`${identity.address.street}, ${identity.address.postalCode} ${identity.address.city}, ${identity.countryCode}`);
        add('contactEmail',identity.contactEmail,/^[^\s@?&#]+@[^\s@?&#]+$/.test(identity.contactEmail)?`mailto:${identity.contactEmail}`:null);
        add('phone',identity.phone,/^\+?[\d ()-]+$/.test(identity.phone||'')?`tel:${identity.phone.replace(/[ ()-]/g,'')}`:null);
        let web; try { const url=new URL(identity.website); if(url.protocol==='https:'&&!url.username&&!url.password)web=url.href; }catch{}
        add('website',identity.website,web);
        const explanation=document.createElement('p'); explanation.textContent=t('explanation'); dialog.append(explanation);
        dialog.addEventListener('close',()=>{dialog.remove(); if(this.dialog===dialog)this.dialog=null; if(opener.isConnected)opener.focus();},{once:true});
        // Keep Escape owned by this native dialog, including inside order overlays.
        dialog.addEventListener('keydown', event => { if (event.key === 'Escape') event.stopPropagation(); });
        this.host.append(dialog);
        if (isEmbed()) {
            dialog.style.position = 'absolute';
            dialog.style.top = `${Math.max(0, opener.getBoundingClientRect().top + window.scrollY)}px`;
            dialog.style.marginBlock = '0';
        }
        dialog.showModal(); close.focus({ preventScroll: true }); revealEmbedStep(dialog);
    }
}
