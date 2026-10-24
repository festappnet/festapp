<?php
if ( ! defined('WP_CLI') || ! WP_CLI ) { exit(1); }
if ( FestappTickets\validate_url('http://127.0.0.1:59804/form/embedded-synthetic') !== false || !FestappTickets\validate_url('https://tickets.festapp.net/form/saved-slug') ) { WP_CLI::error('Global development origin escaped production gate'); }
if ( 'production' !== wp_get_environment_type() || VstupenkyOnline\validate_url('http://127.0.0.1:59801/form/embedded-synthetic') !== false || ! VstupenkyOnline\validate_url('https://vstupenky.online/form/saved-slug') ) {
    WP_CLI::error('Development origin escaped the production environment gate');
}
WP_CLI::success('Production rejects local fixture even when development origin constant is present');
