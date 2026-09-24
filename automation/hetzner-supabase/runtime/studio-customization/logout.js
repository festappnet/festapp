(() => {
  const attribute = 'data-festapp-access-logout';
  const logoutPath = '/cdn-cgi/access/logout';
  const logoutIcon = `
    <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24"
      fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"
      stroke-linejoin="round" class="lucide lucide-log-out text-foreground-lighter"
      aria-hidden="true">
      <path d="M10 17l5-5-5-5"></path>
      <path d="M15 12H3"></path>
      <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"></path>
    </svg>`;

  function installLogoutItem() {
    for (const menu of document.querySelectorAll('[role="menu"]')) {
      if (menu.querySelector(`[${attribute}]`)) continue;

      const preferences = [...menu.querySelectorAll('a[role="menuitem"]')]
        .find((item) => item.getAttribute('href') === '/account/me');
      if (!preferences) continue;

      const separatorTemplate = menu.querySelector('[role="separator"]');
      const separator = separatorTemplate
        ? separatorTemplate.cloneNode(false)
        : Object.assign(document.createElement('div'), {
            className: '-mx-1 my-1 h-px bg-border-overlay',
          });
      separator.setAttribute('role', 'separator');
      separator.setAttribute('aria-orientation', 'horizontal');
      separator.setAttribute(attribute, 'separator');

      const logout = preferences.cloneNode(false);
      logout.setAttribute(attribute, 'item');
      logout.setAttribute('href', logoutPath);
      logout.setAttribute('aria-label', 'Sign out of Festapp');
      logout.innerHTML = `${logoutIcon}<span>Sign out</span>`;

      menu.append(separator, logout);
    }
  }

  new MutationObserver(installLogoutItem).observe(document.body, {
    childList: true,
    subtree: true,
  });
  installLogoutItem();
})();
