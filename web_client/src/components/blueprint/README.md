# Blueprint Component

The Blueprint component renders an interactive seat map for ticket selection.

## Architecture

- **`BlueprintRenderer`**: The main class responsible for managing the DOM,
  event listeners, and rendering loop.
- **`TransformController`**: Handles pan and zoom logic using CSS transforms
  (`matrix`).
- **`BlueprintDataPreparer`**: Pre-processes raw API data into an optimized
  format for rendering.
- **`SeatStyler`**: Applies visual styles (colors, icons) to seat elements based
  on their state (available, selected, ordered). Use this to customize seat
  appearance.
- **`TooltipProvider`**: Manages the content and positioning of tooltips when
  hovering over seats.
- **`SvgUtils`**: Helper for parsing and preparing the background SVG map.

## Usage

```javascript
/* Inside a Component or Page */
import { BlueprintRenderer } from "./blueprint/blueprint_renderer.js";

const container = document.getElementById("blueprint-container");
const renderer = new BlueprintRenderer(container);

// Render
renderer.render(data, (clickedSeat) => {
  console.log("User clicked:", clickedSeat);
});

// Update Styling (e.g. after selection change)
// Efficiently updates DOM without full re-render
renderer.updateSeatsDOM();
```

## Styling

The component uses `blueprint_config.js` for constants and
`BlueprintRenderer.css` (imported implicitly via renderer logic or manually) for
base styles.

## Performance

The renderer uses a "Transform Layer" approach:

1. **Background & Seats** are rendered once into a `transformContainer`.
2. **Pan & Zoom** only updates the `transform: translate(...) scale(...)`
   property of this container. Actual frame rate depends on device and map size.
3. **Updates**: Use `updateSeatsDOM()` to flip classes/styles on existing DOM
   nodes instead of `render()`.

## Interaction & Zoom

- **Zoom constraints**: The minimum is the viewport's computed fit scale. The
  maximum is that fit scale multiplied by `BlueprintConfig.maxScale` (currently
  5), not an absolute `0.1x-5x` range. Bounds apply in both axes, including
  configured insets and pan clearance.
- **Gestures**: `GestureController` handles pointer/wheel input;
  `TransformController` owns the transform and bounds. The renderer also provides
  zoom/reset buttons. Call `renderer.destroy()` when removing the view so its
  gesture handlers and `ResizeObserver` are released.
