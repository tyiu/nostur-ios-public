//
//  NosturTabsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

struct NosturTabsView: View {
    @EnvironmentObject private var themes:Themes
    @EnvironmentObject private var dm:DirectMessageViewModel

    @StateObject private var dim = DIMENSIONS()
    @AppStorage("selected_tab") private var selectedTab = "Main"
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Mentions" }
    }

    @State private var unread: Int = 0
    @State private var showTabBar = true
    @ObservedObject private var ss:SettingsStore = .shared
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        HStack {
            VStack {
                Color.clear.frame(height: 0)
                    .modifier(SizeModifier())
                    .onPreferenceChange(SizePreferenceKey.self) { size in
                        guard size.width > 0 else { return }
                        dim.listWidth = size.width
                    }
                NoInternetConnectionBanner()
                TabView(selection: $selectedTab.onUpdate { oldTab, newTab in
                    tabTapped(newTab, oldTab: oldTab)
                }) {
                    Group {
                        MainView()
                            .tabItem { Image(systemName: "house") }
                            .tag("Main")
                        
    //                    DiscoverCommunities()
    //                        .tabItem { Image(systemName: "person.3.fill")}
    //                        .tag("Communities")
                        
                        NotificationsContainer()
                            .tabItem { Image(systemName: "bell.fill") }
                            .tag("Notifications")
                            .badge(unread)
                        
                        Search()
                            .tabItem { Image(systemName: "magnifyingglass") }
                            .tag("Search")
                        
                        BookmarksAndPrivateNotes()
                            .tabItem { Image(systemName: "bookmark") }
                            .tag("Bookmarks")
                            
                        
                        DMContainer()
                            .tabItem { Image(systemName: "envelope.fill") }
                            .tag("Messages")
                            .badge((dm.unread + dm.newRequests))
                    }
                    .toolbarBackground(themes.theme.listBackground, for: .tabBar)
                    .toolbar(!ss.autoHideBars || showTabBar ? .visible : .hidden, for: .tabBar)
                }
                .withSheets()
                .edgesIgnoringSafeArea(.all)
            }
            .frame(maxWidth: 600)
            .environmentObject(dim)
            if UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular {
                DetailPane()
            }
        }
        .contentShape(Rectangle())
        .background(themes.theme.listBackground)
        .withLightningEffect()
        .onChange(of: selectedTab) { newValue in
            if !IS_CATALYST {
                if newValue == "Main" {
                    sendNotification(.scrollingUp) // To show the navigation/toolbar
                }
            }
            if newValue == "Notifications" {
                
                // If there is only one tab with unread notifications, go to that tab
                if NotificationsViewModel.shared.unread > 0 {
                    if NotificationsViewModel.shared.unreadMentions > 0 {
                        UserDefaults.standard.setValue("Mentions", forKey: "selected_notifications_tab")
                    }
                    else if NotificationsViewModel.shared.unreadNewPosts > 0 {
                        UserDefaults.standard.setValue("New Posts", forKey: "selected_notifications_tab")
                    }
                    else if NotificationsViewModel.shared.unreadReactions > 0 {
                        UserDefaults.standard.setValue("Reactions", forKey: "selected_notifications_tab")
                    }
                    else if NotificationsViewModel.shared.unreadZaps > 0 {
                        UserDefaults.standard.setValue("Zaps", forKey: "selected_notifications_tab")
                    }
                    else if NotificationsViewModel.shared.unreadReposts > 0 {
                        UserDefaults.standard.setValue("Reposts", forKey: "selected_notifications_tab")
                    }
                    else if NotificationsViewModel.shared.unreadNewFollowers > 0 {
                        UserDefaults.standard.setValue("Followers", forKey: "selected_notifications_tab")
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    sendNotification(.notificationsTabAppeared) // use for resetting unread count
                }
            }
        }
        .onReceive(receiveNotification(.scrollingUp)) { _ in
            guard !IS_CATALYST && ss.autoHideBars else { return }
            withAnimation {
                showTabBar = true
            }
        }
        .onReceive(receiveNotification(.scrollingDown)) { _ in
            guard !IS_CATALYST && ss.autoHideBars else { return }
            withAnimation {
                showTabBar = false
            }
        }
        .task {
            if ss.receiveLocalNotifications {
                requestNotificationPermission()
            }
        }
        .onReceive(NotificationsViewModel.shared.unreadPublisher) { unread in
            if unread != self.unread {
                self.unread = unread
            }
        }
//        .overlay(alignment: .topLeading) {
//            VStack {
//                Text("h: \(horizontalSizeClass.debugDescription)")
//                Text("v: \(verticalSizeClass.debugDescription)")
//                Spacer()
//            }
//        }
    }

    private func tabTapped(_ tabName:String, oldTab:String) {
        
        // Only do something if we are already on same the tab
        guard oldTab == tabName else { return }

        // For main, we scroll to first unread
        // but depends on condition with values only known in FollowingAndExplore
        sendNotification(.didTapTab, tabName)

        // pop navigation stack back to root
        sendNotification(.clearNavigation, tabName)
    }
}


extension Binding {
    func onUpdate(_ closure: @escaping (Value, Value) -> Void) -> Binding<Value> {
        Binding(get: {
            wrappedValue
        }, set: { newValue in
            let oldValue = wrappedValue
            wrappedValue = newValue
            closure(oldValue, newValue)
        })
    }
}


struct NoInternetConnectionBanner: View {
    @EnvironmentObject private var networkMonitor:NetworkMonitor
    
    var body: some View {
        if networkMonitor.isDisconnected {
            Text("\(Image(systemName: "wifi.exclamationmark")) No internet connection")
                .font(.caption)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(5)
                .background(.red)
        }
        else {
            EmptyView()
        }
    }
}
