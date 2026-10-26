
import { LocalizationService } from '../../services/localization_service.js';

export class OrdersStrings {

    static get synchronizePayments() { return LocalizationService.tr('FeatureOrders.synchronizePayments'); }
    static get processing() { return LocalizationService.tr('FeatureOrders.processing'); }
    static get changeStateToPaid() { return LocalizationService.tr('FeatureOrders.changeStateToPaid'); }
    static get changeStateToPaidConfirmation() { return LocalizationService.tr('FeatureOrders.changeStateToPaidConfirmation'); }
    static get tickets() { return LocalizationService.tr('FeatureOrders.tickets'); }
    static get ticket() { return LocalizationService.tr('FeatureOrders.ticket'); }
    static get applications() { return LocalizationService.tr('FeatureOrders.applications'); }
    static get application() { return LocalizationService.tr('FeatureOrders.application'); }
    static get stornoFailed() { return LocalizationService.tr('FeatureOrders.stornoFailed'); }
    static get ordersTab() { return LocalizationService.tr('FeatureOrders.ordersTab'); }
    static get ordersHistoryTab() { return LocalizationService.tr('FeatureOrders.ordersHistoryTab'); }

    static get confirmTicket() { return LocalizationService.tr('FeatureOrders.setAsUsed'); }
    static get stornoCompletedText() { return LocalizationService.tr('FeatureOrders.stornoCompletedItem'); }
    
    // Grid Columns
    static get gridId() { return LocalizationService.tr('OrderGridColumns.id'); }
    static get gridHide() { return LocalizationService.tr('OrderGridColumns.hide'); }
    static get gridTitle() { return LocalizationService.tr('OrderGridColumns.title'); }
    static get gridPrice() { return LocalizationService.tr('OrderGridColumns.price'); }
    static get gridProductType() { return LocalizationService.tr('OrderGridColumns.productType'); }
    static get gridOrder() { return LocalizationService.tr('OrderGridColumns.order'); }
    static get gridMax() { return LocalizationService.tr('OrderGridColumns.max'); }
    static get gridOrdered() { return LocalizationService.tr('OrderGridColumns.ordered'); }
    static get gridPaid() { return LocalizationService.tr('OrderGridColumns.paid'); }
    static get gridCurrency() { return LocalizationService.tr('OrderGridColumns.currency'); }
    static get gridDescription() { return LocalizationService.tr('OrderGridColumns.description'); }
    static get gridState() { return LocalizationService.tr('OrderGridColumns.state'); }
    static get gridCreated() { return LocalizationService.tr('OrderGridColumns.created'); }
    static get gridProducts() { return LocalizationService.tr('OrderGridColumns.products'); }
    static get gridNote() { return LocalizationService.tr('OrderGridColumns.note'); }
    static get gridHiddenNote() { return LocalizationService.tr('OrderGridColumns.hiddenNote'); }
    static get gridSpot() { return LocalizationService.tr('OrderGridColumns.spot'); }
    static get gridOrderSymbol() { return LocalizationService.tr('OrderGridColumns.orderSymbol'); }
    static get gridCustomer() { return LocalizationService.tr('OrderGridColumns.customer'); }
    static get gridEmail() { return LocalizationService.tr('OrderGridColumns.email'); }
    static get gridHistory() { return LocalizationService.tr('OrderGridColumns.history'); }
    static get gridTransactions() { return LocalizationService.tr('OrderGridColumns.transactions'); }
    static get gridAmount() { return LocalizationService.tr('OrderGridColumns.amount'); }
    static get gridReturned() { return LocalizationService.tr('OrderGridColumns.returned'); }
    static get gridVariableSymbol() { return LocalizationService.tr('OrderGridColumns.variableSymbol'); }
    static get gridDeadline() { return LocalizationService.tr('OrderGridColumns.deadline'); }
    static get gridForm() { return LocalizationService.tr('OrderGridColumns.form'); }
    static get gridReminderSent() { return LocalizationService.tr('OrderGridColumns.reminderSent'); }
    static get gridChangedAt() { return LocalizationService.tr('OrderGridColumns.changedAt'); }
    static get gridChangedBy() { return LocalizationService.tr('OrderGridColumns.changedBy'); }
    static get gridChanges() { return LocalizationService.tr('OrderGridColumns.changes'); }
    static get gridPaidOrSent() { return LocalizationService.tr('OrderGridColumns.paidOrSent'); }
    static get gridCancelled() { return LocalizationService.tr('OrderGridColumns.cancelled'); }
    static get gridUsedInForms() { return LocalizationService.tr('OrderGridColumns.usedInForms'); }
}
