# Changelog

## 2026_02 (0.19.24–0.19.29)

- Self-registration: users sign up and get their own organization.
- Multi-organization membership.
- Organization management: create, delete, settings.
- Organization-level phone prefix settings.

## 2026_01 (0.19.7–0.19.23)

- Full vanilla JS web client for public pages — forms, seat maps, ticket ordering. Admin stays in Flutter.
- SEO: form links show properly on social media with cover images and descriptions.
- Bank integration: manage bank accounts per unit, connect FIO Bank for automatic payment matching.
- Bank email transaction pairing: incoming bank notification emails automatically parsed and matched to orders.
- Surcharges on products.
- Cash payments and free products with on-site payment.
- Contract/agreement PDF generation for travel events.
- Cross-instance synchronization of occasions between databases.
- Multiple tickets per order.
- Manual ticket lookup in scanner.
- Scheduled changes: prices, product visibility, and form open/close on a timer.

## 2025_12 (0.17.42–0.19.6)

- Web client foundation: vanilla JS client for forms, blueprints, and ticket ordering.
- Email banners: configurable per email at organization/unit/occasion level with live preview.
- Hierarchical email template resolution — most specific level wins.
- Form design: custom fonts (Google Fonts) and colors.
- Countdown timer before form opening.
- Scheduled form auto-open/close.
- Blueprint order history per seat.
- Change product on individual blueprint seats.
- Seat details popup on blueprint.
- Multichoice products.

## 2025_11 (0.17.32–0.17.41)

- Blueprint: different prices per seat/table.
- Quick order creation from blueprint.
- Seat swap on blueprint.
- Cross marks on occupied seats.
- Clean URLs for social media sharing (no hash).
- Public home page showing promoted events across all units.
- Scanner: auto-import users from tickets.
- Reset password via scan.
- Manual ticket PDF download by admin.
- Sent ticket history tracking.
- Feedback button.
- Max tickets per form setting.
- Reply-to email setting.

## 2025_10 (0.17.20–0.17.31)

- Payment variable symbol (VS) sequence generation.
- Blueprint bitmap background support.
- Multi-currency translations.
- Form response field editing.

## 2025_09 (0.17.9–0.17.11)

- Multi-currency translations in edge functions.

## 2025_08 (0.17.6–0.17.8)

- Ticket "as used" quick update from admin.

## 2025_07 (0.15–0.17.5)

- Inventory/accommodation system: capacity pools, resources, rooms, beds — with overbooking protection.
- "My Stay" page for guests to see their assigned accommodation.
- Order change history with before/after diff view.
- Automated payment deadline reminder emails.
- Email notifications when orders are modified, with change summary.
- Admin can edit product prices on existing orders.
- User groups with admin role.
- Breadcrumbs navigation.
- Copy/duplicate forms across occasions.
- Group participant management.

## 2025_06 (0.14.15–0.14.29)

- Schedule split by place.
- Schedule event types.
- Schedule map integration.
- Sign-up conflict resolution for schedule.
- Multiple forms per occasion with create/duplicate/delete.
- Form settings UI.
- ID document form field.
- Nationality form field.
- Bulk user import from tickets.

## 2025_05 (0.13–0.14.14)

- Activities: volunteer/staff task scheduling with drag-and-drop timeline, autosave, version history, publish.
- Schedule custom separators.
- Schedule offline support.
- Offline map support with custom tile styles.
- Feature toggle system for enabling/disabling occasion features.
- Form editor and viewer rebuilt.
- Product management.
- Fakturoid invoicing integration.
- Named/personalized ticket PDFs.
- Order sync with external systems.

## 2025_04 (0.12.8–0.12.13)

- Multi-currency support.

## 2025_03 (0.12.4–0.12.7)

- Automatic ticket sending after payment is matched (cron-based).
- Named/personalized ticket PDFs.
- Offline usability fixes.

## 2025_02 (0.12.0–0.12.3)

- Multi-tenant units: each unit manages its own occasions, users, and settings.
- QR ticket scanning with validation.
- Email template system with per-occasion customization.
- Bank transaction tracking: import, search, link to orders.
- Visual form builder.
- Form responses viewer.
- Self-service instance installation.
- Occasion duplication.

## 2025_01 (0.11.1–0.11.2)

- Batch ticket PDF generation and sending from admin.

## 2024_12 (0.11.0)

- E-shop/ticketing system: orders, products, tickets, payments — built from scratch.
- Automatic ticket email when order is placed.
- Blueprint seat editor: visual seat map with interactive reservation.
- Public registration and order forms with preview.
- Game feature: group checkpoint gameplay with code-guessing.
- Admin page split into dedicated tabs per feature.
- Dark/light theme support.

## 2024_11 (0.10.2–0.10.16)

- Check-in/attendance page.
- Settings page.
- Map rewrite with custom markers and place popups.
- Timetable with zoom and current time indicator.
- Image compression.
- Companion management dialog.

## 2024_10 (0.10.0–0.10.1)

- Admin dashboard for managing multiple occasions.

## 2024_08 (0.9.10–0.9.13)

- PWA install page.
- Deep linking support for occasions.
- Auto-hyperlink conversion in content.

## 2024_07 (0.9.9)

- QR codes for users and companions.

## 2024_06 (0.9.4–0.9.8)

- Companion feature: add guest users to occasions.
- Approver page for workshop attendees.

## 2024_05 (0.9.1–0.9.3)

- User registration: sign-up, forgot password, reset password.
- News creation form.

## 2024_04 (0.8.3–0.8.5)

- Multi-occasion architecture with permissions system.
- Password management.

## 2024_03 (0.7.4–0.8.2)

- Song/lyrics page.
- Offline data caching.

## 2024_02 (0.7.0–0.7.3)

- URL-based navigation.
- Offline data support.

## 2024_01 (0.6)

- Timetable: visual schedule grid with time axis and locations.
- URL routing for the web version.
- "My program" creation without login.
- Ukrainian language.
- PWA offline mode.

## 2023_12 (0.5)

- Rebranded from single-event app to reusable festival platform "Festapp".
- 5 languages (cs, en, de, pl, sk) with 152 translation keys each.
- Full privacy policy.
- PWA manifest and app icons.

## 2023_11 (pre-release)

- Push notifications via OneSignal (Android & iOS).
- JWT claims-based role security (admin/editor) at database level.
- Configurable branding: colors, logos, settings per instance.
- User management: diff-based CSV import with password generation and welcome emails.
- App published to App Store and Google Play.

## 2023_08 – 2023_09 (pre-release)

- Exclusive event groups: prevent scheduling conflicts for parallel workshops.
- User groups with leaders and assigned meeting places.
- "My Program" view showing only signed-up events.
- iOS app store preparation.

## 2023_07 (pre-release)

- Full admin panel: manage users, events, information, places.
- Rich HTML content editor for event and info descriptions.
- Bulk user import from CSV with auto-generated passwords.
- Welcome email sending via MailerSend.
- 16 SVG map icons (food, beer, church, info, etc.).
- Database functions for atomic event sign-up with capacity checking.
- First Android release.

## 2023_06 (pre-release)

- Event detail page with sign-in/sign-out and participant list.
- Program schedule with day tabs and timeline visualization.
- User profile page.

## 2023_05 (pre-release)

- News/announcements feed.
- Google Sheets data import script.

## 2023_04 (pre-release)

- Project started. Flutter app with Supabase backend.
- Login with email/password and auto-login.
- Interactive map with OpenStreetMap and custom markers.
- Admin data grid for managing content.

## 2023_03 (pre-release)

- Initial demo app.
- GitHub Pages deployment.
