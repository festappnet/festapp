<?php
/** Server export import. CMS owns local persistence, never consent semantics. */
namespace FestappTickets;
if ( ! defined( 'ABSPATH' ) ) { exit; }
require_once __DIR__ . '/consent-export.php';
function consent_settings() {
    $value = get_option( 'festapp-tickets_consent', array() );
    return is_array( $value ) ? $value : array();
}
function consent_config() {
    $value = consent_settings();
    return !empty( $value['enabled'] ) ? \Festapp\CmsConsent\parse_export( $value['export'] ?? '', allowed_origins(), \Festapp\CmsConsent\origin_from_url( home_url() ) ) : null;
}
function sanitize_consent_settings( $input ) {
    if ( !is_array( $input ) ) { return array(); }
    $raw = isset( $input['export'] ) && is_string( $input['export'] ) ? $input['export'] : '';
    $config = \Festapp\CmsConsent\parse_export( $raw, allowed_origins(), \Festapp\CmsConsent\origin_from_url( home_url() ) );
    if ( !$config && '' !== $raw ) { add_settings_error( 'festapp-tickets_consent', 'invalid_export', __( 'Import a valid export for this website from Festapp.', 'festapp-tickets' ) ); }
    return array( 'enabled' => !empty( $input['enabled'] ) && null !== $config, 'export' => $config ? wp_json_encode( $config, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE ) : '' );
}
function register_settings() {
    register_setting( 'festapp-tickets_consent', 'festapp-tickets_consent', array( 'type' => 'array', 'sanitize_callback' => __NAMESPACE__ . '\\sanitize_consent_settings', 'default' => array() ) );
}
function consent_script_attributes( $attributes ) {
    $config = consent_config();
    if ( !$config || !is_array( $attributes ) || ( $attributes['id'] ?? '' ) !== helper_handle( $config['serviceOrigin'] ) . '-js' ) { return $attributes; }
    $attributes['data-festapp-consent'] = wp_json_encode( $config, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE );
    if ( 'cookiebot' === $config['providerConfig']['provider'] ) { $attributes['data-cookieconsent'] = 'ignore'; }
    if ( 'complianz' === $config['providerConfig']['provider'] ) { $attributes['data-category'] = 'functional'; }
    return $attributes;
}
function helper_handle( $origin ) {
	return 'festapp-tickets-helper-' . substr( md5( $origin ), 0, 12 );
}

/**
 * Enqueue the service helper for one allowed origin.
 *
 * @param string $origin Service origin.
 */
function enqueue_helper( $origin ) {
	// Secondary loops enqueue before wp_footer prints. Service owns revalidation.
	// phpcs:disable WordPress.WP.EnqueuedResourceParameters.MissingVersion -- Service-owned protocol with revalidation.
	wp_enqueue_script(
		helper_handle( $origin ),
		$origin . '/embed.js',
		array(),
		null,
		array(
			'in_footer' => true,
			'strategy'  => 'defer',
		)
	);
	// phpcs:enable WordPress.WP.EnqueuedResourceParameters.MissingVersion
}


function form_link_html( $valid, $text, $classes = '' ) {
	$config = consent_config();
	$marked = $config && $config['serviceOrigin'] === $valid['origin'];
	if ( $marked ) { enqueue_helper( $valid['origin'] ); }
	return sprintf(
		'<a%s href="%s" target="_blank"%s>%s</a>',
		'' === $classes ? '' : ' class="' . esc_attr( $classes ) . '"',
		esc_url( $valid['url'] ),
		$marked ? ' data-festapp-consent-link' : ' rel="noopener noreferrer"',
		esc_html( $text )
	);
}

/**
 * Block renderer for a link or button opening the form in a new tab.
 *
 * @param array $attributes Block attributes.
 * @return string Escaped HTML.
 */
function render_link( $attributes ) {
	$link = link_markup( $attributes );
	return '' === $link ? '' : '<p class="festapp-tickets-form-link">' . $link . '</p>';
}

/**
 * Shortcode adapter for the form link.
 *
 * @param array|string $attributes Shortcode attributes.
 * @return string Rendered HTML.
 */
function link_shortcode( $attributes ) {
	return link_markup(
		shortcode_atts(
			array(
				'url'   => '',
				'text'  => '',
				'style' => 'button',
			),
			$attributes,
			'festapp_tickets_link'
		)
	);
}

/**
 * Shared link renderer.
 *
 * @param array $attributes Block or shortcode attributes.
 * @return string Escaped HTML.
 */
function link_markup( $attributes ) {
	$valid = validate_url( isset( $attributes['url'] ) ? $attributes['url'] : '' );
	if ( ! $valid ) {
		return '<span class="festapp-tickets-error">' . esc_html__( 'The form is not configured. Enter a saved public https://tickets.festapp.net/form/ URL without extra parameters.', 'festapp-tickets' ) . '</span>';
	}
	$text = isset( $attributes['text'] ) && is_string( $attributes['text'] ) ? trim( wp_strip_all_tags( $attributes['text'] ) ) : '';
	if ( '' === $text ) {
		$text = __( 'Buy tickets', 'festapp-tickets' );
	}
	$button = ! isset( $attributes['style'] ) || 'link' !== $attributes['style'];
	wp_enqueue_style( 'festapp-tickets' );
	return form_link_html( $valid, $text, $button ? 'wp-element-button festapp-tickets-button' : 'festapp-tickets-text-link' );
}
