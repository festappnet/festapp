
export class FormStatsModel {
    constructor(data = {}) {
        this.total = data.total || 0;
        this.storno = data.storno || 0;
        this.paidOrSent = data.paid_or_sent || 0;
        this.ordered = data.ordered || 0;
    }
}

export class FormOptionModel {
    static metaValue = 'value';
    static metaDescription = 'description';
    static metaOptionsName = 'name';
    static metaOptionsId = 'id';
    static metaOptionsPrice = 'price';
    static metaOptionsPrice = 'price';
    static metaCurrency = 'currency_code';
    static metaData = 'data';

    constructor(data = {}) {
        this.title = data[FormOptionModel.metaValue] || '';
        this.description = data[FormOptionModel.metaDescription] || null;
        this.name = data[FormOptionModel.metaOptionsName] || null;
        this.id = data[FormOptionModel.metaOptionsId] || null;
        this.price = data[FormOptionModel.metaOptionsPrice] || 0;
        this.currency = data[FormOptionModel.metaCurrency];
        this.data = data[FormOptionModel.metaData] || null;
    }
}

export class FormFieldModel {
    static metaRequired = "required";
    static metaHidden = "hidden";
    static metaTitle = "title";
    static metaDescription = "description";
    static metaOptions = "options";

    constructor(data = {}) {
        this.id = data.id;
        this.createdAt = data.created_at ? new Date(data.created_at) : null;
        this.title = data.title;
        this.description = data.description;
        this.type = data.type;
        this.isRequired = data.is_required;
        this.isHidden = data.is_hidden;
        this.isTicketField = data.is_ticket_field;
        this.formId = data.form;
        this.order = data.order;
        this.productTypeId = data.product_type;
        this.data = data.data || {};
        this.productTypeData = data.product_type_data || this.data.product_type_data || null;
        
        if (this.data && this.data[FormFieldModel.metaFields]) {
             // Recursively create models for subfields (important for product logic)
             // Store back in data or a new property?
             // Let's store in a new property `subFields` for convenience, but keep data synced if possible.
             this.subFields = this.data[FormFieldModel.metaFields]
                 .map(f => new FormFieldModel(f))
                 .sort((a, b) => a.order - b.order);
        }

        this.options = [];
        // Standard Options
        if (this.data && this.data[FormFieldModel.metaOptions]) {
            this.options = this.data[FormFieldModel.metaOptions].map(o => new FormOptionModel(o));
        }

        // Product Type Options logic
        if (this.type === 'product_type' && this.productTypeData) {
            // Product type metadata is returned next to the form field by
            // get_form_by_link. Match the Flutter renderer and use its
            // description for the whole product choice section.
            this.description = this.productTypeData.description;

            const products = this.productTypeData.products || [];
             this.options = products.map(p => new FormOptionModel({
                 [FormOptionModel.metaValue]: p.title,
                 [FormOptionModel.metaDescription]: p.description,
                 [FormOptionModel.metaOptionsId]: p.id,
                 [FormOptionModel.metaOptionsPrice]: p.price,
                 [FormOptionModel.metaCurrency]: p.currency_code,
                 [FormOptionModel.metaData]: p.data
             }));
        }
    }
}

export class FormModel {
    static metaIsCardDesign = "is_card_design";
    static metaIsReminderEnabled = "is_reminder_enabled";
    static metaFields = "fields";
    static metaVariableSymbol = "variable_symbol";
    static metaPaymentMessage = "payment_message";
    static metaType = "type";
    static metaStartNumber = "starting_number";
    static metaStartTime = "start_time";
    static metaEndTime = "end_time";
    static metaEnableCountdown = "enable_countdown";
    static metaCountdownStyle = "countdown_style";
    static metaCountdownTitle = "countdown_title";
    static metaPrimaryColor = "primary_color";
    static metaSecondaryColor = "secondary_color";
    static metaFontFamily = "font_family";
    static metaDesign = "design";
    static metaSchedule = "schedule";
    static metaCommunicationTone = "communication_tone";

    constructor(data = {}) {
        this.id = data.id;
        this.createdAt = data.created_at ? new Date(data.created_at) : null;
        this.title = data.title;
        this.description = data.description;
        this.data = data.data || {};
        this.key = data.key;
        this.occasionId = data.occasion; // Occasion ID might come as integer or object depending on query
        this.blueprint = data.blueprint;
        this.type = data.type;
        this.bankAccountId = data.bank_account;
        this.deadlineDurationSeconds = data.deadline_duration_seconds;
        this.isOpen = data.is_open;
        this.accountNumber = data.account_number;
        this.secret = data.secret;
        this.header = data.header;
        this.headerOff = data.header_off;
        this.link = data.link;
        this.relatedFields = (data.fields || [])
            .map(f => new FormFieldModel(f))
            .sort((a, b) => a.order - b.order);

        // --- Flutter Parity Logic: Group `is_ticket_field` items into the Ticket field ---
        // 1. Identify ticket child fields
        const ticketChildFields = this.relatedFields
            .filter(f => f.isTicketField === true)
            .sort((a, b) => (a.order || 0) - (b.order || 0));

        // 2. Find the main ticket field
        const ticketField = this.relatedFields.find(f => f.type === 'ticket');
        
        if (ticketField) {
            // 3. Move them into the ticket field
            // Ensure subFields array exists
             if (!ticketField.subFields) ticketField.subFields = [];
             
             // Merge: We might have existing subFields from strict nesting (data.fields).
             // We append the flat `is_ticket_field` ones.
             // Avoid duplicates if they were already nested? 
             // FormFieldModel constructor recurses on `data.fields`.
             // If the backend sends them purely as flat fields with `is_ticket_field`, they won't be in `subFields` yet.
             // If they are sent BOTH ways, we need to check ID.
             
             ticketChildFields.forEach(child => {
                 if (!ticketField.subFields.some(existing => existing.id === child.id)) {
                     ticketField.subFields.push(child);
                 }
             });
             
             // 4. Sort the finalized list
             ticketField.subFields.sort((a, b) => (a.order || 0) - (b.order || 0));
        }

        const usesSeatSelection = [...this.relatedFields, ...(ticketField?.subFields || [])]
            .some(f => f.type === 'spot' && f.isHidden !== true);
        const usesRegularChoice = f =>
            !(f.type === 'spot' && f.isHidden === true) &&
            !(usesSeatSelection && f.type === 'product_type' && f.productTypeData?.type === 'spot');
        this.relatedFields = this.relatedFields.filter(usesRegularChoice);
        if (ticketField?.subFields) {
            ticketField.subFields = ticketField.subFields.filter(usesRegularChoice);
        }

        this.stats = data.stats ? new FormStatsModel(data.stats) : null;
        
        // Capture Features for FeatureService
        // Backend might send it in 'features' or inside 'occasion' object
        this.occasionFeatures = data.features || (data.occasion && data.occasion.features) || [];

        // Capture occasion start_time for deposit deadline calculation
        const occasionStartRaw = data.occasion && data.occasion.start_time;
        this.occasionStartTime = occasionStartRaw ? new Date(occasionStartRaw) : null;
    }

    get _designData() {
        if (!this.data[FormModel.metaDesign]) {
            this.data[FormModel.metaDesign] = {};
        }
        return this.data[FormModel.metaDesign];
    }

    get _scheduleData() {
        if (!this.data[FormModel.metaSchedule]) {
            this.data[FormModel.metaSchedule] = {};
        }
        return this.data[FormModel.metaSchedule];
    }

    get visibleFields() {
        // Collect IDs of fields that are children of other fields
        const childIds = new Set();
        this.relatedFields.forEach(f => {
             // Check if field has subfields defined in its data
             if (f.subFields && f.subFields.length > 0) {
                 f.subFields.forEach(sub => childIds.add(sub.id));
             }
        });
        
        return this.relatedFields.filter(f => !childIds.has(f.id) && f.isTicketField !== true);
    }

    get startTime() {
        const val = this._scheduleData[FormModel.metaStartTime];
        return val ? new Date(val) : null;
    }

    get endTime() {
        const val = this._scheduleData[FormModel.metaEndTime];
        return val ? new Date(val) : null;
    }

    get enableCountdown() {
        return this._scheduleData[FormModel.metaEnableCountdown] === true;
    }

    get countdownTitle() {
        return this._scheduleData[FormModel.metaCountdownTitle];
    }
    
    get isCardDesign() {
        return this._designData[FormModel.metaIsCardDesign] === true;
    }

    get primaryColor() {
        return this._parseColor(this._designData[FormModel.metaPrimaryColor]);
    }

    get secondaryColor() {
        return this._parseColor(this._designData[FormModel.metaSecondaryColor]);
    }

    get fontFamily() {
        return this._designData[FormModel.metaFontFamily];
    }
    
    get communicationTone() {
        return this.data[FormModel.metaCommunicationTone];
    }

    _parseColor(value) {
        if (!value) return null;
        if (typeof value === 'number') {
            // Convert int color to hex string #RRGGBB
            return '#' + (value & 0xFFFFFF).toString(16).padStart(6, '0');
        }
        if (typeof value === 'string') {
            if (value.startsWith('#') && value.length === 9) {
                // Assume ARGB (#AARRGGBB) and convert to RGBA (#RRGGBBAA)
                const alpha = value.substring(1, 3);
                const red = value.substring(3, 5);
                const green = value.substring(5, 7);
                const blue = value.substring(7, 9);
                return `#${red}${green}${blue}${alpha}`;
            }
            if (value.startsWith('#')) return value;
            return value; // Assume valid string
        }
        return null;
    }
}
