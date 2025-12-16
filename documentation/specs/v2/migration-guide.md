# Migration Guide: v1 to v2

## Overview

Migrating from `DetentScrollView` (v1) to `DetentScrollContainer` (v2) is designed to be straightforward. The APIs are intentionally similar.

## Basic Migration

### Before (v1)

```swift
import DetentScrollView

struct MyView: View {
    @State private var section = 0

    var body: some View {
        DetentScrollView(
            sectionHeights: [800, 600, 800],
            sectionSnapInsets: [0, 100, 0],
            configuration: .default,
            currentSection: $section,
            isScrollDisabled: false
        ) {
            VStack(spacing: 0) {
                Section1().frame(height: 800)
                Section2().frame(height: 600)
                Section3().frame(height: 800)
            }
        }
    }
}
```

### After (v2)

```swift
import DetentScrollView

struct MyView: View {
    @State private var section = 0

    var body: some View {
        DetentScrollContainer(  // <- Only change: renamed type
            sectionHeights: [800, 600, 800],
            sectionSnapInsets: [0, 100, 0],
            configuration: .default,
            currentSection: $section,
            isScrollDisabled: false
        ) {
            VStack(spacing: 0) {
                Section1().frame(height: 800)
                Section2().frame(height: 600)
                Section3().frame(height: 800)
            }
        }
    }
}
```

## Changes Summary

| Aspect | v1 | v2 |
|--------|----|----|
| Type name | `DetentScrollView` | `DetentScrollContainer` |
| Import | `import DetentScrollView` | Same |
| Parameters | All the same | All the same |
| Configuration | `DetentScrollConfiguration` | Same (reused) |

## Behavioral Differences

### 1. Gesture System

**v1**: Uses SwiftUI `DragGesture`
**v2**: Uses UIKit `UIPanGestureRecognizer`

**Impact**: None for most users. The feel should be identical.

### 2. Child Gesture Coordination

**v1**: Child UIKit gestures can block parent SwiftUI updates
**v2**: Child UIKit gestures coordinate via `UIGestureRecognizerDelegate`

**Impact**: This is the main reason for v2. Pinch-to-zoom in child views now works correctly.

### 3. View Hierarchy

**v1**: Pure SwiftUI view tree
**v2**: UIKit container with UIHostingController for SwiftUI content

**Impact**:
- SwiftUI previews still work (UIViewControllerRepresentable supports previews)
- View debugger will show UIKit views wrapping SwiftUI content
- Performance should be similar or better

## Edge Cases

### Custom Gesture Recognizers in Content

If your content has custom `UIGestureRecognizer`s, they will now properly coordinate with the scroll gesture via UIKit's standard delegate mechanisms.

```swift
// This now works correctly in v2
DetentScrollContainer(...) {
    MyZoomableView()  // Contains UIPinchGestureRecognizer
}
```

### Nested Scroll Views

If you have nested `ScrollView` or `List` in your content, behavior should be similar to v1. The outer `DetentScrollContainer` handles section transitions while inner scroll views handle their own content.

### Animation Coordination

v1 used SwiftUI's `withAnimation` for transitions. v2 uses UIKit animations (`UIView.animate`). The timing curves are matched to feel consistent.

```swift
// v1 used:
withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { ... }

// v2 uses:
UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, ...)
```

## Testing Your Migration

1. **Visual diff**: Compare scroll feel between v1 and v2 side-by-side
2. **Section transitions**: Verify threshold-based snapping works
3. **Momentum**: Verify flick-to-scroll momentum feels natural
4. **Rubber-band**: Verify boundary resistance matches
5. **Child gestures**: Verify pinch/pan in child views works

## Gradual Migration

You can run v1 and v2 side-by-side during migration:

```swift
struct PrototypeView: View {
    @State private var useV2 = true

    var body: some View {
        if useV2 {
            DetentScrollContainer(...) { content }
        } else {
            DetentScrollView(...) { content }
        }
    }
}
```

## Rollback Plan

If v2 has issues, simply change the type name back to `DetentScrollView`. Both implementations will be available in the package.

## Deprecation Timeline

1. **Phase 1** (Current): Both v1 and v2 available, no deprecation warnings
2. **Phase 2** (After validation): v1 marked `@available(*, deprecated, renamed: "DetentScrollContainer")`
3. **Phase 3** (Future major version): v1 removed

## Reporting Issues

If you encounter differences between v1 and v2:

1. Note the specific behavior difference
2. Create a minimal reproduction
3. File an issue with:
   - Expected behavior (v1)
   - Actual behavior (v2)
   - Device/OS version
   - Reproduction steps
