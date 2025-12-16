# DetentScrollView v2: UIKit Implementation

## Overview

A complete rewrite of DetentScrollView using UIKit for gesture handling, solving the SwiftUI gesture conflict that prevents parent view updates during child gesture recognition.

## Problem Statement

The current SwiftUI-based DetentScrollView has a fundamental conflict with child views that use UIKit gesture recognizers (like MercurialPinchPanOverlay for zoom/pan):

1. **SwiftUI rendering blocks during gestures**: When a child view has active gesture recognizers, the parent DetentScrollView's view doesn't re-render during drag - only when the gesture ends.

2. **Pinch-to-zoom at 1x broken**: To fix scrolling, we filter touches via `hitTest`, but this prevents pinch gestures from receiving both touches at 1x zoom.

3. **Mutual exclusion**: We cannot have both smooth scroll animation AND pinch-to-zoom at 1x with the current architecture.

## Solution

Replace the SwiftUI `DragGesture` with a UIKit `UIPanGestureRecognizer`. This allows:

- Direct view transform updates (immediate, no SwiftUI update cycle)
- Gesture delegate coordination with child gesture recognizers
- Predictable touch event flow via UIKit's responder chain

## Architecture

```
DetentScrollContainer (UIViewControllerRepresentable)
    └── DetentScrollViewController (UIViewController)
            ├── UIPanGestureRecognizer (scroll handling)
            ├── contentView (UIView - transforms for offset)
            │       └── UIHostingController.view (SwiftUI content)
            └── scrollBarView (UIView - indicator)
```

## Documents

- [Implementation Plan](./implementation-plan.md) - Phased approach with deliverables
- [API Design](./api-design.md) - Public interface specification
- [Migration Guide](./migration-guide.md) - How to migrate from v1

## Timeline

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Core UIKit Container | Not Started |
| 2 | Detent Physics | Not Started |
| 3 | Momentum & Polish | Not Started |
| 4 | Gesture Coordination | Not Started |

## Success Criteria

1. Scroll animation renders during drag (not just on release)
2. Pinch-to-zoom works at 1x zoom level
3. All existing functionality preserved (sections, snap insets, momentum, etc.)
4. API remains similar to v1 for easy migration
