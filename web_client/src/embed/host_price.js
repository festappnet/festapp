    // The child owns prices and formatting. The host projects only that view,
    // so native sticky positioning never waits for cross-frame scroll messages.
export const projectPrice = (frame, record, data) => {
        const model = data.price;
        const host = frame.parentElement;
        if (!host?.hasAttribute('data-festapp-embed-host')) return;
        if (model !== null && (!model || !Number.isInteger(model.count) || model.count < 1 || model.count > 9999 ||
            typeof model.total !== 'string' || model.total.length > 160 || !Array.isArray(model.lines) ||
            model.lines.length > 16 || !model.lines.every(line => typeof line === 'string' && line.length <= 512))) return;
        if (!record.priceLayer) {
            if (!getComputedStyle(host).position || getComputedStyle(host).position === 'static') host.style.position = 'relative';
            const layer = document.createElement('div');
            layer.dataset.festappEmbedPrice = '';
            layer.style.cssText = 'position:absolute;top:16px;right:16px;bottom:16px;left:16px;pointer-events:none;z-index:30';
            const card = document.createElement('button'); card.type = 'button';
            card.style.cssText = 'position:sticky;top:16px;display:block;width:max-content;max-width:100%;margin-left:auto;pointer-events:auto;border:0;text-align:right;cursor:pointer;box-sizing:border-box';
            card.onclick = () => record.channel.send('price-activate');
            layer.append(card); host.append(layer); record.priceLayer = layer; record.priceCard = card;
        }
        record.priceLayer.hidden = model === null || data.visible !== true;
        const signature = JSON.stringify({model,appearance:data.appearance});
        if (model && signature !== record.priceSignature) {
            record.priceSignature = signature;
            const card = record.priceCard; card.replaceChildren();
            const styles = ['background-color','color','font-family','font-size','font-weight','padding','border-radius','box-shadow'];
            for (const property of styles) {
                const value = data.appearance?.[property];
                if (typeof value === 'string' && value.length <= 512) card.style.setProperty(property,value);
            }
            const row = document.createElement('span'); row.style.cssText='display:flex;align-items:center;gap:8px';
            const count = document.createElement('span');count.textContent = `${model.count}x`;
            const icon = document.createElementNS('http://www.w3.org/2000/svg','svg');
            icon.setAttribute('viewBox','0 0 24 24');icon.setAttribute('width','24');icon.setAttribute('height','24');icon.setAttribute('aria-hidden','true');
            const path = document.createElementNS('http://www.w3.org/2000/svg','path');path.setAttribute('fill','currentColor');
            path.setAttribute('d','M20 12c0-1.1.9-2 2-2V6c0-1.1-.9-2-2-2H4C2.9 4 2 4.9 2 6v4c1.1 0 2 .9 2 2s-.9 2-2 2v4c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2v-4c-1.1 0-2-.9-2-2zm-4.42 4.8L12 14.5l-3.58 2.3 1.1-4.1-3.2-2.62 4.2-.25L12 6l1.48 3.83 4.2.25-3.2 2.62 1.1 4.1z');icon.append(path);
            const total = document.createElement('span');total.textContent=model.total;
            row.append(count,icon,total);card.append(row);
            for (const text of model.lines) { const line=document.createElement('div');line.textContent=text;card.append(line); }
        }
        record.channel.send('price-ready', {visible:!record.priceLayer.hidden});
    };
