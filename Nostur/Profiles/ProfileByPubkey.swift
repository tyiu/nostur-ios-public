//
//  ProfileByPubkey.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI

struct ProfileByPubkey: View {
    @EnvironmentObject private var themes:Themes
    
    public let pubkey:String
    public var tab:String?
        
    @State private var editingAccount:Account? = nil
    @StateObject private var vm = FetchVM<NRContact>()

    var body: some View {
        switch vm.state {
        case .initializing, .loading, .altLoading:
            ProgressView()
                .frame(alignment: .center)
                .onAppear {
                    vm.setFetchParams((
                        prio: false,
                        req: { _ in
                            bg().perform { // 1. FIRST CHECK LOCAL DB
                                if let contact = Contact.fetchByPubkey(pubkey, context: bg()) {
                                    let nrContact = NRContact(contact: contact, following: isFollowing(pubkey))
                                    vm.ready(nrContact) // 2A. DONE
                                }
                                else { req(RM.getUserMetadata(pubkey: pubkey)) } // 2B. FETCH IF WE DONT HAVE
                            }
                        }, 
                        onComplete: { relayMessage, _ in
                            bg().perform { // 3. WE SHOULD HAVE IT IN LOCAL DB NOW
                                if let contact = Contact.fetchByPubkey(pubkey, context: bg()) {
                                    let nrContact = NRContact(contact: contact, following: isFollowing(pubkey))
                                    vm.ready(nrContact)
                                }
                                else { // 4. OR ELSE WE TIMEOUT
                                    vm.timeout()
                                }
                            }
                        },
                        altReq: nil
                    ))
                    vm.fetch()
                }
        case .ready(let nrContact):
            ProfileView(nrContact: nrContact, tab:tab)
                .preference(key: TabTitlePreferenceKey.self, value: nrContact.anyName)
        case .timeout:
            VStack {
                Spacer()
                Text("Time-out")
                Button("Try again") { vm.state = .loading; vm.fetch() }
                Spacer()
            }
            .onAppear {
                guard let account = account() else { return }
                if account.publicKey == pubkey {
                    editingAccount = account
                }
            }
            .sheet(item: $editingAccount) { account in
                NavigationStack {
                    AccountEditView(account: account)
                }
                .presentationBackground(themes.theme.background)
            }
        case .error(let error):
            Text(error)
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        ProfileByPubkey(pubkey: "77bbc321087905d98f941bd9d4cc4d2856fdc0f2f083f3ae167544e1a3b39e91")
    }
}
