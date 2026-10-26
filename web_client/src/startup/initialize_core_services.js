export async function initializeCoreServices({
    localizationService,
    supabaseService,
    rightsService,
    isAppSupported,
    publicEmbed = false,
}) {
    // Translation state must exist before Supabase/Rights listeners can render
    // custom elements. Otherwise an early context update leaks raw i18n keys.
    await localizationService.init();
    await supabaseService.initialize();
    if (!publicEmbed && !isAppSupported) await rightsService.updateAppData();
}
