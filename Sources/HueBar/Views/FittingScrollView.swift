import SwiftUI

/// A vertical `ScrollView` that is only as tall as its content, up to `maxHeight`.
/// Lets the menu bar panel shrink to fit short lists instead of leaving empty space.
struct FittingScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content

    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
        }
        .frame(height: min(contentHeight ?? maxHeight, maxHeight))
    }
}
