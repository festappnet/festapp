# FestApp Web Client

A web-based interface for the FestApp ecosystem, built with vanilla JavaScript
and HTML/CSS. This project mirrors the business logic and some UI patterns of
the main Flutter application but is designed for lightweight, browser-based
access (e.g., ticket purchasing, registration forms).

## Overview

This project is a Single Page Application (SPA) that acts as a web client for:

- Users to register or buy tickets.
- Filling out forms with validation.
- Browsing "occasions" or events.

## Key Features

- **Dynamic Form building**: Renders forms based on JSON configurations
  (`blueprint`).
- **EShop Integration**: Manages orders and tickets (similar to the Flutter
  app's Eshop component).
- **Responsive Design**: Mobile-friendly layout using custom CSS variables and
  utility classes.
- **Component-based Architecture**: UI logic is split into functional
  components.
  - **Forms**: The primary UI for user interaction, handling Tickets and Orders.
  - **Eshop**: (Logic only) Provides backing data services for Forms, mirroring
    the Flutter Eshop logic.

## Architecture

- **Vanilla JS**: No heavy frontend framework. Uses direct DOM manipulation and
  custom component classes (SFC-like pattern with `.js` and scoped `.css`).
- **CSS Variables**: Extensive use of CSS variables for theming.
- **Service Layer**: `src/services` handles API communication.

## Setup & Running

1. **Install Dependencies**:
   ```bash
   npm install
   ```

2. **Run Dev Server**:
   ```bash
   npm run dev
   ```

3. **Build**:
   ```bash
   npm run build
   ```

## Testing

The project uses Node.js's native test runner.

```bash
# Run all tests
npm test
```

## Maintenance Scripts

Located in `scripts/` (and root `automation/` wrappers):

- **Translation Sync**:
  - `unify_translations.js`: Syncs keys between Flutter and Web.
  - `reorder_cs_like_en.js`: Ensures Czech translation file matches English
    structure.
- **Database Tests**: `run_db_tests.js` runs SQL regression tests.
