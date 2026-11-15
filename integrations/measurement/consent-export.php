<?php
/**
 * Shared CMS envelope parser. Provider semantics belong to the service adapter.
 *
 * @package Festapp\CmsConsent
 */

namespace Festapp\CmsConsent;

use function parse_url as parse_origin_url;
if ( ! function_exists( __NAMESPACE__ . '\\parse_export' ) ) {
	/**
	 * Validate an exported envelope without interpreting provider consent.
	 *
	 * @param mixed    $input JSON input.
	 * @param string[] $allowed_origins Service origins owned by this product.
	 * @param string   $website_origin Actual website origin.
	 * @return array|null Normalized configuration or null.
	 */
	function parse_export( $input, array $allowed_origins, string $website_origin ): ?array {
		if ( ! is_string( $input ) || strlen( $input ) > 16384 || '' === $input ) {
			return null;
		}
		$v = json_decode( $input, true, 16 );
		if ( ! is_array( $v ) || ( $v['schemaVersion'] ?? null ) !== 1 ||
			! in_array( $v['serviceOrigin'] ?? null, $allowed_origins, true ) ||
			( $v['websiteOrigin'] ?? null ) !== $website_origin || ! origin( $website_origin ) ||
			! is_array( $v['binding'] ?? null ) || ! is_string( $v['binding']['id'] ?? null ) ||
			! preg_match( '/\A[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}\z/D', $v['binding']['id'] ) ||
			! positive_integer( $v['binding']['version'] ?? null ) ) {
			return null;
		}
		$c = $v['providerConfig'] ?? null;
		if ( ! is_array( $c ) || ! in_array( $c['provider'] ?? null, array( 'complianz', 'cookiebot', 'cookieconsent', 'wix' ), true ) ||
			! positive_integer( $c['organization'] ?? null ) || ! positive_integer( $c['unit'] ?? null ) ||
			! is_string( $c['consentRevision'] ?? null ) || ! preg_match( '/\A[a-f0-9]{32}\z/D', $c['consentRevision'] ) ||
			( $c['origin'] ?? null ) !== $website_origin ) {
			return null;
		}
		return array(
			'schemaVersion'  => 1,
			'serviceOrigin'  => $v['serviceOrigin'],
			'websiteOrigin'  => $website_origin,
			'binding'        => array(
				'id'      => $v['binding']['id'],
				'version' => $v['binding']['version'],
			),
			'providerConfig' => $c,
		);
	}
}
if ( ! function_exists( __NAMESPACE__ . '\\origin_from_url' ) ) {
		/**
		 * Read an origin while excluding CMS installation paths.
		 *
		 * @param string $url CMS website URL.
		 * @return string Validated origin or an empty string.
		 */
	function origin_from_url( string $url ): string {
		$p = parse_origin_url( $url );
		if ( ! is_array( $p ) || ( $p['scheme'] ?? '' ) !== 'https' || isset( $p['user'] ) || isset( $p['pass'] ) ) {
			return '';
		}
		$value = 'https://' . strtolower( $p['host'] ?? '' );
		if ( isset( $p['port'] ) && 443 !== $p['port'] ) {
			$value .= ':' . $p['port'];
		}
		return origin( $value ) ? $value : '';
	}
}
if ( ! function_exists( __NAMESPACE__ . '\\positive_integer' ) ) {
	/**
	 * Check that an identifier is a positive JavaScript-safe integer.
	 *
	 * @param mixed $value Candidate identifier.
	 * @return bool Whether the identifier is valid.
	 */
	function positive_integer( $value ): bool {
		return is_int( $value ) && $value > 0 && $value <= 9007199254740991;
	}
}
if ( ! function_exists( __NAMESPACE__ . '\\origin' ) ) {
	/**
	 * Validate a complete HTTPS origin.
	 *
	 * @param string $value Candidate origin.
	 * @return bool Whether the origin is valid.
	 */
	function origin( string $value ): bool {
		$p = parse_origin_url( $value );
		return is_array( $p ) && ( $p['scheme'] ?? '' ) === 'https' && ! isset( $p['user'], $p['pass'] ) &&
			! isset( $p['path'] ) && ! isset( $p['query'] ) && ! isset( $p['fragment'] ) &&
			preg_match( '/\Ahttps:\/\/[a-z0-9.-]+(?::[0-9]+)?\z/D', $value ) === 1;
	}
}
