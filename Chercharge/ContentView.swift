//
//  ContentView.swift
//  Chercharge
//

import SwiftUI

struct ContentView: View {
    @Environment(BookingStore.self) private var store
    @State private var selectedTab: MainTab = .home
    @State private var homePath = NavigationPath()
    @State private var bookingsPath = NavigationPath()

    var body: some View {
        Group {
            switch selectedTab {
            case .home:
                NavigationStack(path: $homePath) {
                    HomeView(path: $homePath) {
                        withAnimation(ConciergeLuxe.softEase) {
                            selectedTab = .vehicles
                        }
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route, path: $homePath)
                    }
                }
            case .bookings:
                NavigationStack(path: $bookingsPath) {
                    BookingsView(path: $bookingsPath) {
                        withAnimation(ConciergeLuxe.softEase) {
                            selectedTab = .home
                        }
                        homePath.append(AppRoute.book)
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route, path: $bookingsPath)
                    }
                }
            case .vehicles:
                NavigationStack {
                    VehiclesView()
                }
            case .profile:
                NavigationStack {
                    ProfileView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isShowingRootTab {
                ConciergeFloatingTabBar(
                    selection: $selectedTab,
                    reservationsBadge: store.activeJob == nil ? 0 : 1
                )
                .padding(.top, 4)
                .padding(.bottom, 4)
                .background(Brand.ivory.opacity(0.001))
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: store.lastCompletedJob?.id) { _, newID in
            guard let newID, selectedTab == .home else { return }
            homePath = NavigationPath()
            homePath.append(AppRoute.complete(jobID: newID))
        }
        .onChange(of: store.activeJob?.needsAnyInspectionApproval) { oldValue, needsApproval in
            // Rising edge only — avoid wiping navigation on every job mutation while approval stays true.
            guard needsApproval == true, oldValue != true else { return }
            selectedTab = .home
            homePath = NavigationPath()
        }
    }

    private var isShowingRootTab: Bool {
        switch selectedTab {
        case .home:
            return homePath.isEmpty
        case .bookings:
            return bookingsPath.isEmpty
        case .vehicles, .profile:
            return true
        }
    }

    /// Clears both tab stacks and lands on Home — used by Live Status / Job Complete / unavailable screens
    /// so “Home” never leaves the user stuck on Reservations after opening tracking from that tab.
    private func navigateHome() {
        homePath = NavigationPath()
        bookingsPath = NavigationPath()
        withAnimation(ConciergeLuxe.softEase) {
            selectedTab = .home
        }
    }

    private func navigateProfile() {
        homePath = NavigationPath()
        bookingsPath = NavigationPath()
        withAnimation(ConciergeLuxe.softEase) {
            selectedTab = .profile
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute, path: Binding<NavigationPath>) -> some View {
        switch route {
        case .book:
            if CherchargeServiceAvailability.isLiveConciergeAvailable {
                BookChargeView(path: path) {
                    path.wrappedValue = NavigationPath()
                    withAnimation(ConciergeLuxe.softEase) {
                        selectedTab = .profile
                    }
                }
            } else {
                ServiceUnavailableView(path: path, kind: .bookACharge, onBackHome: navigateHome)
            }
        case .preOrder:
            // Founding Agreement / nested ProfileRoute links resolve via stack destinations.
            PreOrderView()
                .profileRouteDestinations()
        case .tracking(let jobID):
            if CherchargeServiceAvailability.isLiveConciergeAvailable {
                TrackingView(
                    path: path,
                    jobID: jobID,
                    onBackHome: navigateHome,
                    onOpenProfile: navigateProfile
                )
            } else {
                ServiceUnavailableView(path: path, kind: .liveStatus, onBackHome: navigateHome)
            }
        case .reviewInspection(let jobID, let phase):
            if let job = resolvedJob(id: jobID) {
                CustomerInspectionReviewView(jobID: job.id, phase: phase)
            } else {
                ContentUnavailableView(
                    "Inspection not found",
                    systemImage: "photo",
                    description: Text("No inspection is stored for this booking yet.")
                )
            }
        case .compareInspections(let jobID):
            InspectionComparisonView(jobID: jobID)
        case .complete(let jobID):
            JobCompleteView(path: path, jobID: jobID, onBackHome: navigateHome)
                .profileRouteDestinations()
        case .adminHome:
            AdminHomeView()
        }
    }

    private func resolvedJob(id: UUID) -> ChargeJob? {
        if let active = store.activeJob, active.id == id { return active }
        if let completed = store.lastCompletedJob, completed.id == id { return completed }
        return store.pastJobs.first { $0.id == id }
    }
}

#Preview {
    ContentView()
        .environment(BookingStore())
        .environment(DocumentReviewInbox())
        .environment(TeslaAuthService())
        .environment(AuthService())
        .environment(UserLocationService())
}
