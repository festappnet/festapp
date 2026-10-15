
import { LocalizationService } from '../../services/localization_service.js';

export class UnitStrings {
    static copy(key, cs, en) { return LocalizationService.tr(`Catalogue.${key}`, {}, LocalizationService.currentLocale === 'cs' || LocalizationService.currentLocale === 'sk' ? cs : en); }
    static get clearSearch() { return this.copy('clearSearch', 'Vymazat hledání', 'Clear search'); }
    static get retry() { return this.copy('retry', 'Zkusit znovu', 'Try again'); }
    static get loading() { return this.copy('loading', 'Aktualizujeme seznam akcí…', 'Updating events…'); }
    static get loadFailed() { return this.copy('loadFailed', 'Akce se nepodařilo načíst. Zkuste to znovu.', 'Events could not be loaded. Please try again.'); }
    static get refreshFailed() { return this.copy('refreshFailed', 'Seznam se nepodařilo aktualizovat. Zobrazené odkazy na akce můžete dál použít.', 'The list could not be updated. You can still use the event links below.'); }
    static get noSearchResults() { return this.copy('noSearchResults', 'Pro tento výraz jsme nenašli žádnou akci.', 'No events match your search.'); }
    static get emptyCatalogue() { return this.copy('emptyCatalogue', 'Zatím zde nejsou žádné akce.', 'There are no events here yet.'); }
    static get onlyArchive() { return this.copy('onlyArchive', 'Momentálně nejsou zveřejněné žádné aktuální ani nadcházející akce. Starší akce najdete v archivu.', 'There are no current or upcoming events. Earlier events are available in the archive.'); }
    static get otherEvents() { return this.copy('otherEvents', 'Další akce', 'Other events'); }

    static get search() { return LocalizationService.tr('Common.search'); }
    static get noEventsFound() { return LocalizationService.tr('Common.noEventsFound'); }
    static get happeningNow() { return LocalizationService.tr('Common.happeningNow'); }
    static get upcomingEvents() { return LocalizationService.tr('Common.upcomingEvents'); }
    static get pastEvents() { return LocalizationService.tr('Common.pastEvents'); }
    static get deleteUnit() { return LocalizationService.tr('UnitSettings.deleteUnit'); }
    static get deleteUnitConfirmation() { return LocalizationService.tr('UnitSettings.deleteUnitConfirmation'); }
    static get cannotDeleteUnitWithOccasions() { return LocalizationService.tr('UnitSettings.cannotDeleteUnitWithOccasions'); }
    static get cannotDeleteLastUnit() { return LocalizationService.tr('UnitSettings.cannotDeleteLastUnit'); }
}
