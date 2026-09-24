# Forms Feature (Web Client)

**Purpose**: The central engine for data collection, ticket ordering, and
registration.

## Core Concepts

### 1. Dynamic Definition

Forms are defined in JSON stored in the DB, not hardcoded. The web client
fetches this definition and renders widgets accordingly.

- **RPC**: `get_form_by_link`
  (`database/functions/eshop_forms/get_form_by_link.sql`) returns the "Form
  Bundle" (Metadata, Fields, Products, Secret).

### 2. Core Files

- `form_page.js`: The main entry point for rendering a form.
- `form_session.js`: Manages the state of the current form session.
- `form_data_reader.js`: Extracts data from the DOM/inputs for submission.
- `field_builders/`: Directory containing builders for specific field types
  (e.g. `TextFieldBuilder`, `TicketFieldBuilder`).

## Data Flow

1. **Load**: `FormPage` -> `get_form_by_link` (SQL) -> Renders fields.
2. **Interact**: User fills inputs.
3. **Submit**:
   - `FormDataReader` collects values.
   - `DbForms` or `DbOrders` sends data to Supabase/Edge Functions (similar to
     Flutter `DbForms`/`DbOrders`).

## Critical Implementation Details

- **Field Builders**: Each field type has a dedicated builder class used to
  generate the HTML.
- **Validation**: Form validation logic mirrors the Flutter app but is
  implemented in JS (often reusing the same regex or logic).

## Theming & Fonts

The forms support extensive theming via `ThemeService`:

- **Fonts**: Defaults to **Futura** (bundled). Supports Google Fonts via
  configuration.
- **Font Scaling**:
  - **Default (Futura)**: Uses a `1.2` scale factor (defined in
    `theme_config.css`) to match design requirements.
  - **Custom Fonts**: If a custom font is set, the scale automatically resets to
    `1.0` to prevent layout issues.
- **Colors**: Automatically generates a palette (primary, secondary, background,
  surface) based on the primary color, with support for Dark Mode.

## State Management

- **FormSession**: The source of truth for the current user session (seats
  selected, cart contents).
- **FormHolder**: A container for the static form definition and helper methods.
