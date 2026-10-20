import { SeatStates } from './blueprint_config.js';
import { formatPrice } from '../../utils/formatters.js';
import { CommonStrings } from '../shared/common_strings.js';
import { LocalizationService } from '../../services/localization_service.js';

// Existing Basic status palette, supplied through the generic presentation seam.
const basicSeatFills = {
    [SeatStates.AVAILABLE]: '#267329FF', [SeatStates.SELECTED_BY_ME]: '#267329FF',
    [SeatStates.SELECTED]: '#00000042', [SeatStates.ORDERED]: '#0000001F',
    [SeatStates.USED]: '#412673FF', [SeatStates.TAKEN]: '#412673FF',
    [SeatStates.BLACK]: '#000000DE', [SeatStates.EMPTY]: '#267329FF',
};

/** Public commerce/session adapter. All geometry and gestures belong to the package. */
export class BlueprintLayoutAdapter {
    constructor(data, { session, initialSeats = [] } = {}) {
        if (!data?.layout) throw new Error('Blueprint V2 layout unavailable');
        this.document = data.layout;
        this.resources = data.layoutResources || {};
        this.session = session;
        this.disposed = false;
        this.pending = new Set();
        this.models = new Map();
        this.bindings = new Map();
        this.areaBindings = new Map((data.areaBindings || []).map(binding => [binding.nodeId, {...binding}]));
        this.areaAvailability = new Map((data.areaAvailability || []).map(area => [area.nodeId, area.reason ? 0 : area.available]));
        const products = new Map((data.products || []).map(p => [String(p.id), p]));
        this.areaProducts = new Map([...this.areaBindings].map(([id, binding]) => [id, products.get(String(binding.productId))]));
        const spots = new Map((data.spots || []).map(s => [String(s.id), s]));
        for (const binding of data.seatBindings || []) {
            const spot = spots.get(String(binding.spotId)) || {state: binding.status};
            const product = products.get(String(binding.productId));
            const selected = spot.state === SeatStates.SELECTED_BY_ME;
            const currency = product?.currency_code;
            const priceLabel = typeof product?.price === 'number' && Number.isFinite(product.price) && /^[A-Z]{3}$/.test(currency || '')
                ? formatPrice(product.price, currency, 0, LocalizationService.currentLocale) : null;
            this.bindings.set(binding.nodeId, { ...binding });
            // Explicit allowlist: no order/customer/internal-note data crosses
            // the generic public renderer boundary, even if a caller errs.
            this.models.set(binding.nodeId, {
                id: binding.spotId, title: binding.title || spot.title || '',
                state: [SeatStates.SELECTED, SeatStates.SELECTED_BY_ME, SeatStates.ORDERED, SeatStates.USED, SeatStates.TAKEN].includes(spot.state)
                    ? spot.state : binding.blocked ? SeatStates.BLACK : !product ? SeatStates.EMPTY
                    : selected ? SeatStates.SELECTED_BY_ME : spot.state || SeatStates.AVAILABLE,
                product: binding.productId, priceLabel, productModel: product && {
                    id: product.id, title: product.title, price: product.price,
                    currency_code: product.currency_code,
                    isAvailable: product.isAvailable, is_dynamically_available: product.is_dynamically_available,
                    is_available_dynamic_capacity: product.is_available_dynamic_capacity,
                },
            });
        }
        this.session?.reconcileReservations?.([...this.models.values()], data);
    }
    // The host supplies only the permission-checked reader; this adapter updates
    // commercial presentation and payload without replacing document or camera.
    setReservationReader(read) {
        if (!this._recover) this._previousRecover = this.session?.recoverReservations;
        this._recover = async () => {
            const data = await read();
            if (this.disposed) throw new Error('reservation_picker_closed');
            this.reconcile(data);
        };
        if (this.session) this.session.recoverReservations = this._recover;
    }
    reconcile(data) {
        const states = new Map((data.spots || []).map(spot => [String(spot.id), spot.state]));
        const bindings = new Map((data.seatBindings || []).map(binding => [binding.nodeId, binding]));
        for (const [id, model] of this.models) {
            model.state = states.get(String(model.id)) || bindings.get(id)?.status || SeatStates.EMPTY;
        }
        this.session?.reconcileReservations?.([...this.models.values()], data);
        if (!this.disposed) this.onPresentationChanged?.(this.seatPresentation);
    }
    get selectedSeats() { return [...this.models.values()].filter(s => s.state === SeatStates.SELECTED_BY_ME); }
    seatModel(nodeId) { return this.models.get(nodeId); }
    get seatPresentation() {
        return Object.fromEntries([...this.models].map(([id, model]) => {
            const own = model.state === SeatStates.SELECTED_BY_ME;
            const available = model.state === SeatStates.AVAILABLE || own;
            return [id, {
                status: own ? 'available' : model.state === SeatStates.SELECTED ? 'reserved'
                    : [SeatStates.ORDERED, SeatStates.USED, SeatStates.TAKEN].includes(model.state) ? 'occupied'
                    : model.state === SeatStates.BLACK ? 'blocked' : available ? 'available' : 'unavailable',
                selectable: own || (available && model.productModel != null && model.productModel.isAvailable !== false && model.productModel.is_dynamically_available !== false && model.productModel.is_available_dynamic_capacity !== false),
                stateMarker: [SeatStates.USED, SeatStates.TAKEN].includes(model.state) ? 'none' : 'auto',
                selected: own, label: model.title, fill: basicSeatFills[model.state] ?? basicSeatFills[SeatStates.EMPTY],
                tooltip: `${[model.productModel?.title, model.title].filter(Boolean).join(' ')}\n${CommonStrings.price}: ${model.priceLabel ?? formatPrice(0, 'CZK', 0, LocalizationService.currentLocale)}`,
            }];
        }));
    }
    get capacityPresentation() {
        return Object.fromEntries([...this.areaBindings].map(([id]) => [id, {
            available: this.areaAvailability.get(id) ?? 0,
            selectedQuantity: this.session?.state?.tickets.filter(ticket => ticket._blueprintArea === id).length || 0,
        }]));
    }
    async requestQuantity(nodeId, quantity) {
        const binding = this.areaBindings.get(nodeId), available = this.areaAvailability.get(nodeId);
        if (this.disposed || !binding || !Number.isInteger(available)) return {accepted: false, message: 'area_quantity_unavailable'};
        try {
            this.session.setAreaQuantity(binding, quantity, available, this.areaProducts.get(nodeId));
            this.onCapacityChanged?.(this.capacityPresentation);
            return {accepted: true};
        } catch (error) { return {accepted: false, message: error.message}; }
    }
    options() {
        return { document: this.document, resources: this.resources,
            seatPresentation: this.seatPresentation, capacityPresentation: this.capacityPresentation,
            onQuantityRequested: (id, quantity) => this.requestQuantity(id, quantity),
            onSelectionRequested: (ids, selecting) => this.requestSelection(ids, selecting) };
    }
    async requestSelection(nodeIds, selecting) {
        const ids = [...nodeIds];
        if (this.disposed || !ids.length || ids.some(id => this.pending.has(id))) return { accepted: false };
        const models = ids.map(id => this.models.get(id));
        if (models.some((model, index) => !model || !this.seatPresentation[ids[index]].selectable)) return { accepted: false };
        // The package supplies a complete unit. Validate it before any command.
        for (const id of ids) {
            const unit = (this.document.selectionUnits || []).find(u => u.nodeIds.includes(id));
            if (unit && (unit.nodeIds.length !== ids.length || unit.nodeIds.some(member => !nodeIds.has(member)))) {
                return { accepted: false, message: 'Incomplete seat unit' };
            }
        }
        ids.forEach(id => this.pending.add(id));
        try {
            const result = await this.session.toggleSpotUnit(models, selecting);
            if (this.disposed) return { accepted: false };
            for (const model of models) model.state = selecting ? SeatStates.SELECTED_BY_ME : SeatStates.AVAILABLE;
            this.onPresentationChanged?.(this.seatPresentation);
            return { accepted: true, expiresAt: result?.expiresAt };
        } catch (error) {
            if (!this.disposed) this.onError?.(error);
            return { accepted: false, message: error.message, reason: error.reason,
                authoritativeSeatIds: error.reservationRecovered ? [...this.models].filter(([, model]) => model.state === SeatStates.SELECTED_BY_ME).map(([id]) => id) : undefined };
        } finally { ids.forEach(id => this.pending.delete(id)); }
    }
    updatePresentation(spots) {
        const states = new Map(spots.map(s => [String(s.id), s.state]));
        for (const [id, model] of this.models) {
            if (!this.pending.has(id) && states.has(String(model.id))) model.state = states.get(String(model.id));
        }
        if (!this.disposed) this.onPresentationChanged?.(this.seatPresentation);
    }
    dispose() { if (this.session?.recoverReservations === this._recover) this.session.recoverReservations = this._previousRecover ?? null; this.disposed = true; this.onPresentationChanged = null; this.onCapacityChanged = null; this.onError = null; }
}
