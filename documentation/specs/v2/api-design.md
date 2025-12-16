# API Design

## Public Interface

### DetentScrollContainer

The primary SwiftUI interface, designed to mirror v1's `DetentScrollView` API.

```swift
public struct DetentScrollContainer<Content: View>: UIViewControllerRepresentable {

    /// Creates a detent scroll container with the specified sections and configuration.
    ///
    /// - Parameters:
    ///   - sectionHeights: Height of each section in points.
    ///   - sectionSnapInsets: Optional insets for each section (default: all zeros).
    ///   - configuration: Threshold and resistance configuration.
    ///   - currentSection: Optional binding to observe/control current section.
    ///   - isScrollDisabled: External signal to disable scrolling (e.g., when content is zoomed).
    ///   - content: The content to display.
    public init(
        sectionHeights: [CGFloat],
        sectionSnapInsets: [CGFloat]? = nil,
        configuration: DetentScrollConfiguration = .default,
        currentSection: Binding<Int>? = nil,
        isScrollDisabled: Bool = false,
        @ViewBuilder content: () -> Content
    )
}
```

### Usage Example

```swift
struct PrototypeView: View {
    @State private var currentSection: Int = 0
    @State private var isZoomed: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            DetentScrollContainer(
                sectionHeights: [screenHeight, 600, screenHeight],
                sectionSnapInsets: [0, 100, 0],
                configuration: DetentScrollConfiguration(threshold: 150),
                currentSection: $currentSection,
                isScrollDisabled: isZoomed
            ) {
                VStack(spacing: 0) {
                    // Section 1: Zoomable content
                    MercurialPanZoomView(onZoomChanged: { isZoomed = $0 })
                        .frame(height: screenHeight)

                    // Section 2: Cards
                    CardsSection()
                        .frame(height: 600)

                    // Section 3: More content
                    MoreContent()
                        .frame(height: screenHeight)
                }
            }
        }
    }
}
```

## API Comparison: v1 vs v2

| Feature | v1 (DetentScrollView) | v2 (DetentScrollContainer) |
|---------|----------------------|---------------------------|
| Type | `View` | `UIViewControllerRepresentable` |
| Gesture System | SwiftUI `DragGesture` | UIKit `UIPanGestureRecognizer` |
| Init Parameters | Same | Same |
| Configuration | `DetentScrollConfiguration` | Same (reused) |
| Section Binding | `Binding<Int>?` | Same |
| Scroll Disable | `isScrollDisabled: Bool` | Same |
| Content | `@ViewBuilder` | Same |

## Configuration (Reused from v1)

```swift
public struct DetentScrollConfiguration {
    /// Drag distance required to trigger a section transition (default: 120pt)
    public var threshold: CGFloat

    /// Rubber-band resistance coefficient (default: 0.55)
    public var resistanceCoefficient: CGFloat

    /// Minimum drag distance before scroll gesture activates (default: 10pt)
    public var minimumDragDistance: CGFloat

    public init(
        threshold: CGFloat = 120,
        resistanceCoefficient: CGFloat = 0.55,
        minimumDragDistance: CGFloat = 10
    )

    public static let `default` = DetentScrollConfiguration()
}
```

## Internal API (DetentScrollViewController)

For advanced use cases or testing, the view controller can be used directly:

```swift
@MainActor
public class DetentScrollViewController: UIViewController {

    // MARK: - Configuration

    /// Section heights in points
    public var sectionHeights: [CGFloat]

    /// Snap insets for each section
    public var sectionSnapInsets: [CGFloat]

    /// Scroll behavior configuration
    public var configuration: DetentScrollConfiguration

    /// When true, scroll gestures are ignored
    public var isScrollDisabled: Bool

    // MARK: - State (Read-only)

    /// Current section index
    public private(set) var currentSection: Int

    /// Whether momentum animation is active
    public var isAnimating: Bool { get }

    // MARK: - Callbacks

    /// Called when section changes
    public var onSectionChanged: ((Int) -> Void)?

    // MARK: - Methods

    /// Sets the SwiftUI content to display
    public func setContent<V: View>(_ content: V)

    /// Programmatically scrolls to a section
    public func scrollToSection(_ section: Int, animated: Bool = true)

    /// Stops any active momentum animation
    public func stopAnimation()
}
```

## Gesture Delegate Protocol

For child views that need to coordinate gestures:

```swift
/// Protocol for views that need to coordinate with DetentScrollContainer's gestures.
public protocol DetentScrollGestureCoordinating: AnyObject {
    /// Whether the coordinating view wants to disable scroll (e.g., when zoomed)
    var wantsScrollDisabled: Bool { get }

    /// Called when scroll gesture wants to begin
    /// Return false to prevent scroll and allow the touch to pass through
    func detentScrollShouldBegin() -> Bool
}
```

## Accessibility

```swift
extension DetentScrollViewController {
    /// Accessibility label for the scroll view
    public var accessibilityLabel: String? { get set }

    /// Whether to announce section changes to VoiceOver
    public var announceSectionChanges: Bool { get set }
}
```

## Thread Safety

All public API is `@MainActor` isolated. The view controller and its configuration must only be accessed from the main thread.

```swift
@MainActor
public class DetentScrollViewController: UIViewController { ... }
```

## Error Handling

The API is designed to be defensive:

- Empty `sectionHeights` results in no-op scrolling
- Out-of-bounds section indices are clamped
- Mismatched `sectionSnapInsets` count is padded with zeros
