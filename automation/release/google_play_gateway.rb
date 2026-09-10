#!/usr/bin/env ruby

require 'digest'
require 'google/apis/androidpublisher_v3'
require 'googleauth'
require 'json'
require 'time'

def abort_unless(condition, message)
  abort message unless condition
end

expected_repository = ENV.fetch('PLAY_ALLOWED_REPOSITORY').strip
abort_unless(!expected_repository.empty?, 'PLAY_ALLOWED_REPOSITORY is required')
gateway = {
  'GITHUB_ACTIONS' => 'true',
  'GITHUB_REPOSITORY' => expected_repository,
  'RUNNER_ENVIRONMENT' => 'github-hosted',
  'RUNNER_OS' => 'Linux'
}
abort_unless(gateway.all? { |name, value| ENV[name] == value }, 'Google Play access is restricted to the authorized GitHub-hosted Linux gateway')

request_path = File.expand_path(ENV.fetch('PLAY_REQUEST_PATH'))
credential_path = File.expand_path(ENV.fetch('GOOGLE_PLAY_JSON_KEY'))
report_path = File.expand_path(ENV.fetch('PLAY_REPORT_PATH'))
repo_root = File.expand_path('../..', __dir__)
abort_unless(!request_path.start_with?(repo_root + File::SEPARATOR), 'Request must remain outside the repository')
abort_unless(!credential_path.start_with?(repo_root + File::SEPARATOR), 'Credential must remain outside the repository')
abort_unless(!report_path.start_with?(repo_root + File::SEPARATOR), 'Report must remain outside the repository')

request_bytes = File.binread(request_path)
request_sha = Digest::SHA256.hexdigest(request_bytes)
abort_unless(request_sha == ENV.fetch('PLAY_REQUEST_SHA256').downcase, 'Google Play request SHA-256 mismatch')
request = JSON.parse(request_bytes)
operation = ENV.fetch('PLAY_OPERATION')
package_name = ENV.fetch('PLAY_PACKAGE')
abort_unless(request['operation'] == operation, 'Operation selector mismatch')
abort_unless(request['packageName'] == package_name, 'Package selector mismatch')

service = Google::Apis::AndroidpublisherV3::AndroidPublisherService.new
service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
  json_key_io: File.open(credential_path),
  scope: 'https://www.googleapis.com/auth/androidpublisher'
)

def release_hash(release)
  {
    name: release.name,
    status: release.status,
    userFraction: release.user_fraction,
    versionCodes: Array(release.version_codes).map(&:to_i),
    releaseNotes: Array(release.release_notes).map { |note| { language: note.language, text: note.text } }
  }
end

def listing_hash(listing)
  {
    language: listing.language,
    title: listing.title,
    shortDescription: listing.short_description,
    fullDescription: listing.full_description,
    video: listing.video
  }
end

def review_hash(review)
  {
    reviewId: review.review_id,
    authorName: review.author_name,
    comments: Array(review.comments).map do |comment|
      user = comment.user_comment
      developer = comment.developer_comment
      {
        user: user && {
          text: user.text,
          starRating: user.star_rating,
          language: user.reviewer_language,
          appVersionCode: user.app_version_code,
          appVersionName: user.app_version_name,
          lastModified: user.last_modified && { seconds: user.last_modified.seconds, nanos: user.last_modified.nanos }
        },
        developer: developer && {
          text: developer.text,
          lastModified: developer.last_modified && { seconds: developer.last_modified.seconds, nanos: developer.last_modified.nanos }
        }
      }
    end
  }
end

def grant_hash(grant)
  {
    name: grant.name,
    packageName: grant.package_name,
    appLevelPermissions: Array(grant.app_level_permissions).sort
  }
end

def user_hash(user)
  {
    name: user.name,
    email: user.email,
    accessState: user.access_state,
    expirationTime: user.expiration_time,
    partial: user.partial,
    developerAccountPermissions: Array(user.developer_account_permissions).sort,
    grants: Array(user.grants).map { |grant| grant_hash(grant) }
  }
end

def with_disposable_edit(service, package_name)
  edit = service.insert_edit(package_name)
  committed = false
  begin
    result = yield edit, -> { committed = true }
    result
  ensure
    service.delete_edit(package_name, edit.id) unless committed
  end
end

def canonical_json(value)
  normalized = case value
               when Hash
                 value.keys.sort.each_with_object({}) { |key, result| result[key] = JSON.parse(canonical_json(value.fetch(key))) }
               when Array
                 value.map { |item| JSON.parse(canonical_json(item)) }
               else
                 value
               end
  JSON.generate(normalized)
end

def exact_confirmation!(request, prefix, identity, body)
  body_sha = Digest::SHA256.hexdigest(canonical_json(body))
  expected = ([prefix] + identity + [body_sha]).join('|')
  abort_unless(request['confirmation'] == expected, "Exact confirmation required: #{expected}")
  body_sha
end

report = {
  schemaVersion: 1,
  generatedAt: Time.now.utc.iso8601,
  repository: ENV.fetch('GITHUB_REPOSITORY'),
  runId: ENV.fetch('GITHUB_RUN_ID'),
  requestSha256: request_sha,
  operation: operation,
  packageName: package_name
}

case operation
when 'app.inspect'
  max_reviews = [[Integer(request.fetch('maxReviews', 20)), 1].max, 100].min
  report[:store] = with_disposable_edit(service, package_name) do |edit, _|
    listings = Array(service.list_edit_listings(package_name, edit.id).listings).map { |item| listing_hash(item) }
    tracks = Array(service.list_edit_tracks(package_name, edit.id).tracks).map do |track|
      { track: track.track, releases: Array(track.releases).map { |release| release_hash(release) } }
    end
    { listings: listings, tracks: tracks }
  end
  report[:reviews] = Array(service.list_reviews(package_name, max_results: max_reviews).reviews).map { |review| review_hash(review) }
when 'reviews.list'
  max_reviews = [[Integer(request.fetch('maxResults', 100)), 1].max, 100].min
  report[:reviews] = Array(service.list_reviews(package_name, max_results: max_reviews, translation_language: request['translationLanguage']).reviews).map { |review| review_hash(review) }
when 'listing.update'
  locale = String(request.fetch('language'))
  desired = request.fetch('listing').slice('title', 'shortDescription', 'fullDescription', 'video')
  exact_confirmation!(request, 'listing.update', [package_name, locale], desired)
  report[:before] = nil
  report[:after] = nil
  report[:changed] = false
  with_disposable_edit(service, package_name) do |edit, mark_committed|
    current = service.get_edit_listing(package_name, edit.id, locale)
    report[:before] = listing_hash(current)
    current_values = report[:before].transform_keys(&:to_s).slice(*desired.keys)
    next if current_values == desired
    replacement = report[:before].transform_keys(&:to_s).merge(desired)
    listing = Google::Apis::AndroidpublisherV3::Listing.new(
      language: locale,
      title: replacement['title'],
      short_description: replacement['shortDescription'],
      full_description: replacement['fullDescription'],
      video: replacement['video']
    )
    service.update_edit_listing(package_name, edit.id, locale, listing)
    service.validate_edit(package_name, edit.id)
    service.commit_edit(package_name, edit.id)
    mark_committed.call
    report[:changed] = true
  end
  report[:after] = with_disposable_edit(service, package_name) do |edit, _|
    listing_hash(service.get_edit_listing(package_name, edit.id, locale))
  end
  abort_unless(report[:after].transform_keys(&:to_s).slice(*desired.keys) == desired, 'Listing readback mismatch')
when 'review.reply'
  review_id = String(request.fetch('reviewId'))
  reply_text = String(request.fetch('replyText'))
  exact_confirmation!(request, 'review.reply', [package_name, review_id], { replyText: reply_text })
  service.reply_review(package_name, review_id, Google::Apis::AndroidpublisherV3::ReviewsReplyRequest.new(reply_text: reply_text))
  report[:review] = review_hash(service.get_review(package_name, review_id))
  developer_texts = Array(report.dig(:review, :comments)).filter_map { |comment| comment.dig(:developer, :text) }
  abort_unless(developer_texts.include?(reply_text), 'Review reply readback mismatch')
when 'users.inspect'
  developer_id = String(request.fetch('developerId'))
  parent = "developers/#{developer_id}"
  users = []
  token = nil
  loop do
    response = service.list_users(parent, page_size: 100, page_token: token)
    users.concat(Array(response.users))
    token = response.next_page_token
    break if token.nil? || token.empty?
  end
  report[:users] = users.map { |user| user_hash(user) }
when 'grant.update'
  developer_id = String(request.fetch('developerId'))
  email = String(request.fetch('email'))
  permissions = Array(request.fetch('appLevelPermissions')).map(&:to_s).uniq.sort
  exact_confirmation!(request, 'grant.update', [developer_id, email, package_name], { appLevelPermissions: permissions })
  user_name = "developers/#{developer_id}/users/#{email}"
  grant_name = "#{user_name}/grants/#{package_name}"
  grant = Google::Apis::AndroidpublisherV3::Grant.new(name: grant_name, package_name: package_name, app_level_permissions: permissions)
  begin
    updated = service.patch_grant(grant_name, grant, update_mask: 'appLevelPermissions')
  rescue Google::Apis::ClientError => error
    raise unless error.status_code == 404
    updated = service.create_grant(user_name, grant)
  end
  report[:grant] = grant_hash(updated)
  abort_unless(report.dig(:grant, :appLevelPermissions) == permissions, 'Grant readback mismatch')
else
  abort "Unsupported operation: #{operation}"
end

File.open(report_path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
  file.write(JSON.pretty_generate(report) + "\n")
end
summary = { operation: operation, packageName: package_name, requestSha256: request_sha, reportSha256: Digest::SHA256.file(report_path).hexdigest }
summary[:listingCount] = report.dig(:store, :listings)&.length if operation == 'app.inspect'
summary[:trackCount] = report.dig(:store, :tracks)&.length if operation == 'app.inspect'
summary[:reviewCount] = report[:reviews]&.length if %w[app.inspect reviews.list].include?(operation)
summary[:changed] = report[:changed] if operation == 'listing.update'
puts JSON.generate(summary)
