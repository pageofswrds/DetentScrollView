# Implementation Plan

## Phase 1: Core UIKit Container

### Goal
Create the basic UIKit view structure that can host SwiftUI content and respond to pan gestures with immediate visual feedback.

### Files to Create

```
Sources/DetentScrollView/
├── DetentScrollView.swift          (existing v1 - keep unchanged)
├── UIKit/
│   ├── DetentScrollContainer.swift     (UIViewControllerRepresentable)
│   └── DetentScrollViewController.swift (Core UIKit implementation)
```

### DetentScrollContainer.swift

```swift
/// UIViewControllerRepresentable wrapper for SwiftUI integration.
///
/// Usage:
/// ```swift
/// DetentScrollContainer(
///     sectionHeights: [screenHeight, 600, screenHeight],
///     currentSection: $section
/// ) {
///     VStack(spacing: 0) { ... }
/// }
/// ```
public struct DetentScrollContainer<Content: View>: UIViewControllerRepresentable {
    // Configuration
    let sectionHeights: [CGFloat]
    let sectionSnapInsets: [CGFloat]
    let configuration: DetentScrollConfiguration

    // Bindings
    @Binding var currentSection: Int
    let isScrollDisabled: Bool

    // Content
    let content: Content

    // Coordinator for callbacks
    func makeCoordinator() -> Coordinator { ... }
    func makeUIViewController(context:) -> DetentScrollViewController { ... }
    func updateUIViewController(_:context:) { ... }
}
```

### DetentScrollViewController.swift

```swift
/// Core UIKit implementation of detent scrolling.
@MainActor
public class DetentScrollViewController: UIViewController {
    // MARK: - Configuration
    var sectionHeights: [CGFloat] = []
    var sectionSnapInsets: [CGFloat] = []
    var configuration: DetentScrollConfiguration = .default
    var isScrollDisabled: Bool = false

    // MARK: - State
    private(set) var currentSection: Int = 0
    private var internalOffset: CGFloat = 0
    private var rawDragOffset: CGFloat = 0

    // MARK: - Callbacks
    var onSectionChanged: ((Int) -> Void)?

    // MARK: - Views
    private var contentView: UIView!
    private var hostingController: UIHostingController<AnyView>?

    // MARK: - Gestures
    private var panGesture: UIPanGestureRecognizer!
    private var lastPanTranslation: CGFloat = 0

    // MARK: - Lifecycle
    override func viewDidLoad() { ... }

    // MARK: - Content
    func setContent<V: View>(_ content: V) { ... }

    // MARK: - Gesture Handling
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) { ... }

    // MARK: - Layout
    private func updateContentOffset() { ... }
}
```

### Deliverables Checklist

- [ ] `DetentScrollContainer` wraps UIKit in SwiftUI
- [ ] `DetentScrollViewController` hosts SwiftUI content via UIHostingController
- [ ] Pan gesture updates `contentView.transform.ty` directly
- [ ] Visual offset updates immediately during drag (not on release)
- [ ] Basic section tracking (no transitions yet)

### Test Plan

1. Add "UIKit v2" option to PrototypeView's implementation picker
2. Verify drag gesture moves content immediately
3. Verify no animation delay during drag

---

## Phase 2: Detent Physics

### Goal
Port all detent behavior from v1: rubber-band resistance, section transitions, internal scrolling.

### Implementation Details

#### Section Geometry (port from v1)

```swift
extension DetentScrollViewController {
    /// Y offset for the start of each section
    private var sectionOffsets: [CGFloat] { ... }

    /// Maximum internal scroll for a section
    private func maxInternalScroll(for section: Int) -> CGFloat { ... }

    /// Current snap inset
    private var currentSnapInset: CGFloat { ... }
}
```

#### Rubber-Band Resistance

```swift
/// Apply rubber-band using Mercurial's Physics.rubberBand
private var dragOffset: CGFloat {
    Physics.rubberBand(
        offset: rawDragOffset,
        limit: configuration.threshold * 2,
        coefficient: configuration.resistanceCoefficient
    )
}
```

#### Drag Handling (port from v1)

```swift
private func handleDragChanged(translation: CGFloat) {
    // Compute incremental delta
    let delta = translation - lastPanTranslation
    lastPanTranslation = translation

    if delta > 0 {
        applyScrollUp(delta: delta)
    } else if delta < 0 {
        applyScrollDown(delta: delta)
    }

    updateContentOffset()
}

private func handleDragEnded(translation: CGFloat, velocity: CGFloat) {
    // Check threshold for section transition
    let shouldAdvance = -rawDragOffset > configuration.threshold && currentSection < sectionHeights.count - 1
    let shouldRetreat = rawDragOffset > configuration.threshold && currentSection > 0

    if shouldAdvance {
        animateToSection(currentSection + 1)
    } else if shouldRetreat {
        animateToSection(currentSection - 1)
    } else {
        animateSnapBack()
    }
}
```

### Deliverables Checklist

- [ ] Rubber-band resistance at section boundaries
- [ ] Section transitions when threshold exceeded
- [ ] Internal scrolling within tall sections
- [ ] Proper scroll direction handling (up/down)
- [ ] Snap inset support

### Test Plan

1. Verify rubber-band feel matches v1
2. Verify section transitions at threshold
3. Verify tall section scrolling works
4. Verify snap insets create "peek" effect

---

## Phase 3: Momentum & Polish

### Goal
Add momentum physics, scroll bar, and accessibility.

### Implementation Details

#### Momentum Animation

```swift
// Use CADisplayLink for frame-by-frame updates
private var displayLink: CADisplayLink?
private var momentumVelocity: CGFloat = 0

private func startMomentum(velocity: CGFloat) {
    momentumVelocity = -velocity  // Flip sign
    displayLink = CADisplayLink(target: self, selector: #selector(updateMomentum))
    displayLink?.add(to: .main, forMode: .common)
}

@objc private func updateMomentum() {
    // Use Mercurial's Physics for friction and spring
    // Port logic from v1's updateMomentum()
}
```

#### Scroll Bar

```swift
private var scrollBarView: UIView!

private func updateScrollBar() {
    // Calculate position and height
    // Animate visibility
}
```

#### Accessibility

```swift
private func announceSection(_ section: Int) {
    let announcement = "Section \(section + 1) of \(sectionHeights.count)"
    UIAccessibility.post(notification: .announcement, argument: announcement)
}
```

### Deliverables Checklist

- [ ] Momentum animation after release
- [ ] Friction-based deceleration
- [ ] Spring bounce at boundaries
- [ ] Scroll bar indicator
- [ ] Auto-hide scroll bar after delay
- [ ] VoiceOver section announcements
- [ ] Reduce Motion support

### Test Plan

1. Verify momentum feel matches v1
2. Verify bounce at section edges
3. Verify scroll bar appears/hides correctly
4. Test with VoiceOver enabled
5. Test with Reduce Motion enabled

---

## Phase 4: Gesture Coordination

### Goal
Ensure child zoom/pan gestures work correctly with scroll.

### Implementation Details

#### UIGestureRecognizerDelegate

```swift
extension DetentScrollViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't begin if scroll is disabled (zoomed)
        guard !isScrollDisabled else { return false }

        // Only handle vertical drags
        if gestureRecognizer === panGesture {
            let velocity = panGesture.velocity(in: view)
            return abs(velocity.y) > abs(velocity.x)
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // Allow pinch to work simultaneously
        if other is UIPinchGestureRecognizer {
            return true
        }
        return false
    }
}
```

#### Scroll Disable Support

```swift
func updateUIViewController(_ controller: DetentScrollViewController, context: Context) {
    controller.isScrollDisabled = isScrollDisabled
    // When disabled, pan gesture won't begin
}
```

### Deliverables Checklist

- [ ] `isScrollDisabled` prevents scroll when zoomed
- [ ] Pinch gesture can begin at 1x (simultaneous recognition)
- [ ] Pan gesture only captures vertical drags
- [ ] Smooth handoff between scroll and zoom

### Test Plan

1. At 1x: verify vertical scroll works
2. At 1x: verify pinch-to-zoom works
3. When zoomed: verify scroll is disabled
4. When zoomed: verify pan works for navigation
5. Verify pinch-out to 1x re-enables scroll

---

## File Structure (Final)

```
Sources/DetentScrollView/
├── DetentScrollView.swift              (v1 - SwiftUI, keep for backwards compat)
├── UIKit/
│   ├── DetentScrollContainer.swift     (v2 - UIViewControllerRepresentable)
│   ├── DetentScrollViewController.swift (v2 - Core implementation)
│   └── DetentScrollViewController+Gesture.swift (v2 - Gesture delegate)
```

## Migration Path

1. Create v2 alongside v1 (no breaking changes)
2. Test v2 in PrototypeView
3. Once validated, migrate other usages
4. Eventually deprecate v1

## Dependencies

- **Mercurial**: `Physics.rubberBand`, `Physics.springForce`, `Physics.integrate`, `Physics.applyFriction`
- **UIKit**: `UIPanGestureRecognizer`, `CADisplayLink`, `UIHostingController`
