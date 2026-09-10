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

package_name = ENV.fetch('PLAY_PACKAGE').strip
target_code = Integer(ENV.fetch('PLAY_EXPECTED_VERSION_CODE'), 10)
credentials = File.expand_path(ENV.fetch('GOOGLE_PLAY_JSON_KEY'))
abort 'Credential must remain outside the repository' if credentials.start_with?(File.expand_path('../..', __dir__) + File::SEPARATOR)

service = Google::Apis::AndroidpublisherV3::AndroidPublisherService.new
service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open(credentials),
  scope: 'https://www.googleapis.com/auth/androidpublisher'
)

edit = service.insert_edit(package_name)
begin
  releases = Array(service.get_edit_track(package_name, edit.id, 'production').releases)
  matching = releases.select { |release| Array(release.version_codes).map(&:to_i).include?(target_code) }
  abort "Production readback does not contain version code #{target_code}" if matching.empty?
  abort "Production version code #{target_code} is not completed" unless matching.any? { |release| release.status == 'completed' }
  puts JSON.generate(packageName: package_name, versionCode: target_code, status: 'completed')
ensure
  service.delete_edit(package_name, edit.id) if edit&.id
end
