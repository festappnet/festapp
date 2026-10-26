
import { LocalizationService } from '../../services/localization_service.js';

export class FeedbackStrings {
    static get requestFeature() { return LocalizationService.tr('Feedback.requestFeature'); }
    static get subjectFeature() { return LocalizationService.tr('Feedback.subjectFeature'); }
    static get hintFeature() { return LocalizationService.tr('Feedback.hintFeature'); }
    
    static get reportBug() { return LocalizationService.tr('Feedback.reportBug'); }
    static get subjectBug() { return LocalizationService.tr('Feedback.subjectBug'); }
    static get hintBug() { return LocalizationService.tr('Feedback.hintBug'); }

    static get support() { return LocalizationService.tr('Feedback.support'); }
    static get subjectSupport() { return LocalizationService.tr('Feedback.subjectSupport'); }
    static get hintSupport() { return LocalizationService.tr('Feedback.hintSupport'); }

    static get other() { return LocalizationService.tr('Feedback.other'); }
    static get subjectGeneral() { return LocalizationService.tr('Feedback.subjectGeneral'); }
    static get hintGeneral() { return LocalizationService.tr('Feedback.hintGeneral'); }

    static get helpTitle() { return LocalizationService.tr('Feedback.helpTitle'); }
}
