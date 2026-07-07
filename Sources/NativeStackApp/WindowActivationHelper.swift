import SwiftUI

extension View {
    /// Menu bar panels and dashboard windows must accept the first click while inactive.
    func activatesWindowOnAppear() -> some View {
        allowsWindowActivationEvents(true)
    }
}
