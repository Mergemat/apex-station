import ApexKit
import SwiftUI

/// The whole window: drifting blue backdrop, a floating glass tab bar, and the current page.
struct RootView: View {
    enum Page: String, CaseIterable, Identifiable {
        case controller = "Controller"
        case buttons = "Buttons"
        case sticks = "Sticks"
        case device = "Device"
        var id: Self { self }
        var icon: String {
            switch self {
            case .controller: "gamecontroller.fill"
            case .buttons: "square.grid.2x2"
            case .sticks: "circle.circle"
            case .device: "slider.horizontal.3"
            }
        }
    }

    /// `-startPage <name>` on the command line opens a specific tab (used for screenshots).
    @ViewState private var page: Page = UserDefaults.standard.string(forKey: "startPage").flatMap { Page(rawValue: $0.capitalized) } ?? .controller
    @Namespace private var tabs

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()
            VStack(spacing: 0) {
                header
                    .padding(.top, 14)
                    .padding(.horizontal, 28)
                ScrollView {
                    Group {
                        switch page {
                        case .controller: ControllerPage()
                        case .buttons: ButtonsPage()
                        case .sticks: SticksPage()
                        case .device: DevicePage()
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                .scrollIndicators(.never)
            }
        }
        .foregroundStyle(.white)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.2), value: page)
    }

    private var header: some View {
        HStack {
            // Leaves room for the window's traffic lights.
            Color.clear.frame(width: 64, height: 1)
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.fill").foregroundStyle(Theme.accent)
                Text("APEX STATION").font(.system(size: 13, weight: .heavy)).tracking(3)
            }
            Spacer()
            tabBar
            Spacer()
            ConnectionBadge()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Page.allCases) { p in
                Button { page = p } label: {
                    Label(p.rawValue, systemImage: p.icon)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(page == p ? .white : Theme.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            if page == p {
                                Capsule().fill(Theme.accent)
                                    .matchedGeometryEffect(id: "tab", in: tabs)
                                    .bloom(true, radius: 10)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glass(.capsule)
    }
}

private struct ConnectionBadge: View {
    @Environment(ControllerService.self) private var service

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(service.live ? Theme.glow : service.connected ? Theme.accent : Color.white.opacity(0.25))
                .frame(width: 7, height: 7)
                .bloom(service.live, radius: 5)
            Text(text).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glass(.capsule)
    }

    private var text: String {
        if !service.connected { return "No controller" }
        if service.live { return "\(service.reportRate) Hz" }
        return "Connected"
    }
}
