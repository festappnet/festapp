<?php
// Real installed packages, WordPress capabilities and gettext catalogs.
if ( ! defined( 'WP_CLI' ) || ! WP_CLI ) { exit( 1 ); }
global $onboarding_checks;
$onboarding_checks = 0;
function onboarding_assert( $condition, $label ) {
    global $onboarding_checks;
    ++$onboarding_checks;
    if ( ! $condition ) { WP_CLI::error( $label ); }
}
switch_to_locale( 'cs_CZ' );
foreach ( array( array( 'vstupenky-online', 'VstupenkyOnline', 'vstupenky.online' ), array( 'festapp-tickets', 'FestappTickets', 'Festapp Tickets' ) ) as $product ) {
    list( $slug, $namespace, $name ) = $product;
    wp_set_current_user( 1 );
    $links = apply_filters( 'plugin_action_links_' . $slug . '/' . $slug . '.php', array( 'Existing action' ) );
    onboarding_assert( 2 === count( $links ) && false !== strpos( $links[0], 'options-general.php?page=' . $slug ) && false !== strpos( $links[0], 'Začít' ), 'Discoverable localized onboarding for ' . $slug );
    onboarding_assert( 'Existing action' === $links[1], 'Existing plugin actions retained' );
    $plugin = get_plugin_data( WP_PLUGIN_DIR . '/' . $slug . '/' . $slug . '.php' );
    onboarding_assert( $name === $plugin['Name'], 'Plugin name contains no gettext context' );
    onboarding_assert( $name === _x( $name, 'block title', $slug ), 'Contextual Gutenberg block name translates' );
    onboarding_assert( false === strpos( _x( 'Sell tickets using a saved public ' . $name . ' form.', 'block description', $slug ), 'Sell tickets' ), 'Contextual Gutenberg description translates' );
    ob_start(); call_user_func( $namespace . '\admin_page' ); $html = ob_get_clean();
    onboarding_assert( 3 === substr_count( $html, 'class="card"' ) && false !== strpos( $html, 'post-new.php?post_type=page' ), 'Three steps and a native page creation action' );
    onboarding_assert( false === strpos( $html, '<iframe' ) && false === strpos( $html, '<script' ), 'Onboarding does not load the service' );
    $subscriber = get_user_by( 'login', 'vo-subscriber' );
    wp_set_current_user( $subscriber->ID );
    onboarding_assert( array( 'Existing action' ) === apply_filters( 'plugin_action_links_' . $slug . '/' . $slug . '.php', array( 'Existing action' ) ), 'Subscriber receives no admin setup action' );
}
restore_previous_locale();
WP_CLI::success( $onboarding_checks . ' onboarding and real gettext assertions' );
