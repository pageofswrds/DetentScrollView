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

### ~~Missing Tests~~ ✅ DONE
Physics functions extracted to the [Mercurial](../Mercurial) package and comprehensively tested.

**31 tests covering:**
- [x] Rubber-band formula (zero, positive, negative, symmetry, asymptotic limit, coefficient effects, monotonicity)
- [x] Spring force (at rest, positive/negative displacement, damping, stiffness scaling)
- [x] Friction (basic decay, zero velocity, negative velocity, decay over time)
- [x] Integration (positive/negative velocity, zero cases)
- [x] Combined simulations (momentum decay, bounce settling)
- [x] Edge cases (single section, mismatched arrays, empty snap insets)

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

### ~~Gesture Threshold Conflicts~~ ✅ DONE
**File:** `DetentScrollView.swift:411`

Minimum drag distance is now configurable via `DetentScrollConfiguration`:
```swift
DetentScrollConfiguration(
    threshold: 120,
    resistanceCoefficient: 0.55,
    minimumDragDistance: 25  // Increase for child gesture priority
)
```

Default remains 10pt for standard scroll behavior.

---

## Priority 5: Code Quality

### ~~Document Magic Numbers~~ ✅ DONE
All physics and UI constants now have inline documentation explaining their purpose:

- Scroll bar: `40pt` minimum height, `300pt` shrink divisor, `0.3` minimum shrink factor, `20pt` absolute minimum
- Momentum: `50 pt/s` minimum velocity threshold
- Physics: `0.95` friction (decays to ~5% over 1 second), `200` spring stiffness, `30` damping (over-damped)

---

## Future Enhancements

### ~~Accessibility~~ ✅ DONE
- [x] Respect `accessibilityReduceMotion` - skips momentum, uses simple easeOut animations
- [x] VoiceOver section announcements - announces "Section X of Y" on transitions
- [ ] Dynamic Type for scroll bar sizing (skipped - minimal impact)

### ~~Programmatic Navigation~~ ✅ DONE
Change the `currentSection` binding to navigate with animation:
```swift
@State private var section = 0

// Navigate to section 2 with animation
section = 2  // Triggers animated scroll
```

Respects `accessibilityReduceMotion` for animation style.

### ~~Physics Engine Extraction~~ ✅ DONE
Physics extracted to the [Mercurial](../Mercurial) package:
- Pure physics functions (`Physics.rubberBand`, `Physics.springForce`, etc.)
- 1D and 2D variants for scroll and pan gestures
- `MomentumAnimator` classes for common use cases
- Comprehensive test coverage (91 tests)

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
| Test Coverage | 6 | Done |
| Robustness | 2 | Done |
| Code Quality | 1 | Done |
| Future Enhancements | 4 | 3 Done, 1 Planned |
