<?php
/**
 * Public form validation and rendering.
 *
 * @package VstupenkyOnline
 */

namespace VstupenkyOnline;

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Deployment-owned origins. Never accepts public attributes or filter input.
 *
 * @return array Allowed service origins.
 */
function allowed_origins() {
	$origins = array( 'https://vstupenky.online' );
	// Local fixture requires two independent deployment-owned switches.
	if ( in_array( wp_get_environment_type(), array( 'local', 'development' ), true ) && defined( 'VSTUPENKY_ONLINE_DEV_ORIGIN' ) ) {
		$dev = VSTUPENKY_ONLINE_DEV_ORIGIN;
		if ( is_string( $dev ) && preg_match( '~\Ahttp://(?:127\.0\.0\.1|localhost):[1-9][0-9]{3,4}\z~D', $dev ) ) {
			$parts = wp_parse_url( $dev );
			if ( $parts && $parts['port'] <= 65535 ) {
				$origins[] = $dev;
			}
		}
	}
	return $origins;
}

/**
 * Validate without repairing an ambiguous or private input. No HTTP requests.
 *
 * @param mixed $input Public saved URL.
 * @return array|false Valid URL and origin, or false.
 */
function validate_url( $input ) {
	if ( ! is_string( $input ) || strlen( $input ) > 2048 ) {
		return false;
	}
	$origins = allowed_origins();
	foreach ( $origins as $origin ) {
		$prefix = $origin . '/form/';
		if ( 0 !== strpos( $input, $prefix ) ) {
			continue;
		}
		$slug    = substr( $input, strlen( $prefix ) );
		$decoded = rawurldecode( $slug );
		// Reject encoded separators, dot segments, whitespace and double encoding.
		if ( ! preg_match( '/\A[\p{L}\p{N}_-]+\z/uD', $decoded ) || rawurlencode( $decoded ) !== $slug ) {
			return false;
		}
		return array(
			'url'    => $input,
			'origin' => $origin,
		);
	}
	return false;
}

/**
 * Shortcode adapter.
 *
 * @param array|string $attributes Shortcode attributes.
 * @return string Rendered HTML.
 */
function shortcode( $attributes ) {
	return render(
		shortcode_atts(
			array(
				'url'           => '',
				'title'         => '',
				'mode'          => 'auto',
				'height'        => 800,
				'inherit_style' => 'true',
			),
			$attributes,
			'vstupenky_online'
		)
	);
}

/**
 * Shared renderer. Presentation cannot control service business rules.
 *
 * @param array $attributes Block or shortcode attributes.
 * @return string Escaped HTML.
 */
function render( $attributes ) {
	$valid = validate_url( isset( $attributes['url'] ) ? $attributes['url'] : '' );
	if ( ! $valid ) {
		return '<p class="vstupenky-online-error">' . esc_html__( 'The form is not configured. Enter a saved public https://vstupenky.online/form/ URL without extra parameters.', 'vstupenky-online' ) . '</p>';
	}
	$title = isset( $attributes['title'] ) && is_string( $attributes['title'] ) ? trim( wp_strip_all_tags( $attributes['title'] ) ) : '';
	if ( '' === $title ) {
		$title = __( 'Ticket sales - vstupenky.online', 'vstupenky-online' );
	}
	$height        = isset( $attributes['height'] ) && is_scalar( $attributes['height'] ) ? filter_var( $attributes['height'], FILTER_VALIDATE_INT ) : false;
	$height        = false !== $height && $height >= 240 && $height <= 4000 ? $height : 800;
	$auto          = ! isset( $attributes['mode'] ) || 'fixed' !== $attributes['mode'];
	$inherit_style = isset( $attributes['inheritStyle'] ) ? true === $attributes['inheritStyle'] : ( ! isset( $attributes['inherit_style'] ) || 'true' === $attributes['inherit_style'] );
	wp_enqueue_style( 'vstupenky-online' );
	if ( $auto || $inherit_style ) {
		$handle = 'vstupenky-online-helper-' . substr( md5( $valid['origin'] ), 0, 12 );
		// Secondary loops enqueue before wp_footer prints. Service owns revalidation.
		// phpcs:disable WordPress.WP.EnqueuedResourceParameters.MissingVersion -- Service-owned protocol with revalidation.
		wp_enqueue_script(
			$handle,
			$valid['origin'] . '/embed.js',
			array(),
			null,
			array(
				'in_footer' => true,
				'strategy'  => 'defer',
			)
		);
		// phpcs:enable WordPress.WP.EnqueuedResourceParameters.MissingVersion
	}
	return sprintf(
		'<div class="vstupenky-online" data-festapp-embed-host><iframe%s src="%s" title="%s" width="100%%" height="%d" style="border:0;max-width:100%%" loading="lazy"></iframe><p><a href="%s" target="_blank" rel="noopener noreferrer">%s</a></p></div>',
		( $auto || $inherit_style ? ' data-festapp-embed' : '' ) . ( ! $auto && $inherit_style ? ' data-festapp-height="fixed"' : '' ) . ( $inherit_style ? ' data-festapp-style="inherit"' : '' ),
		esc_url( $valid['url'] . '?embed=1' ),
		esc_attr( $title ),
		$height,
		esc_url( $valid['url'] ),
		esc_html__( 'Open the form in a new tab', 'vstupenky-online' )
	);
}
