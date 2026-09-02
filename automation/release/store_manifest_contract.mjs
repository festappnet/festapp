export function storeManifestShapeErrors(manifest) {
  const errors = [];
  const requireObject = (field) => {
    const value = manifest?.[field];
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      errors.push(`app-store manifest is missing object ${field}`);
      return false;
    }
    return true;
  };

  if (requireObject('target')) {
    for (const field of ['name', 'locale']) {
      if (typeof manifest.target[field] !== 'string' || !manifest.target[field].trim()) {
        errors.push(`app-store manifest target.${field} is missing`);
      }
    }
  }
  if (requireObject('apple')) {
    if (typeof manifest.apple.storeName !== 'string' || !manifest.apple.storeName.trim()) {
      errors.push('app-store manifest apple.storeName is missing');
    }
  }
  if (requireObject('urls')) {
    for (const field of ['marketing', 'privacy', 'privacyChoices', 'support']) {
      try {
        const url = new URL(manifest.urls[field]);
        if (url.protocol !== 'https:') throw new Error('not HTTPS');
      } catch {
        errors.push(`app-store manifest urls.${field} must be an absolute HTTPS URL`);
      }
    }
  }
  if (requireObject('screenshots') && Object.keys(manifest.screenshots).length === 0) {
    errors.push('app-store manifest screenshots must define at least one device set');
  }
  return errors;
}
