# DetentScrollView

A SwiftUI scroll view with detent-based resistance and snapping between sections.

Unlike standard `ScrollView` (free-flowing) or paged scroll views (binary snap), `DetentScrollView` creates a physical "detent" feel where users must overcome resistance to transition between sections.

## Features

- Rubber-band resistance at section boundaries
- Threshold-based snapping between sections
- Free scrolling within sections that exceed viewport height
- Natural momentum with instant catch on touch
- Over-damped bounce at section edges
- Auto-hiding scrollbar
- Section snap insets for "peek" behavior

## Requirements

- iOS 17.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pageofswrds/DetentScrollView.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → Enter the repository URL.

## Usage

```swift
import DetentScrollView

struct ContentView: View {
    @State private var currentSection = 0

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            DetentScrollView(
                sectionHeights: [screenHeight, 600, screenHeight],
                sectionSnapInsets: [0, 100, 0],
                currentSection: $currentSection
            ) {
                VStack(spacing: 0) {
                    Section1()
                        .frame(height: screenHeight)

                    Section2()
                        .frame(height: 600)

                    Section3()
                        .frame(height: screenHeight)
                }
            }
        }
    }
}
```

## API Reference

### DetentScrollView

```swift
public init(
    sectionHeights: [CGFloat],
    sectionSnapInsets: [CGFloat]? = nil,
    configuration: DetentScrollConfiguration = .default,
    currentSection: Binding<Int>? = nil,
    isScrollDisabled: Bool = false,
    @ViewBuilder content: () -> Content
)
```

**Parameters:**

- `sectionHeights`: Height of each section in points
- `sectionSnapInsets`: How far from viewport top each section starts when snapped (enables "peek" behavior)
- `configuration`: Threshold and resistance configuration
- `currentSection`: Optional binding to observe/control current section
- `isScrollDisabled`: External signal to disable scrolling (useful for gesture coordination)
- `content`: The content to display

### DetentScrollConfiguration

```swift
public struct DetentScrollConfiguration {
    public var threshold: CGFloat        // Default: 120
    public var resistanceCoefficient: CGFloat  // Default: 0.55

    public static let `default` = DetentScrollConfiguration()
}
```

### Properties

- `isScrolled: Bool` — Whether the user has scrolled past the first section

## Gesture Coordination

When embedding interactive content (like zoomable views), use `isScrollDisabled` to prevent scroll gestures from interfering:

```swift
@State private var isZoomed = false

DetentScrollView(
    sectionHeights: [...],
    isScrollDisabled: isZoomed
) {
    ZoomableContent(onZoomChanged: { zoomed in
        isZoomed = zoomed
    })
}
```

## Roadmap

See [IMPROVEMENTS.md](IMPROVEMENTS.md) for planned improvements including:

- [x] Fix frame rate assumption for ProMotion displays
- [x] Fix potential memory leak in scroll bar hide task
- [ ] Cache section offsets for better performance during animation
- [ ] Add comprehensive unit tests for physics and transitions
- [ ] Improve array bounds validation
- [ ] Add accessibility support

## License

MIT License
