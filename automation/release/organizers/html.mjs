export const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
export const publicUrl = value => {
  const url = new URL(value, 'https://marketing.invalid');
  if (!['https:','mailto:'].includes(url.protocol)) throw new Error('Unsafe landing URL');
  return escape(value);
};
