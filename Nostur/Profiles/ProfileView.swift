//
//  ProfileView.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/03/2023.
//

import SwiftUI
import Nuke
import NukeUI
import NavigationBackport

struct ProfileView: View {
    private let pubkey: String
    private var tab: String?
    
    @EnvironmentObject private var npn: NewPostNotifier
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var settings: SettingsStore = .shared
    @ObservedObject private var fg: FollowingGuardian = .shared
    @ObservedObject private var nrContact: NRContact
    
    @State private var profilePicViewerIsShown = false
    @State private var selectedSubTab = "Posts"
    @State private var backlog = Backlog(timeout: 4.0, auto: true)
    @State private var lastSeen: String? = nil
    @State private var isFollowingYou = false
    @State private var editingAccount: CloudAccount?
    @State private var similarPFP = false
    @State private var showingNewNote = false
    
    
    init(nrContact: NRContact, tab:String? = nil) {
        self.nrContact = nrContact
        self.pubkey = nrContact.pubkey
        self.tab = tab
    }
    
    private var couldBeImposter: Bool {
        guard let account = account() else { return false }
        guard account.publicKey != nrContact.pubkey else { return false }
        guard !nrContact.following else { return false }
        guard nrContact.couldBeImposter == -1 else { return nrContact.couldBeImposter == 1 }
        return similarPFP
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollView {
            Color.clear.background( // GeometryReader in .background so it does not mess up layout
                GeometryReader { toolbarGEO in
                    Color.clear
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                VStack {
                                    HStack(spacing:2) {
                                        PFP(pubkey: nrContact.pubkey, nrContact: nrContact, size: 25)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(themes.theme.background, lineWidth: 1)
                                            )
                                        Text("\(nrContact.anyName) ").font(.headline)
                                    }
                                    .offset(y: 160 + (max(-160,toolbarGEO.frame(in:.global).minY)))
                                }.frame(height: 40).clipped()
                            }
                            
                            ToolbarItem(placement: .navigationBarTrailing) {
                                VStack {
                                    if pubkey == NRState.shared.activeAccountPublicKey {
                                        Button {
                                            guard let account = account() else { return }
                                            guard isFullAccount(account) else { showReadOnlyMessage(); return }
                                            editingAccount = account
                                        } label: {
                                            Text("Edit profile", comment: "Button to edit own profile")
                                        }
                                        .buttonStyle(NosturButton())
                                        .sheet(item: $editingAccount) { account in
                                            NBNavigationStack {
                                                AccountEditView(account: account)
                                            }
                                            .nbUseNavigationStack(.never)
                                            .presentationBackgroundCompat(themes.theme.background)
                                        }
                                        .offset(y: 123 + (max(-123,toolbarGEO.frame(in:.global).minY)))
                                    }
                                    else {
                                        Button {
                                            guard isFullAccount() else { showReadOnlyMessage(); return }
                                            if (nrContact.following && !nrContact.privateFollow) {
                                                nrContact.follow(privateFollow: true)
                                            }
                                            else if (nrContact.following && nrContact.privateFollow) {
                                                nrContact.unfollow()
                                            }
                                            else {
                                                nrContact.follow()
                                            }
                                        } label: {
                                            FollowButton(isFollowing:nrContact.following, isPrivateFollowing:nrContact.privateFollow)
                                        }
                                        .offset(y: 123 + (max(-123,toolbarGEO.frame(in:.global).minY)))
                                    }
                                }.frame(height: 40).clipped()
                                    .layoutPriority(2)
                            }
                        }
                }
            )
            
            LazyVStack(alignment:.leading, spacing:0, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack {
                        GeometryReader { geoBanner in
                            ProfileBanner(banner: nrContact.banner, width: dim.listWidth)
                                .overlay(alignment: .bottomLeading, content: {
                                    PFP(pubkey: nrContact.pubkey, nrContact: nrContact, size: DIMENSIONS.PFP_BIG)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(themes.theme.background, lineWidth: 3)
                                        )
                                        .onTapGesture {
                                            if (nrContact.pictureUrl != nil) {
                                                profilePicViewerIsShown = true
                                            }
                                        }
                                        .scaleEffect(min(1,max(0.5,geoBanner.frame(in:.global).minY / 70 + 1.3)), anchor:.bottom)
                                        .offset(x: 10, y: DIMENSIONS.PFP_BIG/2)
                                })
                            
                        }
                        
                        VStack(alignment: .leading) {
                            HStack(alignment:.top) {
                                if (!settings.hideBadges) {
                                    ProfileBadgesContainer(pubkey: nrContact.pubkey)
                                        .offset(x: 85, y: 0)
                                }
                                
                                Spacer()
                                
                                if npn.isEnabled(for: nrContact.pubkey) {
                                    Image(systemName: "bell")
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .resizable()
                                                .frame(width: 10, height: 10)
                                                .foregroundColor(.green)
                                                .background(themes.theme.background)
                                                .offset(y: -3)
                                        }
                                        .offset(y: 3)
                                        .onTapGesture { npn.toggle(nrContact.pubkey) }
                                        .padding([.trailing, .top], 5)
                                }
                                else {
                                    Image(systemName: "bell")
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: "plus")
                                                .resizable()
                                                .frame(width: 10, height: 10)
                                                .background(themes.theme.background)
                                                .border(themes.theme.background, width: 2.0)
                                                .offset(y: -3)
                                        }
                                        .offset(y: 3)
                                        .onTapGesture { npn.toggle(nrContact.pubkey) }
                                        .padding([.trailing, .top], 5)
                                }
                                
                                
                                if account()?.isFullAccount ?? false {
                                    Button {
                                        UserDefaults.standard.setValue("Messages", forKey: "selected_tab")
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                            sendNotification(.triggerDM, (nrContact.pubkey, nrContact.mainContact))
                                        }
                                    } label: { Image(systemName: "envelope.fill") }
                                    .buttonStyle(NosturButton())
                                }
                                
                                if nrContact.anyLud {
                                    ProfileLightningButton(contact: nrContact.mainContact)
                                }
                                
                                if pubkey == NRState.shared.activeAccountPublicKey {
                                    Button {
                                        guard let account = account() else { return }
                                        guard isFullAccount(account) else { showReadOnlyMessage(); return }
                                        editingAccount = account
                                    } label: {
                                        Text("Edit profile", comment: "Button to edit own profile")
                                    }
                                    .buttonStyle(NosturButton())
                                    .sheet(item: $editingAccount) { account in
                                        NBNavigationStack {
                                            AccountEditView(account: account)
                                        }
                                        .nbUseNavigationStack(.never)
                                        .presentationBackgroundCompat(themes.theme.background)
                                    }
                                }
                                else {
                                    Button {
                                        guard isFullAccount() else { showReadOnlyMessage(); return }
                                        if (nrContact.following && !nrContact.privateFollow) {
                                            nrContact.follow(privateFollow: true)
                                        }
                                        else if (nrContact.following && nrContact.privateFollow) {
                                            nrContact.unfollow()
                                        }
                                        else {
                                            nrContact.follow()
                                        }
                                    } label: {
                                        FollowButton(isFollowing:nrContact.following, isPrivateFollowing:nrContact.privateFollow)
                                    }
                                    .disabled(nrContact.pubkey != account()?.publicKey && !fg.didReceiveContactListThisSession)
                                    .padding(.trailing, 10)
                                }
                            }
                            .padding(.top, 10)
                            
                            HStack(spacing:0) {
                                Text("\(nrContact.anyName) ").font(.system(size: 24, weight:.bold))
                                if couldBeImposter {
                                    Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                                        .padding(.horizontal, 8)
                                        .background(.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                        .layoutPriority(2)
                                }
                                else if nrContact.nip05verified, let nip05 = nrContact.nip05 {
                                    NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly.lowercased())
                                        .layoutPriority(3)
                                }
                            }
                            if let fixedName = nrContact.fixedName, fixedName != nrContact.anyName {
                                HStack {
                                    Text("Previously known as: \(fixedName)").font(.caption).foregroundColor(.primary)
                                        .lineLimit(1)
                                    Image(systemName: "multiply.circle.fill")
                                        .onTapGesture {
                                            nrContact.setFixedName(nrContact.anyName)
                                        }
                                }
                            }
                            
                            Text(verbatim:lastSeen ?? "Last seen:")
                                .font(.caption).foregroundColor(.primary)
                                    .lineLimit(1)
                                .opacity(lastSeen != nil ? 1.0 : 0)
                            
                            HStack {
                                if let mainContact = nrContact.mainContact {
                                    ContactPrivateNoteToggle(contact: mainContact)
                                }
                                Menu {
                                    Button {
                                        UIPasteboard.general.string = npub(nrContact.pubkey)
                                    } label: {
                                        Label(String(localized:"Copy npub", comment:"Menu action"), systemImage: "doc.on.clipboard")
                                    }
                                    Button {
                                        bg().perform {
                                            let kind0 = Event.fetchRequest()
                                            kind0.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                                            kind0.predicate = NSPredicate(format: "pubkey == %@ AND kind == 0", nrContact.pubkey)
                                            
                                            if let event = try? bg().fetch(kind0).first {
                                                let json = event.toNEvent().eventJson()
                                                DispatchQueue.main.async {
                                                    UIPasteboard.general.string = json
                                                }
                                            }
                                        }
                                    } label: {
                                        Label(String(localized:"Copy profile source", comment:"Menu action"), systemImage: "doc.on.clipboard")
                                    }
                                    
                                    Button {
                                        sendNotification(.addRemoveToListsheet, nrContact.mainContact)
                                    } label: {
                                        Label(String(localized:"Add/Remove from feeds", comment:"Menu action"), systemImage: "person.2.crop.square.stack")
                                    }
                                    
                                    
                                    Button {
                                        block(pubkey: nrContact.pubkey, name: nrContact.anyName)
                                    } label: {
                                        Label(
                                            String(localized:"Block \(nrContact.anyName)", comment:"Menu action"), systemImage: "slash.circle")
                                    }
                                    Button {
                                        sendNotification(.reportContact, nrContact.mainContact)
                                    } label: {
                                        Label(String(localized:"Report \(nrContact.anyName)", comment:"Menu action"), systemImage: "flag")
                                    }
                                    
                                    
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .fontWeightBold()
                                        .padding(5)
                                }
                                if (isFollowingYou) {
                                    Text("Follows you", comment: "Label shown when someone follows you").font(.system(size: 12))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary)
                                        .opacity(0.7)
                                        .cornerRadius(13)
                                        .offset(y: -4)
                                }
                            }
                            
                            NRTextDynamic("\(String(nrContact.about ?? ""))\n")
                            
                            HStack(alignment: .center, spacing: 10) {
                                ProfileFollowingCount(pubkey: pubkey)
                                
                                Text("**♾️** Followers", comment: "Label for followers count")
                                    .onTapGesture {
                                        selectedSubTab = "Followers"
                                    }
                            }
                            .frame(height: 30)
                        }
                        .padding(10)
                        .padding(.top, 120)
                    }
                }
                ProfileTabs(nrContact: nrContact, selectedSubTab: $selectedSubTab)
            }
        }
        .background(themes.theme.background)
//        .onReceive(receiveNotification(.newFollowingListFromRelay)) { notification in // TODO: MOVE TO FOLLOWING LIST TAB
//            let nEvent = notification.object as! NEvent
//            if nEvent.publicKey == contact.pubkey {
//                contact.objectWillChange.send()
//            }
//        }
        .overlay(alignment: .bottomTrailing) {
            NewNoteButton(showingNewNote: $showingNewNote)
                .padding([.top, .leading, .bottom], 10)
                .padding([.trailing], 25)
        }
        .sheet(isPresented: $showingNewNote) {
            NBNavigationStack {
                if let account = Nostur.account() {
                    if account.isNC {
                        WithNSecBunkerConnection(nsecBunker: NSecBunkerManager.shared) {
                            ComposePostCompat(directMention: nrContact.mainContact, onDismiss: { showingNewNote = false })
                        }
                    }
                    else {
                        ComposePostCompat(directMention: nrContact.mainContact, onDismiss: { showingNewNote = false })
                    }
                }
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.background)
        }
        .onAppear {
            if let tab = tab {
                selectedSubTab = tab
            }
        }
        .task { [weak nrContact] in
            bg().perform {
                guard let nrContact, let contact = nrContact.contact else { return }
                if (NIP05Verifier.shouldVerify(contact)) {
                    NIP05Verifier.shared.verify(contact)
                }
            }
        }
        .onChange(of: nrContact.nip05) { [weak nrContact] nip05 in
            bg().perform {
                guard let nrContact, let contact = nrContact.contact else { return }
                if (NIP05Verifier.shouldVerify(contact)) {
                    NIP05Verifier.shared.verify(contact)
                }
            }
        }
        .fullScreenCover(isPresented: $profilePicViewerIsShown) {
            ProfilePicFullScreenSheet(profilePicViewerIsShown: $profilePicViewerIsShown, pictureUrl:nrContact.pictureUrl!, isFollowing: nrContact.following)
                .environmentObject(themes)
        }
        .task { [weak nrContact] in
            guard let nrContact else { return }
            guard !SettingsStore.shared.lowDataMode else { return }
            let contact = nrContact
            guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
            guard !contact.following else { return }
            guard contact.metadata_created_at != 0 else { return }
            guard contact.couldBeImposter == -1 else { return }
            guard let cPic = contact.pictureUrl else { return }
            guard !NewOnboardingTracker.shared.isOnboarding else { return }
            
            let contactAnyName = contact.anyName.lowercased()
            let cPubkey = contact.pubkey
            let currentAccountPubkey = NRState.shared.activeAccountPublicKey
            
            bg().perform { [weak contact] in
                guard let account = account() else { return }
                guard account.publicKey == currentAccountPubkey else { return }
                guard let similarContact = account.follows.first(where: {
                    $0.pubkey != cPubkey && isSimilar(string1: $0.anyName.lowercased(), string2: contactAnyName)
                }) else { return }
                guard similarContact.picture != nil, let wotPic = similarContact.pictureUrl else { return }
                
                L.og.debug("😎 ImposterChecker similar name: \(contactAnyName) - \(similarContact.anyName)")
                
                Task.detached(priority: .background) {
                    let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                    if similarPFP {
                        L.og.debug("😎 ImposterChecker similar PFP: \(cPic) - \(wotPic) - \(cPubkey)")
                    }
                    
                    DispatchQueue.main.async {
                        guard let contact else { return }
                        guard currentAccountPubkey == NRState.shared.activeAccountPublicKey else { return }
                        self.similarPFP = similarPFP
                        contact.couldBeImposter = similarPFP ? 1 : 0
                    }
                }
            }
        }
        .task { [weak backlog] in
            guard let backlog else { return }
            let contactPubkey = pubkey
            let reqTask = ReqTask(prefix: "SEEN-", reqCommand: { taskId in
                req(RM.getLastSeen(pubkey: contactPubkey, subscriptionId: taskId))
            }, processResponseCommand: { taskId, _, _ in
                bg().perform {
                    if let last = Event.fetchLastSeen(pubkey: contactPubkey, context: bg()) {
                        let agoString = last.date.agoString
                        DispatchQueue.main.async {
                            lastSeen = String(localized: "Last seen: \(agoString) ago", comment:"Label on profile showing when last seen, example: Last seen: 10m ago")
                        }
                    }
                }
            }, timeoutCommand: { taskId in
                bg().perform {
                    if let last = Event.fetchLastSeen(pubkey: contactPubkey, context: bg()) {
                        let agoString = last.date.agoString
                        DispatchQueue.main.async {
                            lastSeen = String(localized: "Last seen: \(agoString) ago", comment:"Label on profile showing when last seen, example: Last seen: 10m ago")
                        }
                    }
                }
            })
            
            backlog.add(reqTask)
            reqTask.fetch()
        }
        .task { [weak nrContact, weak backlog] in
            guard let backlog else { return }
            bg().perform {
                guard let contact = nrContact?.contact else { return }
                EventRelationsQueue.shared.addAwaitingContact(contact)
                if (contact.followsYou()) {
                    DispatchQueue.main.async {
                        isFollowingYou = true
                    }
                }
                
                let task = ReqTask(
                    reqCommand: { [weak contact] (taskId) in
                        guard let contact else { return }
                        req(RM.getUserProfileKinds(pubkey: contact.pubkey, subscriptionId: taskId, kinds: [0,3,30008,10002]))
                    },
                    processResponseCommand: { [weak contact] (taskId, _, _) in
                        bg().perform {
                            guard let contact else { return }
                            if (contact.followsYou()) {
                                DispatchQueue.main.async {
                                    isFollowingYou = true
                                }
                            }
                        }
                    },
                    timeoutCommand: { [weak contact] taskId in
                        bg().perform {
                            guard let contact else { return }
                            if (contact.followsYou()) {
                                DispatchQueue.main.async {
                                    isFollowingYou = true
                                }
                            }
                        }
                    })

                backlog.add(task)
                task.fetch()
                
                if (NIP05Verifier.shouldVerify(contact)) {
                    NIP05Verifier.shared.verify(contact)
                }
             
                guard contact.anyLud else { return }
                let lud16orNil = contact.lud16
                let lud06orNil = contact.lud06
                Task { [weak contact] in
                    do {
                        if let lud16 = lud16orNil, lud16 != "" {
                            let response = try await LUD16.getCallbackUrl(lud16: lud16)
                            if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                                await bg().perform {
                                    guard let contact else { return }
                                    contact.zapperPubkey = response.nostrPubkey!
                                    L.og.info("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                                }
                            }
                        }
                        else if let lud06 = lud06orNil, lud06 != "" {
                            let response = try await LUD16.getCallbackUrl(lud06: lud06)
                            if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                                await bg().perform {
                                    guard let contact else { return }
                                    contact.zapperPubkey = response.nostrPubkey!
                                    L.og.info("contact.zapperPubkey updated: \(response.nostrPubkey!)")
                                }
                            }
                        }
                    }
                    catch {
                        L.og.error("problem in lnurlp \(error)")
                    }
                }
            }
        }
    }
}

#Preview("ProfileView") {
        //        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
//                        let f = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        //        let snowden = PreviewFetcher.fetchContact(pubkey)
        
        //        let testgif = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        
//        let testtransparentpfp = "7fa56f5d6962ab1e3cd424e758c3002b8665f7b0d8dcee9fe9e288d7751ac194"
        
        
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            NBNavigationStack {
                if let contact = PreviewFetcher.fetchNRContact() {
                    VStack {
                        ProfileView(nrContact: contact)
                    }
                }
            }
        }
    }

