#!/usr/bin/env ruby

require 'google/apis/androidpublisher_v3'
require 'googleauth'
require 'json'

expected_gateway = {
  'GITHUB_ACTIONS' => 'true',
  'GITHUB_REPOSITORY' => 'festappnet/festapp',
  'RUNNER_ENVIRONMENT' => 'github-hosted',
  'RUNNER_OS' => 'Linux'
}
abort 'Google Play readback is restricted to the Festapp GitHub-hosted Linux gateway' unless expected_gateway.all? { |name, value| ENV[name] == value }

manifest_value = ENV.fetch('FESTAPP_RELEASE_MANIFEST').strip
abort 'FESTAPP_RELEASE_MANIFEST must not be empty' if manifest_value.empty?
manifest_path = File.realpath(File.expand_path(manifest_value))
listing_root = File.dirname(manifest_path)
manifest = JSON.parse(File.read(manifest_path))
package_name = manifest.fetch('androidPackage')
google_play = manifest.fetch('googlePlay')
locale = google_play.fetch('locale')
metadata_root = File.expand_path(google_play.fetch('metadataDirectory'), listing_root)
abort 'Google Play metadata path escapes the listing root' unless metadata_root.start_with?("#{listing_root}#{File::SEPARATOR}")
expected_listing = {
  title: File.read(File.join(metadata_root, 'title.txt')).strip,
  short_description: File.read(File.join(metadata_root, 'short_description.txt')).strip,
  full_description: File.read(File.join(metadata_root, 'full_description.txt')).strip
}
credentials = File.realpath(File.expand_path(ENV.fetch('GOOGLE_PLAY_JSON_KEY')))
workspace = File.realpath(ENV.fetch('GITHUB_WORKSPACE'))
inside_workspace = credentials == workspace || credentials.start_with?(workspace + File::SEPARATOR)
abort 'Credential must remain outside the repository' if inside_workspace

service = Google::Apis::AndroidpublisherV3::AndroidPublisherService.new
service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open(credentials),
  scope: 'https://www.googleapis.com/auth/androidpublisher'
)

edit = service.insert_edit(package_name)
begin
  track = service.get_edit_track(package_name, edit.id, 'production')
  listing = service.get_edit_listing(package_name, edit.id, locale)
  image_types = %w[icon featureGraphic phoneScreenshots sevenInchScreenshots tenInchScreenshots]
  counts = image_types.to_h do |type|
    [type, Array(service.list_edit_images(package_name, edit.id, locale, type).images).size]
  end
  actual_listing = {
    title: listing.title.to_s.strip,
    short_description: listing.short_description.to_s.strip,
    full_description: listing.full_description.to_s.strip
  }
  abort 'Google Play listing differs from the canonical private metadata' unless actual_listing == expected_listing
  releases = Array(track.releases)
  puts JSON.generate(
    packageName: package_name,
    productionVersionCodes: releases.flat_map { |release| Array(release.version_codes) }.map(&:to_i).uniq.sort,
    productionStatuses: releases.map(&:status).uniq.sort,
    title: listing.title,
    canonicalListingMatches: true,
    images: counts
  )
ensure
  service.delete_edit(package_name, edit.id) if edit&.id
end
