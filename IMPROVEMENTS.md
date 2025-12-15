# Improvement Roadmap

Code review findings and planned improvements for DetentScrollView.

## Priority 1: Bug Fixes

### ~~Fix Frame Rate Assumption~~ ✅ DONE
**File:** `DetentScrollView.swift:531-536`

Now uses `CACurrentMediaTime()` to calculate actual delta time between frames:
```swift
let currentTime = CACurrentMediaTime()
let rawDelta = currentTime - lastMomentumUpdateTime
let frameTime = CGFloat(min(rawDelta, 1.0 / 30.0))  // Clamp to prevent jumps
lastMomentumUpdateTime = currentTime
```

Works correctly on all refresh rates (60Hz, 120Hz ProMotion, etc.).

### ~~Potential Memory Leak with Task~~ ✅ DONE
**File:** `DetentScrollView.swift:351-354`

Added `onDisappear` cleanup to cancel any pending scroll bar hide task:
```swift
.onDisappear {
    scrollBarHideTask?.cancel()
    scrollBarHideTask = nil
}
```

---

## Priority 2: Performance

### ~~Cache Section Offsets~~ ✅ DONE
**File:** `DetentScrollView.swift:93-94, 160-167`

Section offsets are now computed once at initialization and cached:
```swift
private let cachedSectionOffsets: [CGFloat]  // Stored property

// Computed in init:
var offsets: [CGFloat] = [0]
var cumulative: CGFloat = 0
for height in sectionHeights.dropLast() {
    cumulative += height
    offsets.append(cumulative)
}
self.cachedSectionOffsets = offsets
```

Eliminates redundant calculations during 60-120fps animation updates.

---

## Priority 3: Test Coverage

Current tests only verify configuration defaults and view instantiation.

### Missing Tests
- [ ] Rubber-band formula accuracy
- [ ] Momentum physics (friction decay rate, boundary bounce behavior)
- [ ] Section transition logic (threshold crossing, direction)
- [ ] Edge cases:
  - Single section
  - Zero height section
  - Mismatched `sectionHeights` / `sectionSnapInsets` array lengths
- [ ] `visualOffset` calculation correctness
- [ ] `isScrolled` state transitions

### Suggested Approach
Extract physics logic into pure functions for unit testing:
```swift
// Testable pure function
func rubberBand(offset: CGFloat, limit: CGFloat, coefficient: CGFloat) -> CGFloat

// Testable momentum step
func applyMomentum(velocity: CGFloat, friction: CGFloat, frameTime: CGFloat) -> CGFloat
```

---

## Priority 4: Robustness

### ~~Array Bounds Validation~~ ✅ DONE
**File:** `DetentScrollView.swift:156-162`

Snap insets array is now automatically normalized to match section count:
```swift
let insets = sectionSnapInsets ?? []
if insets.count < sectionHeights.count {
    self.sectionSnapInsets = insets + Array(repeating: 0, count: sectionHeights.count - insets.count)
} else {
    self.sectionSnapInsets = Array(insets.prefix(sectionHeights.count))
}
```

- Too few insets: padded with zeros
- Too many insets: truncated to match

### Gesture Threshold Conflicts
**File:** `DetentScrollView.swift:329`

Fixed 10pt minimum distance may conflict with child gestures:
```swift
DragGesture(minimumDistance: 10)
```

**Consider:** Making configurable or using `simultaneousGesture` with coordination.

---

## Priority 5: Code Quality

### ~~Document Magic Numbers~~ ✅ DONE
All physics and UI constants now have inline documentation explaining their purpose:

- Scroll bar: `40pt` minimum height, `300pt` shrink divisor, `0.3` minimum shrink factor, `20pt` absolute minimum
- Momentum: `50 pt/s` minimum velocity threshold
- Physics: `0.95` friction (decays to ~5% over 1 second), `200` spring stiffness, `30` damping (over-damped)

---

## Future Enhancements

### Accessibility
- Respect `accessibilityReduceMotion` to disable momentum/bounce
- Add VoiceOver support for section announcements
- Support Dynamic Type for scroll bar sizing

### Programmatic Navigation
Add method to scroll to a specific section with animation:
```swift
func scrollTo(section: Int, animated: Bool = true)
```

### Physics Engine Extraction
Extract momentum/friction/spring code into a reusable `PhysicsAnimator` type for:
- Better testability
- Reuse in other components
- Easier tuning

### Protocol for Content
Consider a protocol for content to provide intrinsic heights:
```swift
protocol DetentScrollContent {
    var sectionHeights: [CGFloat] { get }
}
```

---

## Summary

| Category | Items | Status |
|----------|-------|--------|
| Bug Fixes | 2 | Done |
| Performance | 1 | Done |
| Test Coverage | 6 | Pending |
| Robustness | 2 | 1 Done, 1 Pending |
| Code Quality | 1 | Done |
| Future Enhancements | 4 | Planned |
