import SwiftUI

/// A vertical `ScrollView` that is only as tall as its content, up to `maxHeight`.
/// Lets the menu bar panel shrink to fit short lists instead of leaving empty space.
struct FittingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
        }
        // Clamp the viewport before requesting the scroll view's ideal content height.
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}
