import { Component } from '../base/component.js';
import { DbOccasions } from '../occasion/db_occasions.js';
import { OccasionCard } from '../occasion/occasion_card.js';
import { classifyOccasions, groupPastOccasionsByYear } from '../occasion/catalog.js';
import { UnitStrings } from './unit_strings.js';
import './unit_page.css';

export class UnitPage extends Component {
    constructor(hostId) {
        super(hostId);
        this.allOccasions = [];
        this.searchInput = null;
        this.hasLoaded = false;
        this.requestId = 0;
    }

    init(searchId) {
        this.searchInput = document.getElementById(searchId);
        if (!this.searchInput) return;
        this.searchInput.placeholder = UnitStrings.search + '...';
        this.searchInput.setAttribute('aria-label', UnitStrings.search);
        this.onSearch = (e) => this.filter(e.target.value);
        this.searchInput.addEventListener('input', this.onSearch);
        const clearBtn = document.getElementById('clear-search');
        if (clearBtn) {
            clearBtn.setAttribute('aria-label', UnitStrings.clearSearch);
            clearBtn.onclick = () => this.clearSearch();
        }
    }

    clearSearch() {
        if (this.searchInput) this.searchInput.value = '';
        this.filter('');
        this.searchInput?.focus();
    }

    showStatus(message, retry = false) {
        this.host.querySelector('[data-catalog-status]')?.remove();
        const status = document.createElement('div');
        status.dataset.catalogStatus = '';
        status.className = 'catalog-status';
        const text = document.createElement('p');
        text.setAttribute('role', 'status');
        text.textContent = message;
        status.appendChild(text);
        if (retry) {
            const button = document.createElement('button');
            button.type = 'button';
            button.textContent = UnitStrings.retry;
            button.onclick = () => this.loadOccasions(this.orgId, this.unitId);
            status.appendChild(button);
        }
        this.host.prepend(status);
    }

    async loadOccasions(orgId, unitId = null) {
        this.unitId = unitId;
        this.orgId = orgId;
        const requestId = ++this.requestId;
        this.host.querySelector('[data-catalog-status]')?.remove();
        const status = document.createElement('div');
        status.dataset.catalogStatus = '';
        status.className = 'sp-loader';
        status.setAttribute('role', 'status');
        status.setAttribute('aria-label', UnitStrings.loading);
        this.host.prepend(status);
        try {
            const occasions = await DbOccasions.getPublicOccasions(orgId, unitId);
            if (requestId !== this.requestId || !this.host.isConnected) return;
            this.allOccasions = occasions || [];
            this.hasLoaded = true;
            const query = new URLSearchParams(window.location.search).get('q');
            if (query && this.searchInput && !this.searchInput.value) this.searchInput.value = query;
            this.filter(this.searchInput?.value || '');
        } catch (e) {
            if (requestId !== this.requestId || !this.host.isConnected) return;
            console.error('UnitPage.loadOccasions failed:', e);
            this.showStatus(this.host.querySelector('a') ? UnitStrings.refreshFailed : UnitStrings.loadFailed, true);
        }
    }

    // Called when leaving this route, so pending requests cannot overwrite another page.
    clear() {
        ++this.requestId;
        if (this.searchInput && this.onSearch) this.searchInput.removeEventListener('input', this.onSearch);
        const clearBtn = document.getElementById('clear-search');
        if (clearBtn) clearBtn.onclick = null;
        super.clear();
    }

    filter(term) {
        const clearBtn = document.getElementById('clear-search');
        if (clearBtn) clearBtn.style.display = term ? 'block' : 'none';
        // The server-rendered catalogue remains usable until the first successful refresh.
        if (!this.hasLoaded) return;
        const norm = str => (str || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
        const query = norm(term).trim();
        const filtered = query ? this.allOccasions.filter(o => norm(o.title).includes(query)) : this.allOccasions;
        this.render(filtered, Boolean(query));
    }

    render(occasions, isSearch = false) {
        // Rendering is not disposal: keep search handlers and request generation intact.
        super.clear();
        if (!occasions?.length) {
            this.showStatus(isSearch ? UnitStrings.noSearchResults : UnitStrings.emptyCatalogue);
            if (isSearch) {
                const button = document.createElement('button');
                button.type = 'button';
                button.textContent = UnitStrings.clearSearch;
                button.onclick = () => this.clearSearch();
                this.host.querySelector('[data-catalog-status]').appendChild(button);
            }
            return;
        }
        const { present, upcoming, past, undated } = classifyOccasions(occasions);
        if (!present.length && !upcoming.length && !undated.length && !isSearch) this.showStatus(UnitStrings.onlyArchive);
        if (present.length) this.renderSection(UnitStrings.happeningNow, present, true);
        if (upcoming.length) this.renderSection(UnitStrings.upcomingEvents, upcoming);
        if (undated.length) this.renderSection(UnitStrings.otherEvents, undated);
        if (past.length) this.renderSection(UnitStrings.pastEvents, past, false, true);
    }

    renderSection(title, list, isPresent = false, isPast = false) {
        const section = document.createElement('section');
        section.className = isPast ? 'catalog-archive' : 'catalog-section';
        const titleEl = document.createElement('h2');
        titleEl.className = 'section-title';
        titleEl.textContent = title;
        section.appendChild(titleEl);
        const years = isPast ? groupPastOccasionsByYear(list) : [];
        if (years.length) {
            years.forEach(({ year, occasions }) => {
                const heading = document.createElement('h3');
                heading.className = 'catalog-year-title';
                heading.textContent = String(year);
                section.appendChild(heading);
                section.appendChild(this.createGrid(occasions, isPresent, isPast));
            });
        } else {
            section.appendChild(this.createGrid(list, isPresent, isPast));
        }
        this.host.appendChild(section);
    }

    createGrid(list, isPresent, isPast) {
        const grid = document.createElement('div');
        grid.className = 'catalog-grid';
        list.forEach(oc => grid.appendChild(OccasionCard.create(oc, isPresent, isPast)));
        return grid;
    }
}
