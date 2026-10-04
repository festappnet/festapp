// FeatureConstants with a new constant for the ticket type.
class FeatureConstants {
  // Core keys
  static const String metaIsEnabled = "is_enabled";
  static const String metaCode = "code";
  static const String metaTitle = "title";
  static const String metaDescription = "description";

  // Feature codes
  static const String ticket = "ticket";
  static const String form = "form";
  static const String songbook = "songbook";
  static const String game = "game";
  static const String userGroups = "user_groups";
  static const String mySchedule = "my_schedule";
  static const String services = "services";
  static const String entryCode = "entry_code";
  static const String companions = "companions";
  static const String blueprint = "blueprint";
  static const String timetable = "timetable";
  static const String map = "map";
  static const String quotes = "quotes";
  static const String workshops = "workshops";
  static const String volunteers = "volunteers";
  static const String schedule = "schedule";
  static const String contract = "contract";
  static const String deposit = "deposit";
  static const String import = "import"; // New feature
  static const String globalSearch = "global_search";
  static const String eventFeedback = "event_feedback";
  static const String programNotifications = "program_notifications";
  // Counseling feature. Speakers themselves are core (no feature); the
  // "counseling" feature gates only the counseling flow (areas, slots,
  // rozcestník, booking window/limit). Replaces the retired "speakers" feature.
  static const String counseling = "counseling";
  // Cleaning service (úklidová služba): participants report toilet status,
  // the cleaning crew is notified and resolves reports. SimpleFeature (on/off).
  static const String cleaning = "cleaning";
  static const String reception = "reception";

  // Per-event flag (stored in events.data) toggling feedback for one event.
  static const String feedbackEnabled = "feedback_enabled";

  // Counseling feature config keys (occasions.features "counseling" element).
  static const String counselingEventType = "counseling_event_type";
  static const String counselingRegistrationStartTime =
      "registration_start_time";
  static const String counselingMaxActiveBookings = "max_active_bookings";

  // Per-event flags (stored in events.data).
  //   is_counseling_slot → generated counseling slot (filtered from timeline).
  //   counseling_entry   → event acts as the counseling entry point / rozcestník.
  static const String isCounselingSlot = "is_counseling_slot";
  static const String counselingEntry = "counseling_entry";
  static const String counselingDefaultEventType = "counseling";

  // Contract Feature
  static const String contractTransport = "transport";
  static const String contractDeparturePoint = "departure_point";
  static const String contractPlaceOfStay = "place_of_stay";
  static const String contractTourName = "tour_name";
  static const String contractTourDate = "tour_date";
  static const String contractNotes = "notes";
  static const String contractNumberOfDays = "number_of_days";
  static const String contractPaymentInfo = "payment_info";

  // Extra fields for ticket feature
  static const String ticketLightColor = "lightColor";
  static const String ticketDarkColor = "darkColor";
  static const String ticketBackground = "background";
  static const String ticketType = "ticket_type";
  static const String ticketLayout = "layout";
  static const String ticketCanScanManually = "can_scan_manually";
  static const String ticketShowHiddenNote = "show_hidden_note";

  // Extra fields for form feature
  static const String formUseExternal = "use_external_form";
  static const String formExternalLink = "external_form_link";
  static const String formExternalPrice = "external_price";
  static const String reserveButtonTitle = "reserve_button_title";
  static const String formShowPaymentQr = "show_payment_qr";
  static const String reminderIsEnabled = "reminder_is_enabled";
  static const String reminderIntervalSeconds = "reminder_interval_seconds";
  static const String deadlineDurationSeconds = "deadline_duration_seconds";

  // Extra field for companions feature
  static const String companionsMax = "max_companions";
  static const String companionsAllowUserCreate = "allow_user_create";
  static const String companionsAllowAdminAssign = "allow_admin_assign";

  // Extra fields for map feature
  static const String onlineMapLayer = "map_layer";
  static const String offlineMapLayer = "map_layer_offline";
  static const String defaultMapZoom = "defaultMapZoom";
  static const String defaultMapLocation = "defaultMapLocation";

  // Offline map extra fields (for offline map layer)
  static const String offlineMapPackageURL = "offlineMapPackageURL";
  static const String offlineMapStyleURL = "offlineMapStyleURL";
  static const String offlineMapLayerName = "offlineMapLayerName";
  static const String offlineMapRenderer = "offlineMapRenderer";
  static const String offlineMapBundleManifestURL =
      "offlineMapBundleManifestURL";
  static const String forceOfflineMap = "forceOfflineMap";

  // MapLayer inner keys (for online map layer)
  static const String mapLogo = "logo";
  static const String mapText = "text";
  static const String mapLogoLink = "logo_link";
  static const String mapTextLink = "text_link";
  static const String mapLayerLink = "layer_link";

  // Deposit Feature
  static const String depositDeadline = "deposit_deadline";
  static const String depositDeadlineDays = "deposit_deadline_days";
  static const String metaSurchargeDescription = "meta_surcharge_description";
  // Mutually exclusive deposit modes:
  //   "real"    → payment-linked deposit (default, backward-compat)
  //   "virtual" → visual-only meta doplatek (no payment impact, allows discounts)
  static const String depositMode = "deposit_mode";
  static const String depositModeReal = "real";
  static const String depositModeVirtual = "virtual";

  // Import Feature
  static const String importAutoImport = "auto_import";

  // Services (Inventory / "Pobyt") Feature
  // Mutually exclusive modes:
  //   "stay"            → accommodation and/or food capacity groups (default)
  //   "capacity_groups" → generic capacity groups only ("other" pool type)
  static const String servicesMode = "services_mode";
  static const String servicesModeStay = "stay";
  static const String servicesModeCapacityGroups = "capacity_groups";
  // Independent sub-toggles, only relevant in "stay" mode.
  static const String servicesAllowAccommodation = "allow_accommodation";
  static const String servicesAllowFood = "allow_food";
}
