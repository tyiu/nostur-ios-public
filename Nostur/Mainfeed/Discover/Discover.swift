//
//  Discover.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/06/2024.
//

import SwiftUI
import NavigationBackport

struct Discover: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject var settings: SettingsStore = .shared
    @EnvironmentObject var discoverVM: DiscoverViewModel
    @State private var showSettings = false
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Discover" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_subtab") }
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            switch discoverVM.state {
            case .initializing, .loading:
                CenteredProgressView()
                    .task(id: "discover") {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(discoverVM.timeoutSeconds) * NSEC_PER_SEC)
                            discoverVM.timeout()
                        } catch { }
                    }
            case .ready:
                List(discoverVM.discoverPosts) { nrPost in
                    PostOrThread(nrPost: nrPost)
                        .onBecomingVisible {
                            // SettingsStore.shared.fetchCounts should be true for below to work
                            discoverVM.prefetch(nrPost)
                        }
                        .id(nrPost.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(themes.theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .environment(\.defaultMinListRowHeight, 50)
                .listStyle(.plain)
                .refreshable {
                    await discoverVM.refresh()
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Discover" else { return }
                    self.scrollToTop(proxy)
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Discover" else { return }
                    self.scrollToTop(proxy)
                }
                .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                    discoverVM.reload()
                }
                .padding(0)
            case .timeout:
                VStack {
                    Spacer()
                    Text("Time-out while loading discover feed")
                    Button("Try again") { discoverVM.reload() }
                    Spacer()
                }
            }
        }
        .background(themes.theme.listBackground)
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "Discover" else { return }
            discoverVM.load()
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard !IS_CATALYST else { return }
            guard selectedTab == "Main" && selectedSubTab == "Discover" else { return }
            guard discoverVM.shouldReload else { return }
            discoverVM.state = .loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // Reconnect delay
                discoverVM.load()
            }
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Discover" else { return }
            discoverVM.load() // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                DiscoverFeedSettings(discoverVM: discoverVM)
                    .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
        }
    }
    
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let topPost = discoverVM.discoverPosts.first else { return }
        withAnimation {
            proxy.scrollTo(topPost.id, anchor: .top)
        }
    }
}

struct Discover_Previews: PreviewProvider {
    static var previews: some View {
        Discover()
            .environmentObject(DiscoverViewModel())
            .environmentObject(Themes.default)
    }
}
