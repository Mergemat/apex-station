import SwiftUI

/// SwiftUI's `@State` property wrapper. In the macOS 27 SDK the name `State` resolves to a
/// macro whose plugin only ships with Xcode, so we reach the wrapper through an alias to
/// keep the project buildable with just the Command Line Tools.
typealias ViewState = SwiftUICore.State
