# Features and screenshots

- Available on Android, iOS, and Web.
- Previously synchronized event data is available offline (Android, iOS, Web/PWA);
  availability depends on the selected sync capability and populated local cache.
- Dark and light modes are available.
- **Volunteer Management**: Dedicated staffing system for managing tasks,
  shifts, and assignments.

---

- Schedule
  - Timeline - Schedule overview by time and day.
  - Event detail - Includes: Time, Place (with link), Content, Subevents, Sign
    In/Sign Out button.
  - Timetable - View event entries on the axes of Time and Place.
  - My schedule - Attendee can add event entries to their own list.

<p align="center">
  <img src="../../repo-data/screenshots/schedule2.png?raw=true" alt="schedule2" title="schedule2" width="200" />
  <img src="../../repo-data/screenshots/schedule1.png?raw=true" alt="schedule1" title="schedule1" width="200" />
  <img src="../../repo-data/screenshots/schedule5.png?raw=true" alt="schedule5" title="schedule5" width="200" />
  <img src="../../repo-data/screenshots/schedule3.png?raw=true" alt="schedule3" title="schedule3" width="200" />
</p>

- Map
  - Map with current user location, places, and paths with custom icons and
    descriptions. It is also possible to set up an offline map (Android, iOS).

<p align="center">
  <img src="../../repo-data/screenshots/map1.png?raw=true" alt="map1" title="map1" width="220" />
  <img src="../../repo-data/screenshots/map2.png?raw=true" alt="map2" title="map2" width="220" />
  <img src="../../repo-data/screenshots/map4.png?raw=true" alt="map4" title="map4" width="220" />
</p>

- News/Notifications
  - Receive news and push notifications relevant to the event.
  - Push uses OneSignal with tenant/platform configuration. Browser delivery
    depends on browser support, permission and the configured web app identity.

<p align="center">
  <img src="../../repo-data/screenshots/news3.png?raw=true" alt="news3" title="news3" width="220" />
  <img src="../../repo-data/screenshots/news2.png?raw=true" alt="news2" title="news2" width="220" />
</p>

- Info/Songbook/Game
  - Various information about the event, a Songbook with font-size
    increase/decrease, and a groups-based code-guessing game.

- Administration/Feature settings
  - Overview of all event data, map, groups, users, rights, and other settings.
  - Setup of multiple events.

- User/Companions/Workshops
  - User profile with personal data.
  - Ability to import users from a table.
  - Creation of events with limited capacity (workshops) and creation of
    companions.
  - QR code for workshop entry verification.

<p align="center">
  <img src="../../repo-data/screenshots/user1.png?raw=true" alt="user1" title="user1" width="200" />
  <img src="../../repo-data/screenshots/user3.png?raw=true" alt="user3" title="user3" width="200" />
  <img src="../../repo-data/screenshots/user4.png?raw=true" alt="user4" title="user4" width="200" />
  <img src="../../repo-data/screenshots/user5.png?raw=true" alt="user5" title="user5" width="200" />
</p>

- Ticket/Form/Seat reservation
  - Support for creation of custom forms (similar to Google Forms) with priced
    products.
  - Creation of custom tickets with custom graphics.
  - Creation of a seat reservation component.

<p align="center">
  <img src="../../repo-data/screenshots/form1.png?raw=true" alt="form1" title="form1" width="200" />
  <img src="../../repo-data/screenshots/form3.png?raw=true" alt="form3" title="form3" width="200" />
  <img src="../../repo-data/screenshots/form4.png?raw=true" alt="form4" title="form4" width="200" />
  <img src="../../repo-data/screenshots/form5.png?raw=true" alt="form5" title="form5" width="200" />
</p>

- Orders/Transactions
  - Order management, bank payment synchronization, automated sending, and
    creation of paid tickets.

- Email Templates
  - Customization of all email templates.

<p align="center">
  <img src="../../repo-data/screenshots/email1.png?raw=true" alt="email1" title="email1" width="220" />
  <img src="../../repo-data/screenshots/email2.png?raw=true" alt="email2" title="email2" width="220" />
  <img src="../../repo-data/screenshots/email3.png?raw=true" alt="email3" title="email3" width="220" />
</p>

- Ticket scanning
  - QR-code-based ticket verification.

Developer references for current features:
[Google sign-in](../operations/auth/google-sign-in.md),
[ticket layout editor](../../lib/components/ticket_layout/README.md),
[occasion reports](../../lib/components/eshop/README.md#occasion-report-snapshot), and
[BankSync account management](../../lib/components/bank_accounts/README.md).

