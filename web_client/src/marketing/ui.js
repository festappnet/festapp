export function marketingUI(root) {
  const source = root.getElementById?.('marketing-ui')?.textContent;
  if (!source) return null;
  return JSON.parse(source);
}
