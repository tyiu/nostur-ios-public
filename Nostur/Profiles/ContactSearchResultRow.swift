//
//  ContactSearchResultRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI

struct ContactSearchResultRow: View {
    @ObservedObject var contact:Contact
    var onSelect:(() -> Void)?
    
    @State var similarPFP = false
    @State var isFollowing = false
    
    var couldBeImposter:Bool {
        guard let account = NosturState.shared.account else { return false }
        guard account.publicKey != contact.pubkey else { return false }
        guard !NosturState.shared.isFollowing(contact.pubkey) else { return false }
        guard contact.couldBeImposter == -1 else { return contact.couldBeImposter == 1 }
        return similarPFP
    }
    
    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: contact.pubkey, contact: contact)
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {                        
                        HStack(alignment: .top, spacing:3) {
                            Text(contact.anyName).font(.headline).foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if couldBeImposter {
                                Text("possible imposter", comment: "Label shown on a profile").font(.system(size: 12.0))
                                    .padding(.horizontal, 8)
                                    .background(.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .padding(.top, 3)
                                    .layoutPriority(2)
                            }
                            else if (contact.nip05veried) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color("AccentColor"))
                            }
                            
                            if let fixedName = contact.fixedName, fixedName != contact.anyName {
                                HStack {
                                    Text("Previously known as: \(fixedName)").font(.caption).foregroundColor(.primary)
                                        .lineLimit(1)
                                    Image(systemName: "multiply.circle.fill")
                                        .onTapGesture {
                                            contact.fixedName = contact.anyName
                                        }
                                }
                            }
                        }
                    }.multilineTextAlignment(.leading)
                    Spacer()
                }
                Text(contact.about ?? "").foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let onSelect {
                onSelect()
            }
        }
        .task {
            if (NosturState.shared.isFollowing(contact.pubkey)) {
                isFollowing = true
            }
            else {
                guard ProcessInfo.processInfo.isLowPowerModeEnabled == false else { return }
                guard contact.metadata_created_at != 0 else { return }
                guard contact.couldBeImposter == -1 else { return }
                guard let cPic = contact.picture else { return }
                let contactAnyName = contact.anyName
                let cPubkey = contact.pubkey
                
                DataProvider.shared().bg.perform {
                    guard let account = NosturState.shared.bgAccount else { return }
                    guard let similarContact = account.follows_.first(where: {
                        isSimilar(string1: $0.anyName.lowercased(), string2: contactAnyName.lowercased())
                    }) else { return }
                    guard let wotPic = similarContact.picture else { return }
                    
                    L.og.debug("😎 ImposterChecker similar name: \(contactAnyName) - \(similarContact.anyName)")
                    
                    Task.detached(priority: .background) {
                        let similarPFP = await pfpsAreSimilar(imposter: cPic, real: wotPic)
                        if similarPFP {
                            L.og.debug("😎 ImposterChecker similar PFP: \(cPic) - \(wotPic) - \(cPubkey)")
                        }
                        
                        DispatchQueue.main.async {
                            self.similarPFP = similarPFP
                            contact.couldBeImposter = similarPFP ? 1 : 0
                        }
                    }
                }
            }
        }
    }
}


struct ContactSearchResultRow_Previews: PreviewProvider {
    static var previews: some View {
        
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            VStack {
                if let contact = PreviewFetcher.fetchContact(pubkey) {
                    ContactSearchResultRow(contact: contact, onSelect: {})
                    
                    ContactSearchResultRow(contact: contact, onSelect: {})
                    
                    ContactSearchResultRow(contact: contact, onSelect: {})
                }
             
                Spacer()
            }
        }
    }
}
