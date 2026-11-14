<?php
/**
 * Optional transfer of the website's saved cookie choice to forms opened in a
 * new tab. WordPress only configures the service helper and marks links; the
 * service decides whether a choice is imported and fails closed otherwise.
 *
 * @package VstupenkyOnline
 */

namespace VstupenkyOnline;

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

const CONSENT_OPTION = 'vstupenky_online_consent_transfer';
const CONSENT_FIELDS = array( 'provider', 'organization', 'unit', 'consent_revision', 'policy_id', 'cbid', 'origin', 'consent_valid_from', 'max_age_seconds', 'revision', 'analytics_category', 'marketing_category' );

/**
 * Saved settings. They are the organizer's coverage assertion and are only
 * written by an administrator through the settings form.
 *
 * @return array
 */
function consent_settings() {
	$settings = get_option( CONSENT_OPTION, array() );
	return is_array( $settings ) ? $settings : array();
}

/**
 * Supported standard website consent banners.
 *
 * @return array Provider identifiers and names.
 */
function consent_providers() {
	return array(
		'complianz'     => 'Complianz',
		'cookiebot'     => 'Cookiebot',
		'cookieconsent' => 'CookieConsent v3 (orestbida)',
	);
}

/**
 * Validate settings exactly as the service helper does. Nothing is repaired
 * or derived from the incoming request.
 *
 * @param array $settings Saved or submitted settings.
 * @return array Field errors and the helper configuration, or null.
 */
function consent_validate( $settings ) {
	$errors   = array();
	$value    = function ( $key ) use ( $settings ) {
		return isset( $settings[ $key ] ) && is_string( $settings[ $key ] ) ? $settings[ $key ] : '';
	};
	$provider = $value( 'provider' );
	if ( ! isset( consent_providers()[ $provider ] ) ) {
		$errors['provider'] = __( 'Select the consent banner used on this website.', 'vstupenky-online' );
	}
	foreach ( array( 'organization', 'unit' ) as $key ) {
		if ( ! preg_match( '/\A[1-9][0-9]{0,14}\z/D', $value( $key ) ) ) {
			$errors[ $key ] = __( 'Enter a positive whole number.', 'vstupenky-online' );
		}
	}
	if ( ! preg_match( '/\A[a-f0-9]{32}\z/D', $value( 'consent_revision' ) ) ) {
		$errors['consent_revision'] = __( 'Enter the 32-character consent revision of the form.', 'vstupenky-online' );
	}
	$config = array(
		'provider'        => $provider,
		'organization'    => (int) $value( 'organization' ),
		'unit'            => (int) $value( 'unit' ),
		'consentRevision' => $value( 'consent_revision' ),
	);
	if ( 'complianz' === $provider ) {
		if ( ! preg_match( '/\A[1-9][0-9]{0,15}\z/D', $value( 'policy_id' ) ) ) {
			$errors['policy_id'] = __( 'Enter the Complianz policy ID as a positive whole number.', 'vstupenky-online' );
		}
		$config['policyId'] = $value( 'policy_id' );
	} elseif ( 'cookiebot' === $provider ) {
		if ( ! preg_match( '/\A[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}\z/D', $value( 'cbid' ) ) ) {
			$errors['cbid'] = __( 'Enter the Cookiebot domain group ID (CBID).', 'vstupenky-online' );
		}
		if ( ! is_https_origin( $value( 'origin' ) ) ) {
			$errors['origin'] = __( 'Enter the exact HTTPS origin of this website, without a path or trailing slash.', 'vstupenky-online' );
		}
		if ( ! is_utc_instant( $value( 'consent_valid_from' ) ) ) {
			$errors['consent_valid_from'] = __( 'Enter a UTC time such as 2026-11-11T00:00:00.000Z.', 'vstupenky-online' );
		}
		$max_age = $value( 'max_age_seconds' );
		if ( ! preg_match( '/\A[1-9][0-9]{0,7}\z/D', $max_age ) || (int) $max_age > 31536000 ) {
			$errors['max_age_seconds'] = __( 'Enter the consent lifetime in seconds, at most 31536000.', 'vstupenky-online' );
		}
		$config += array(
			'cbid'             => $value( 'cbid' ),
			'origin'           => $value( 'origin' ),
			'consentValidFrom' => $value( 'consent_valid_from' ),
			'maxAgeSeconds'    => (int) $max_age,
		);
	} elseif ( 'cookieconsent' === $provider ) {
		if ( ! preg_match( '/\A[1-9][0-9]{0,14}\z/D', $value( 'revision' ) ) ) {
			$errors['revision'] = __( 'Enter the CookieConsent revision as a positive whole number.', 'vstupenky-online' );
		}
		$config['revision'] = (int) $value( 'revision' );
		$analytics          = '' === $value( 'analytics_category' ) ? 'analytics' : $value( 'analytics_category' );
		$marketing          = '' === $value( 'marketing_category' ) ? 'marketing' : $value( 'marketing_category' );
		foreach ( array(
			'analytics_category' => $analytics,
			'marketing_category' => $marketing,
		) as $key => $category ) {
			if ( ! preg_match( '/\A[A-Za-z0-9_.:-]{1,128}\z/D', $category ) ) {
				$errors[ $key ] = __( 'Use letters, digits, dots, colons, hyphens or underscores.', 'vstupenky-online' );
			}
		}
		if ( $analytics === $marketing ) {
			$errors['marketing_category'] = __( 'Analytics and marketing need different categories.', 'vstupenky-online' );
		}
		if ( 'analytics' !== $analytics || 'marketing' !== $marketing ) {
			$config['categories'] = array(
				'analytics' => $analytics,
				'marketing' => $marketing,
			);
		}
	}
	return array(
		'errors' => $errors,
		'config' => $errors ? null : $config,
	);
}

/**
 * Exact HTTPS origin, as returned by the browser for location.origin.
 *
 * @param string $origin Candidate origin.
 * @return bool
 */
function is_https_origin( $origin ) {
	if ( ! preg_match( '~\Ahttps://([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*)(?::([1-9][0-9]{0,4}))?\z~D', $origin, $parts ) ) {
		return false;
	}
	return ! isset( $parts[2] ) || ( (int) $parts[2] <= 65535 && 443 !== (int) $parts[2] );
}

/**
 * Exact ISO 8601 UTC instant with milliseconds, as produced by toISOString().
 *
 * @param string $value Candidate instant.
 * @return bool
 */
function is_utc_instant( $value ) {
	if ( ! preg_match( '/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z\z/D', $value ) ) {
		return false;
	}
	$date = \DateTimeImmutable::createFromFormat( 'Y-m-d\TH:i:s.v\Z', $value, new \DateTimeZone( 'UTC' ) );
	return $date && $date->format( 'Y-m-d\TH:i:s.v\Z' ) === $value;
}

/**
 * Current instant in the format required for consentValidFrom.
 *
 * @return string
 */
function utc_now() {
	$now = \DateTimeImmutable::createFromFormat( 'U.u', sprintf( '%.6F', microtime( true ) ), new \DateTimeZone( 'UTC' ) );
	return $now->format( 'Y-m-d\TH:i:s.v\Z' );
}

/**
 * Helper configuration when the transfer is enabled and valid, otherwise null.
 *
 * @return array|null
 */
function consent_config() {
	$settings = consent_settings();
	if ( empty( $settings['enabled'] ) ) {
		return null;
	}
	return consent_validate( $settings )['config'];
}

/**
 * Service origin whose helper carries the configuration. A deployment-owned
 * local origin replaces production only in local or development WordPress.
 *
 * @return string
 */
function consent_origin() {
	$origins = allowed_origins();
	return end( $origins );
}

/**
 * Script handle shared with embeds, so each page prints one helper per origin.
 *
 * @param string $origin Service origin.
 * @return string
 */
function helper_handle( $origin ) {
	return 'vstupenky-online-helper-' . substr( md5( $origin ), 0, 12 );
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

/** Load the helper site-wide: marked links also live in menus and home pages. */
function enqueue_consent_helper() {
	if ( consent_config() ) {
		enqueue_helper( consent_origin() );
	}
}

/**
 * Add the configuration to the helper script tag.
 *
 * @param array $attributes Script tag attributes.
 * @return array
 */
function consent_script_attributes( $attributes ) {
	if ( ! is_array( $attributes ) || ! isset( $attributes['id'] ) || helper_handle( consent_origin() ) . '-js' !== $attributes['id'] ) {
		return $attributes;
	}
	$config = consent_config();
	if ( ! $config ) {
		return $attributes;
	}
	$attributes['data-festapp-consent'] = wp_json_encode( $config, JSON_UNESCAPED_SLASHES );
	if ( 'cookiebot' === $config['provider'] ) {
		// Cookiebot auto-blocking keeps the helper available.
		$attributes['data-cookieconsent'] = 'ignore';
	} elseif ( 'complianz' === $config['provider'] ) {
		// Complianz never blocks scripts marked as functional.
		$attributes['data-category'] = 'functional';
	}
	return $attributes;
}

/**
 * Whether a link may take part, using the same exceptions as the helper.
 *
 * @param mixed $href     Link URL.
 * @param mixed $target   Link target.
 * @param bool  $excluded Whether download or referrerpolicy is present.
 * @return bool
 */
function is_consent_link( $href, $target, $excluded ) {
	if ( $excluded || '_blank' !== $target ) {
		return false;
	}
	$valid = validate_url( $href );
	return $valid && consent_origin() === $valid['origin'];
}

/**
 * Remove only the tokens that would sever the opener channel.
 *
 * @param mixed $rel Link relationship value.
 * @return string Remaining tokens.
 */
function consent_rel( $rel ) {
	if ( ! is_string( $rel ) ) {
		return '';
	}
	$tokens = preg_split( '/\s+/', trim( $rel ), -1, PREG_SPLIT_NO_EMPTY );
	return implode(
		' ',
		array_filter(
			$tokens,
			function ( $token ) {
				return ! in_array( strtolower( $token ), array( 'noopener', 'noreferrer' ), true );
			}
		)
	);
}

/**
 * Mark new-tab links to public forms of this service in rendered HTML.
 *
 * @param mixed $html Rendered content.
 * @return mixed
 */
function mark_consent_links( $html ) {
	if ( ! is_string( $html ) || false === strpos( $html, consent_origin() . '/form/' ) || ! consent_config() ) {
		return $html;
	}
	$tags = new \WP_HTML_Tag_Processor( $html );
	while ( $tags->next_tag( 'a' ) ) {
		$excluded = null !== $tags->get_attribute( 'download' ) || null !== $tags->get_attribute( 'referrerpolicy' );
		if ( ! is_consent_link( $tags->get_attribute( 'href' ), $tags->get_attribute( 'target' ), $excluded ) ) {
			continue;
		}
		$rel = consent_rel( $tags->get_attribute( 'rel' ) );
		if ( '' === $rel ) {
			$tags->remove_attribute( 'rel' );
		} else {
			$tags->set_attribute( 'rel', $rel );
		}
		$tags->set_attribute( 'data-festapp-consent-link', true );
	}
	return $tags->get_updated_html();
}

/**
 * Block filter adapter.
 *
 * @param mixed $html Rendered block.
 * @return mixed
 */
function mark_block_links( $html ) {
	return mark_consent_links( $html );
}

/**
 * Classic menu adapter.
 *
 * @param array $atts Menu link attributes.
 * @return array
 */
function mark_menu_link( $atts ) {
	if ( ! is_array( $atts ) || ! consent_config() || ! isset( $atts['href'], $atts['target'] ) ) {
		return $atts;
	}
	if ( ! is_consent_link( $atts['href'], $atts['target'], ! empty( $atts['download'] ) || ! empty( $atts['referrerpolicy'] ) ) ) {
		return $atts;
	}
	// The menu walker omits empty values: an empty rel is dropped, the marker is kept.
	$atts['rel']                       = consent_rel( isset( $atts['rel'] ) ? $atts['rel'] : '' );
	$atts['data-festapp-consent-link'] = '1';
	return $atts;
}

/**
 * Markup of a link to the standalone form.
 *
 * @param array  $valid Validated form URL.
 * @param string $text  Visible text, unescaped.
 * @param string $classes CSS classes.
 * @return string Escaped HTML.
 */
function form_link_html( $valid, $text, $classes = '' ) {
	$marked = consent_config() && consent_origin() === $valid['origin'];
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
	return '' === $link ? '' : '<p class="vstupenky-online-form-link">' . $link . '</p>';
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
			'vstupenky_online_link'
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
		return '<span class="vstupenky-online-error">' . esc_html__( 'The form is not configured. Enter a saved public https://vstupenky.online/form/ URL without extra parameters.', 'vstupenky-online' ) . '</span>';
	}
	$text = isset( $attributes['text'] ) && is_string( $attributes['text'] ) ? trim( wp_strip_all_tags( $attributes['text'] ) ) : '';
	if ( '' === $text ) {
		$text = __( 'Buy tickets', 'vstupenky-online' );
	}
	$button = ! isset( $attributes['style'] ) || 'link' !== $attributes['style'];
	wp_enqueue_style( 'vstupenky-online' );
	return form_link_html( $valid, $text, $button ? 'wp-element-button vstupenky-online-button' : 'vstupenky-online-text-link' );
}

/**
 * Value detected from an active consent plugin. Only a suggestion: it is
 * never saved without an explicit administrator action.
 *
 * @param string $field Settings field.
 * @return string Detected value or an empty string.
 */
function detected_consent_value( $field ) {
	if ( 'policy_id' === $field && defined( 'CMPLZ_VERSION' ) ) {
		$policy = class_exists( '\COMPLIANZ' ) && isset( \COMPLIANZ::$banner_loader ) && is_object( \COMPLIANZ::$banner_loader ) && method_exists( \COMPLIANZ::$banner_loader, 'get_active_policy_id' )
			? \COMPLIANZ::$banner_loader->get_active_policy_id() : get_option( 'complianz_active_policy_id', 1 );
		$policy = is_scalar( $policy ) ? (string) $policy : '';
		return preg_match( '/\A[1-9][0-9]{0,15}\z/D', $policy ) ? $policy : '';
	}
	if ( 'cbid' === $field && defined( 'CYBOT_COOKIEBOT_VERSION' ) ) {
		$cbid = class_exists( '\cybot\cookiebot\lib\Cookiebot_WP' ) && method_exists( '\cybot\cookiebot\lib\Cookiebot_WP', 'get_cbid' )
			? \cybot\cookiebot\lib\Cookiebot_WP::get_cbid() : get_option( 'cookiebot-cbid', '' );
		$cbid = is_string( $cbid ) ? strtolower( trim( $cbid ) ) : '';
		return preg_match( '/\A[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}\z/D', $cbid ) ? $cbid : '';
	}
	if ( 'origin' === $field ) {
		$parts = wp_parse_url( home_url() );
		if ( ! is_array( $parts ) || ! isset( $parts['scheme'], $parts['host'] ) ) {
			return '';
		}
		$origin = strtolower( $parts['scheme'] . '://' . $parts['host'] ) . ( isset( $parts['port'] ) ? ':' . $parts['port'] : '' );
		return is_https_origin( $origin ) ? $origin : '';
	}
	return '';
}

/**
 * Differences between the saved assertion and the live website, if any.
 *
 * @return array Field => detected value.
 */
function consent_mismatches() {
	$settings = consent_settings();
	if ( empty( $settings['enabled'] ) || ! isset( $settings['provider'] ) ) {
		return array();
	}
	$fields     = 'complianz' === $settings['provider'] ? array( 'policy_id' ) : ( 'cookiebot' === $settings['provider'] ? array( 'cbid', 'origin' ) : array() );
	$mismatches = array();
	foreach ( $fields as $field ) {
		$detected = detected_consent_value( $field );
		if ( '' !== $detected && ( ! isset( $settings[ $field ] ) || $detected !== $settings[ $field ] ) ) {
			$mismatches[ $field ] = $detected;
		}
	}
	return $mismatches;
}

/**
 * Settings API sanitizer. Applies a detected value only for the field whose
 * button the administrator clicked, and stores enabled only for valid input.
 *
 * @param mixed $input Submitted settings.
 * @return array
 */
function sanitize_consent_settings( $input ) {
	$input    = is_array( $input ) ? $input : array();
	$settings = array( 'enabled' => ! empty( $input['enabled'] ) );
	foreach ( CONSENT_FIELDS as $field ) {
		$value              = isset( $input[ $field ] ) && is_scalar( $input[ $field ] ) ? trim( sanitize_text_field( (string) $input[ $field ] ) ) : '';
		$settings[ $field ] = in_array( $field, array( 'consent_revision', 'cbid', 'origin' ), true ) ? strtolower( $value ) : $value;
	}
	$adopt = isset( $input['adopt'] ) && is_string( $input['adopt'] ) ? $input['adopt'] : '';
	if ( in_array( $adopt, array( 'policy_id', 'cbid', 'origin' ), true ) && '' !== detected_consent_value( $adopt ) ) {
		$settings[ $adopt ] = detected_consent_value( $adopt );
	}
	if ( 'cookiebot' === $settings['provider'] && ( 'consent_valid_from' === $adopt || '' === $settings['consent_valid_from'] ) ) {
		// The notice applies from this confirmation; earlier choices do not transfer.
		$settings['consent_valid_from'] = utc_now();
	}
	$result = consent_validate( $settings );
	if ( $settings['enabled'] && $result['errors'] ) {
		$settings['enabled'] = false;
		if ( ! get_settings_errors( CONSENT_OPTION ) ) {
			add_settings_error( CONSENT_OPTION, 'invalid', __( 'Cookie choice transfer stays off until every required field is valid.', 'vstupenky-online' ) );
		}
	}
	return $settings;
}
