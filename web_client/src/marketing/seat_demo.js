import kernelUrl from '@festapp/venue-layout/kernel?url';
import { loadKernel, mount } from '@festapp/venue-layout';
import { FeatureBlueprint, Common } from '../../../assets/translations/cs.json';
import { BlueprintLayoutAdapter } from '../components/blueprint/blueprint_layout_adapter.js';
import { SeatStates } from '../components/blueprint/blueprint_config.js';
import { formatPrice } from '../utils/formatters.js';
import { layout, layoutResources } from './seat_demo_layout.json';

const sampleTicket = { id: 1, title: 'Vstupenka', price: 650, currency_code: 'CZK' };
const sampleOccupiedSeats = new Set(['1A', '1B', '3C', '4A', '4D', '6A', '6B', '6C', '8B', '8C', '10E', '12F', '20A', '20B']);

export async function mountSeatDemo(demo) {
    await loadKernel(kernelUrl);

    // Authored scout-ball-182 template. Seat availability and prices are illustrative.
    const authoredScene = JSON.parse(globalThis.VenueLayoutKernel.compileScene(
        JSON.stringify(layout), JSON.stringify(layoutResources), '{}',
    ));
    const seatFills = Object.fromEntries(authoredScene.items.filter(item => item.kind === 'seat').map(item => [item.id, item.fill]));
    const seats = layout.nodes.filter(node => node.kind === 'seat');
    const spots = seats.map(node => ({
        id: node.id,
        state: sampleOccupiedSeats.has(node.label) ? SeatStates.ORDERED : SeatStates.AVAILABLE,
    }));
    const adapter = new BlueprintLayoutAdapter({
        layout, layoutResources, spots, products: [sampleTicket],
        seatBindings: seats.map(node => ({
            nodeId: node.id, spotId: node.id, title: node.label, productId: sampleTicket.id,
        })),
    }, {
        // The shared picker uses the same selection adapter as checkout. This
        // session updates only its in-memory selection, with no API credentials.
        session: { state: { tickets: [] }, async toggleSpotUnit() {} },
        seatFills, locale: 'cs', priceLabel: Common.price,
    });

    const map = demo.querySelector('[data-seat-map]');
    const zoomIn = demo.querySelector('[data-seat-zoom-in]');
    const zoomOut = demo.querySelector('[data-seat-zoom-out]');
    const clear = demo.querySelector('[data-seat-clear]');
    const seatLabels = demo.querySelector('[data-seat-labels]');
    const total = demo.querySelector('[data-seat-total]');
    map.hidden = false;

    const viewer = mount(map, {
        ...adapter.options(),
        messages: FeatureBlueprint.viewer,
        minZoom: 1,
        maxZoom: 5,
        canvasCornerRadius: 12,
        onCameraChanged({ canZoomIn, canZoomOut }) {
            zoomIn.disabled = !canZoomIn;
            zoomOut.disabled = !canZoomOut;
        },
    });
    // Keep ordinary scrolling available over the inline map. Pinch gestures
    // and the zoom buttons still use the shared viewer.
    map.addEventListener('wheel', event => {
        if (!event.ctrlKey) event.stopImmediatePropagation();
    }, { capture: true, passive: true });
    adapter.onPresentationChanged = seatPresentation => {
        viewer.update({ seatPresentation });
        const selected = adapter.selectedSeats;
        const labels = selected.map(seat => seat.title).sort((a, b) => a.localeCompare(b, 'cs', { numeric: true }));
        seatLabels.textContent = labels.length ? labels.join(', ') : 'Zatím žádná';
        total.textContent = formatPrice(sampleTicket.price * selected.length, sampleTicket.currency_code, 0, 'cs');
        clear.disabled = !selected.length;
    };
    zoomIn.onclick = () => viewer.zoomBy(1.25);
    zoomOut.onclick = () => viewer.zoomBy(1 / 1.25);
    demo.querySelector('[data-seat-fit]').onclick = () => viewer.fitToScreen();
    clear.onclick = () => {
        adapter.updatePresentation(spots);
        zoomIn.focus({ preventScroll: true });
    };
}
