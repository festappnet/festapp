import { LocalizationService } from '../../../services/localization_service.js';
import { ThemeService } from '../../../services/theme_service.js';
import { AppConfig } from '../../../app_config.js';
import { CommonStrings } from '../../shared/common_strings.js';

export class SettingsWidget {
    constructor(container) {
        this.container = container;
        this.element = document.createElement('div');
        this.element.className = 'settings-widget';
        // Note: Styles are injected by the parent (UserHeader) or global shared styles
        
        this.render();
        this.container.appendChild(this.element);
    }

    render() {
        this.element.innerHTML = '';
        
        // Theme Section
        this.renderSection({
            title: LocalizationService.tr('Common.appearance') || 'Vzhled', // Fallback trans
            options: [
                { id: 'dark', label: CommonStrings.dark },
                { id: 'auto', label: CommonStrings.auto },
                { id: 'light', label: CommonStrings.light }
            ],
            currentValue: ThemeService.currentMode,
            onSelect: (val) => {
                ThemeService.setMode(val);
                this.render(); // Re-render to update active state
            }
        });

        // Language Section
        this.renderSection({
            title: CommonStrings.language,
            options: AppConfig.supportedLanguages.map(lang => ({
                id: lang,
                label: lang === 'cs' ? 'Čeština' : 'English'
            })),
            currentValue: LocalizationService.currentLocale,
            onSelect: (val) => {
                if (val !== LocalizationService.currentLocale) {
                     LocalizationService.setLocale(val);
                }
            }
        });

        // Version
        if (AppConfig.version) {
            const versionEl = document.createElement('div');
            versionEl.className = 'version-info';
            versionEl.textContent = `v${AppConfig.version}`;
            this.element.appendChild(versionEl);
        }
    }

    renderSection({ title, options, currentValue, onSelect }) {
        const section = document.createElement('div');
        section.className = 'settings-section';

        const label = document.createElement('div');
        label.className = 'settings-label';
        label.textContent = title;
        section.appendChild(label);

        // Segmented Control Group
        const group = document.createElement('div');
        group.className = 'segmented-control';

        options.forEach((opt) => {
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.textContent = opt.label;
            
            const isActive = opt.id === currentValue;
            btn.className = `segmented-btn ${isActive ? 'active' : ''}`;
            
            btn.onclick = () => onSelect(opt.id);
            
            group.appendChild(btn);
        });

        section.appendChild(group);
        this.element.appendChild(section);
    }
}
