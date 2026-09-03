import test from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { JSDOM } from 'jsdom';

register('../css_loader.mjs', import.meta.url);

test('the Admin header button opens the admin route', async () => {
  const dom = new JSDOM('<!doctype html><html><body></body></html>', {
    url: 'https://example.test/',
  });

  global.window = dom.window;
  global.document = dom.window.document;
  global.HTMLElement = dom.window.HTMLElement;
  global.customElements = dom.window.customElements;

  const [{ UserHeader }, { RightsService }, { RouterService }] = await Promise.all([
    import('../../src/components/users/user_header.js'),
    import('../../src/services/rights_service.js'),
    import('../../src/services/router_service.js'),
  ]);

  const originalCanSeeAdmin = RightsService.canSeeAdmin;
  const originalCanSeeReservations = RightsService.canSeeReservations;
  const originalGetUserDisplayInfo = RightsService.getUserDisplayInfo;
  const originalNavigateToAdmin = RouterService.navigateToAdmin;
  const originalNavigateToHandover = RouterService.navigateToHandover;
  const originalContext = RightsService._context;
  let adminNavigations = 0;
  let adminOccasionLink = null;
  let adminBaseUrl = null;
  let handoverNavigations = 0;

  try {
    RightsService.canSeeAdmin = () => true;
    RightsService.canSeeReservations = () => false;
    RightsService.getUserDisplayInfo = () => ({ initial: 'A', name: 'Admin' });
    RightsService._context = {
      occasion: { link: 'hvezdamorska' },
      organization: { DEFAULT_URL: 'https://live.festapp.net' },
    };
    RouterService.navigateToAdmin = (occasionLink, baseUrl) => {
      adminNavigations += 1;
      adminOccasionLink = occasionLink;
      adminBaseUrl = baseUrl;
    };
    RouterService.navigateToHandover = () => { handoverNavigations += 1; };

    const header = new UserHeader();
    header.user = { id: 'admin-user' };
    header.context = {};
    header.render();
    header.querySelector('.btn-admin').click();

    assert.equal(adminNavigations, 1);
    assert.equal(adminOccasionLink, 'hvezdamorska');
    assert.equal(adminBaseUrl, 'https://live.festapp.net');
    assert.equal(handoverNavigations, 0);
  } finally {
    RightsService.canSeeAdmin = originalCanSeeAdmin;
    RightsService.canSeeReservations = originalCanSeeReservations;
    RightsService.getUserDisplayInfo = originalGetUserDisplayInfo;
    RouterService.navigateToAdmin = originalNavigateToAdmin;
    RouterService.navigateToHandover = originalNavigateToHandover;
    RightsService._context = originalContext;
    dom.window.close();
  }
});
