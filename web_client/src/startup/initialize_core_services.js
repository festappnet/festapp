export async function initializeCoreServices({
    localizationService,
    supabaseService,
    rightsService,
    isAppSupported,
    deferAppContext = false,
    onBackendReady = () => {},
}) {
    // Translation state must exist before Supabase/Rights listeners can render
    // custom elements. Otherwise an early context update leaks raw i18n keys.
    await localizationService.init();
    await supabaseService.initialize();
    onBackendReady();
    if (!deferAppContext && !isAppSupported) await rightsService.updateAppData();
}
