<?php
if ( ! defined( 'WP_CLI' ) || ! WP_CLI ) { exit( 1 ); }
$locale_switched = 'cs_CZ' !== get_locale() && switch_to_locale( 'cs_CZ' );
if ( 'cs_CZ' !== get_locale() ) { WP_CLI::error( 'Could not switch to the installed core cs_CZ language pack' ); }
foreach ( array( 'vstupenky-online', 'festapp-tickets' ) as $slug ) {
 if ( 'Vstupenky na vašem webu' !== __( 'Tickets on your website', $slug ) ) { WP_CLI::error( 'Czech PHP catalog did not load for ' . $slug ); }
 $json=load_script_textdomain($slug.'-editor',$slug,WP_PLUGIN_DIR.'/'.$slug.'/languages');
 if (false===$json || false===strpos($json,'Založit účet')) { WP_CLI::error('Czech editor catalog did not load for '.$slug); }
}
if ( false !== FestappTickets\validate_url('https://vstupenky.online/form/x') || false !== VstupenkyOnline\validate_url('https://tickets.festapp.net/form/x') ) { WP_CLI::error('Locale changed product identity'); }
if ( $locale_switched ) { restore_previous_locale(); }
WP_CLI::success('Both PHP and editor Czech catalogs actually load; changing language retains product/origin identity');
