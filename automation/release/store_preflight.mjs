import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { parseProjectVersion } from './project_version.mjs';
import { storeManifestShapeErrors } from './store_manifest_contract.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const manifestValue = process.env.FESTAPP_RELEASE_MANIFEST?.trim();
if (!manifestValue) {
  console.error('ERROR: Set FESTAPP_RELEASE_MANIFEST to the private release config.json.');
  process.exit(1);
}
const manifestPath = path.resolve(manifestValue);
if (!fs.existsSync(manifestPath)) {
  console.error(`ERROR: missing release manifest ${manifestPath}`);
  process.exit(1);
}
const listingRoot = path.dirname(fs.realpathSync(manifestPath));
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const errors = [];
const warnings = [];
const fail = (message) => errors.push(message);
const requireFile = (relative) => fs.existsSync(path.join(root, relative)) || fail(`missing ${relative}`);
const listingPath = (relative) => {
  const resolved = path.resolve(listingRoot, relative);
  if (resolved !== listingRoot && !resolved.startsWith(`${listingRoot}${path.sep}`)) {
    fail(`release path escapes listing root: ${relative}`);
  }
  return resolved;
};
const requireListingFile = (relative) => fs.existsSync(listingPath(relative)) || fail(`missing release file ${relative}`);

for (const error of storeManifestShapeErrors(manifest)) fail(error);
if (errors.length) {
  for (const error of errors) console.error(`ERROR: ${error}`);
  process.exit(1);
}

if (!process.argv.includes('--local') || !process.argv.includes('--read-only')) {
  fail('preflight must be invoked with --local --read-only');
}
if (manifest.schemaVersion !== 2) fail('unsupported app-store manifest schema');
if (!/^\d+$/.test(manifest.appleId ?? '') || !manifest.bundleId) fail('immutable Apple identity is missing');
if (!manifest.signingTeamId) fail('signing team is missing');
if (manifest.releaseMode !== 'automatic_after_approval') fail('release mode must be automatic after Apple approval');

const review = manifest.review;
if (!review?.contact?.firstName || !review?.contact?.lastName || !review?.contact?.email || !review?.contact?.phone) {
  fail('canonical reviewer contact is incomplete');
}
if (!review?.demoAccount?.email || !review?.demoAccount?.authEmail || !review?.demoAccount?.passwordKeychainService) {
  fail('canonical reviewer demo account is incomplete');
}
if (!review?.notesPath) fail('canonical reviewer notes path is missing');
else requireListingFile(review.notesPath);

const classification = manifest.storeClassification;
if (!classification?.primaryCategory || !classification?.secondaryCategory) fail('store categories are incomplete');
if (!classification?.contentRights) fail('content-rights decision is missing');
if (typeof classification?.availableInNewTerritories !== 'boolean') fail('new-territory availability decision is missing');
if (!Number.isInteger(classification?.availability?.currentCountryOrRegionCount) ||
    !classification?.availability?.chinaMainland ||
    !/^\d{4}-\d{2}-\d{2}$/.test(classification?.availability?.confirmedInAppStoreConnectAt ?? '')) {
  fail('country-availability decision is incomplete');
}
const expectedBooleanAgeAnswers = [
  'advertising', 'ageAssurance', 'gambling', 'healthOrWellnessTopics', 'lootBox',
  'messagingAndChat', 'parentalControls', 'unrestrictedWebAccess', 'userGeneratedContent',
  'socialMedia', 'socialMediaDisabledForUsersUnder13',
];
for (const field of expectedBooleanAgeAnswers) {
  if (classification?.ageRating?.[field] !== false) fail(`age-rating ${field} must be false`);
}
const appPrivacy = manifest.appPrivacy;
if (!appPrivacy?.entryMode || typeof appPrivacy?.approvalRequired !== 'boolean' ||
    typeof appPrivacy?.published !== 'boolean' ||
    (appPrivacy.published && !/^\d{4}-\d{2}-\d{2}$/.test(appPrivacy.lastPublishedAt ?? ''))) {
  fail('App Privacy publication state is incomplete');
}
if (!appPrivacy?.questionnairePath) fail('App Privacy questionnaire path is missing');
else requireListingFile(appPrivacy.questionnairePath);
const dsa = manifest.dsa;
if (!dsa?.publisher || !dsa?.accountEnrollment || !dsa?.traderStatus ||
    typeof dsa?.commercialization !== 'boolean' ||
    typeof dsa?.organizerRelationshipRelevant !== 'boolean' ||
    typeof dsa?.manualAscConfirmationRequired !== 'boolean' ||
    !/^\d{4}-\d{2}-\d{2}$/.test(dsa?.confirmedInAppStoreConnectAt ?? '')) {
  fail('DSA decision state is incomplete');
}
const expectedNoneAgeAnswers = [
  'ageRatingOverrideV2', 'alcoholTobaccoOrDrugUseOrReferences', 'contests',
  'gamblingSimulated', 'gunsOrOtherWeapons', 'horrorOrFearThemes',
  'koreaAgeRatingOverride', 'matureOrSuggestiveThemes',
  'medicalOrTreatmentInformation', 'profanityOrCrudeHumor',
  'sexualContentGraphicAndNudity', 'sexualContentOrNudity',
  'violenceCartoonOrFantasy', 'violenceRealistic',
  'violenceRealisticProlongedGraphicOrSadistic',
];
for (const field of expectedNoneAgeAnswers) {
  if (typeof classification?.ageRating?.[field] !== 'string' || !classification.ageRating[field]) {
    fail(`age-rating ${field} must be a non-empty enum value`);
  }
}

const config = fs.readFileSync(path.join(root, 'automation/project.conf'), 'utf8');
const getConfig = (key) => config.match(new RegExp(`^${key}=(?:"([^"]*)"|(.*))$`, 'm'))?.slice(1).find((v) => v !== undefined)?.trim();
if (getConfig('APP_NAME') !== manifest.target.name) fail('project.conf APP_NAME disagrees with manifest');
if (getConfig('DOMAIN') !== new URL(manifest.urls.marketing).hostname) fail('project.conf DOMAIN disagrees with manifest');
for (const [configKey, manifestUrl] of [
  ['PRIVACY_URL', manifest.urls.privacy],
  ['PRIVACY_CHOICES_URL', manifest.urls.privacyChoices],
  ['SUPPORT_URL', manifest.urls.support],
]) {
  if (getConfig(configKey) !== manifestUrl) fail(`project.conf ${configKey} disagrees with manifest`);
}
try {
  parseProjectVersion(config);
} catch (error) {
  fail(error.message);
}
if ('version' in manifest.target || 'build' in manifest.target) {
  fail('app-store manifest must not duplicate the canonical project version or build number');
}

const project = fs.readFileSync(path.join(root, 'ios/Runner.xcodeproj/project.pbxproj'), 'utf8');
if (!project.includes(`PRODUCT_BUNDLE_IDENTIFIER = ${manifest.bundleId};`)) fail('main bundle identifier disagrees with manifest');
if (!project.includes(`DEVELOPMENT_TEAM = ${manifest.signingTeamId};`)) fail('signing team disagrees with manifest');
const runnerInfo = fs.readFileSync(path.join(root, 'ios/Runner/Info.plist'), 'utf8');
const whenInUse = runnerInfo.match(/<key>NSLocationWhenInUseUsageDescription<\/key>\s*<string>([^<]+)<\/string>/);
if (!whenInUse?.[1]?.trim()) fail('Runner Info.plist is missing a non-empty NSLocationWhenInUseUsageDescription');
const alwaysAndWhenInUse = runnerInfo.match(/<key>NSLocationAlwaysAndWhenInUseUsageDescription<\/key>\s*<string>([^<]+)<\/string>/);
if (!alwaysAndWhenInUse?.[1]?.trim()) {
  fail('Runner Info.plist is missing NSLocationAlwaysAndWhenInUseUsageDescription required by MapLibre');
}
const podfile = fs.readFileSync(path.join(root, 'ios/Podfile'), 'utf8');
if (!/target\.name == ['"]geolocator_apple['"]/.test(podfile) ||
    !/BYPASS_PERMISSION_LOCATION_ALWAYS=1/.test(podfile)) {
  fail('geolocator_apple must compile with the background-location permission bypass');
}
if (!/ENV\[['"]ONESIGNAL_DISABLE_LOCATION['"]\]\s*=\s*['"]true['"]/.test(podfile) ||
    !/pod ['"]OneSignalXCFramework\/OneSignal['"], ['"]5\.5\.5['"]/.test(podfile) ||
    !/pod ['"]OneSignalXCFramework\/OneSignalInAppMessages['"], ['"]5\.5\.5['"]/.test(podfile)) {
  fail('OneSignal must resolve without its unused native location module');
}
const notificationExtensionInfo = fs.readFileSync(
  path.join(root, 'ios/OneSignalNotificationServiceExtension/Info.plist'),
  'utf8',
);
for (const key of ['CFBundleShortVersionString', 'CFBundleVersion']) {
  if (!notificationExtensionInfo.includes(`<key>${key}</key>`)) {
    fail(`notification extension Info.plist is missing ${key}`);
  }
}
for (const configuration of ['Debug', 'Release', 'Profile']) {
  const name = `OneSignalExtension${configuration}.xcconfig`;
  const relative = path.join('ios', 'Flutter', name);
  requireFile(relative);
  if (fs.existsSync(path.join(root, relative))) {
    const contents = fs.readFileSync(path.join(root, relative), 'utf8');
    if (!contents.includes('Generated.xcconfig')) {
      fail(`${name} does not inherit the Flutter app version`);
    }
  }
  if (!new RegExp(`baseConfigurationReference = [^;]+ /\\* ${name.replace('.', '\\.')} \\*/;`).test(project)) {
    fail(`notification extension ${configuration} configuration does not use ${name}`);
  }
}
const fastfile = fs.readFileSync(path.join(root, 'automation/release/fastlane/Fastfile'), 'utf8');
if (/produce\s*\(|lane\s+:publish_ipa/.test(fastfile)) fail('unsafe app creation or monolithic release path found');
const submitLane = fastfile.match(/lane :submit_for_review do([\s\S]*?)^  end/m)?.[1] ?? '';
const replaceScreenshotsLane = fastfile.match(/lane :replace_screenshots do([\s\S]*?)^  end/m)?.[1] ?? '';
const selectBuildLane = fastfile.match(/lane :select_build do([\s\S]*?)^  end/m)?.[1] ?? '';
const cancelReviewLane = fastfile.match(/lane :cancel_review_submission do([\s\S]*?)^  end/m)?.[1] ?? '';
if (!/exact_gate!\('SELECT_BUILD'\)/.test(selectBuildLane) ||
    !/Build\.all/.test(selectBuildLane) || !/processing_state/.test(selectBuildLane) ||
    !/select_build\(build_id: build\.id\)/.test(selectBuildLane)) {
  fail('build selection must be an exact gated processed-build operation');
}
if (!/exact_gate!\('CANCEL_REVIEW_SUBMISSION'\)/.test(cancelReviewLane) ||
    !/get_in_progress_review_submission/.test(cancelReviewLane) ||
    !/cancel_submission/.test(cancelReviewLane)) {
  fail('review cancellation must be an exact gated target operation');
}
if (/lane\s+:upload_screenshots/.test(fastfile) ||
    !/exact_gate!\('REPLACE_SCREENSHOTS'\)/.test(replaceScreenshotsLane) ||
    !/locale_staging\s*=\s*File\.join\(staging,\s*MANIFEST\.fetch\('target'\)\.fetch\('locale'\)\)/.test(replaceScreenshotsLane) ||
    !/overwrite_screenshots:\s*true/.test(replaceScreenshotsLane) ||
    !/sync_screenshots:\s*true/.test(replaceScreenshotsLane)) {
  fail('screenshot replacement must use the exact gated locale-aware canonical lane');
}
if (!/automatic_release:\s*true/.test(submitLane) || /automatic_release:\s*false/.test(submitLane) ||
    !/release_type:\s*Spaceship::ConnectAPI::AppStoreVersion::ReleaseType::AFTER_APPROVAL/.test(submitLane) ||
    !/configured&?\.release_type\s*==\s*Spaceship::ConnectAPI::AppStoreVersion::ReleaseType::AFTER_APPROVAL/.test(submitLane) ||
    !/submitted&?\.release_type\s*==\s*Spaceship::ConnectAPI::AppStoreVersion::ReleaseType::AFTER_APPROVAL/.test(submitLane)) {
  fail('Fastlane submission must use automatic release after Apple approval');
}
if (/release_approved_version|manual ASC action/.test(fastfile)) fail('obsolete manual release path found');
if (review?.demoAccount?.authEmail && fastfile.includes(review.demoAccount.authEmail) ||
    review?.contact?.email && fastfile.includes(review.contact.email) ||
    review?.demoAccount?.passwordKeychainService && fastfile.includes(review.demoAccount.passwordKeychainService)) {
  fail('Fastfile duplicates app-specific reviewer configuration');
}

for (const file of [
  'web/privacy/index.html', 'web/privacy/choices/index.html', 'web/terms/index.html',
  'web/apple-app-site-association', 'web/.well-known/apple-app-site-association',
]) requireFile(file);
const legalCheck = spawnSync(process.execPath, [
  path.join(root, 'automation/release/render_legal_pages.mjs'), '--check',
], { encoding: 'utf8' });
if (legalCheck.status !== 0) fail(legalCheck.stderr.trim() || 'generated legal pages are stale');
const legal = manifest.legal;
if (!legal?.sourceDirectory || !legal?.privacyPolicyVersion ||
    !/^\d{4}-\d{2}-\d{2}$/.test(legal?.effectiveDate ?? '') || !legal?.privacyContact ||
    typeof legal?.approvalRequired !== 'boolean' || typeof legal?.productionDeploymentRequired !== 'boolean') {
  fail('legal publication state is incomplete');
}
if (legal && !legal.productionDeploymentRequired &&
    (!/^\d{4}-\d{2}-\d{2}$/.test(legal.productionDeployedAt ?? '') || !legal.productionDeploymentId)) {
  fail('completed legal deployment lacks its receipt');
}

const appleMetadataDirectory = manifest.apple?.metadataDirectory;
if (!appleMetadataDirectory) fail('Apple metadata directory is missing');
const appleStoreName = manifest.apple?.storeName;
if (typeof appleStoreName !== 'string' || !appleStoreName.trim()) {
  fail('Apple store name is missing');
}
const appleMetadataRoot = listingPath(appleMetadataDirectory ?? '.');
const metadataDir = path.join(appleMetadataRoot, manifest.target.locale);
const copyrightFile = path.join(appleMetadataRoot, 'copyright.txt');
if (!fs.existsSync(copyrightFile) || !/^\d{4}\s+\S.+/.test(fs.readFileSync(copyrightFile, 'utf8').trim())) {
  fail('App Store copyright must contain a four-digit year and rights holder');
}
const limits = { name: 30, subtitle: 30, keywords: 100, promotional_text: 170, description: 4000, release_notes: 4000 };
for (const [name, limit] of Object.entries(limits)) {
  const file = path.join(metadataDir, `${name}.txt`);
  if (!fs.existsSync(file)) { fail(`missing metadata ${manifest.target.locale}/${name}.txt`); continue; }
  const content = fs.readFileSync(file, 'utf8').trim();
  if (!content || [...content].length > limit) fail(`metadata ${name} must be 1..${limit} characters`);
  if (name === 'name' && content !== appleStoreName) fail('metadata name disagrees with apple.storeName');
}
for (const [field, expected] of [['privacy_url', manifest.urls.privacy], ['privacy_choices_url', manifest.urls.privacyChoices], ['support_url', manifest.urls.support], ['marketing_url', manifest.urls.marketing]]) {
  const value = fs.readFileSync(path.join(metadataDir, `${field}.txt`), 'utf8').trim();
  if (value !== expected) fail(`${field} disagrees with manifest`);
}

function pngInfo(file) {
  const data = fs.readFileSync(file);
  if (data.toString('hex', 0, 8) !== '89504e470d0a1a0a') throw new Error('not PNG');
  return { width: data.readUInt32BE(16), height: data.readUInt32BE(20), colorType: data[25] };
}
for (const [device, rule] of Object.entries(manifest.screenshots)) {
  const screenshotRoot = rule.sourceDirectory ? listingPath(rule.sourceDirectory) : undefined;
  const files = screenshotRoot && fs.existsSync(screenshotRoot)
    ? fs.readdirSync(screenshotRoot).filter((file) => file.endsWith('.png')).sort()
    : [];
  if (files.length < rule.minimumCount) {
    fail(`final ${device} screenshots missing: need at least ${rule.minimumCount}`);
    continue;
  }
  for (const name of files) {
    try {
      const info = pngInfo(path.join(screenshotRoot, name));
      if (info.width !== rule.width || info.height !== rule.height) fail(`${name} has ${info.width}x${info.height}`);
      if ([4, 6].includes(info.colorType)) fail(`${name} contains alpha`);
    } catch (error) { fail(`${name}: ${error.message}`); }
  }
}
const icon = path.join(root, 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png');
try {
  const info = pngInfo(icon);
  if (info.width !== 1024 || info.height !== 1024 || [4, 6].includes(info.colorType)) fail('App Store icon must be 1024x1024 without alpha');
  const expectedIconSha256 = manifest.apple?.appIconSha256;
  if (expectedIconSha256) {
    const actualIconSha256 = crypto.createHash('sha256').update(fs.readFileSync(icon)).digest('hex');
    if (actualIconSha256 !== expectedIconSha256) fail('App Store icon disagrees with the approved tenant artwork');
  }
} catch (error) { fail(`App Store icon: ${error.message}`); }

warnings.push('Legal approval and production-deployment gates require external evidence.');
for (const warning of warnings) console.warn(`WARN: ${warning}`);
if (errors.length) {
  for (const error of errors) console.error(`ERROR: ${error}`);
  process.exit(1);
}
console.log('Store preflight passed (local/read-only).');
