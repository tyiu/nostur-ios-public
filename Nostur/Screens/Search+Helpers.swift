//
//  Search+Helpers.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/09/2023.
//

import Foundation
import NostrEssentials

func typeOfSearch(_ searchInput:String) -> TypeOfSearch {
    let searchTrimmed = removeUriPrefix(searchInput.trimmingCharacters(in: .whitespacesAndNewlines))
    
    if (searchTrimmed.prefix(9) == "nprofile1") {
        return .nprofile1(searchTrimmed)
    }
    else if (searchTrimmed.prefix(7) == "nevent1") {
        return .nevent1(searchTrimmed)
    }
    else if (searchTrimmed.prefix(6) == "naddr1") {
        return .naddr1(searchTrimmed)
    }
    else if (searchTrimmed.prefix(5) == "npub1") {
        return .npub1(searchTrimmed)
    }
    else if (searchTrimmed.prefix(1) == "@") {
        if searchTrimmed.contains(".") {
            let domain = String(searchTrimmed.dropFirst(1))
            let name = "_"
            
            let url = URL(string: "https://\(domain)/.well-known/nostr.json?name=\(name)")
            
            return .nip05(Nip05Parts(nip05url: url, domain: domain, name: name))
        }
        return .nametag(String(searchTrimmed.dropFirst(1)))
    }
    else if (searchTrimmed.prefix(1) == "#") {
        return .hashtag(String(searchTrimmed.dropFirst(1)))
    }
    else if (searchTrimmed.prefix(5) == "note1") {
        return .note1(searchTrimmed)
    }
    else if (searchTrimmed.count == 64) {
        return .hexId(searchTrimmed)
    }
    else if (searchTrimmed.prefix(8) == "https://") {
        return .url(searchTrimmed)
    }
    else if searchTrimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).count == 2 {
        let nip05parts = searchTrimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
        
        let domain = String(nip05parts[1])
        let name = String(nip05parts[0])
        
        let url = URL(string: "https://\(domain)/.well-known/nostr.json?name=\(name)")
        
        return .nip05(Nip05Parts(nip05url: url, domain: domain, name: name))
    }
    
    
    return .other(searchTrimmed)
}

public enum TypeOfSearch {
    case nprofile1(String)
    case naddr1(String)
    case nevent1(String)
    case npub1(String)
    case nametag(String)
    case hashtag(String)
    case note1(String)
    case hexId(String)
    case nip05(Nip05Parts)
    case url(String)
    case other(String)
}

public struct Nip05Parts {
    var nip05url:URL?
    let domain:String
    let name:String
}

extension Search {
    
    func nprofileSearch(_ term:String) {
        guard let identifier = try? ShareableIdentifier(term),
              let pubkey = identifier.pubkey
        else { return }
        
        searching = true
        contacts.nsPredicate = NSPredicate(format: "pubkey = %@", pubkey)
        nrPosts = []
        req(RM.getUserMetadata(pubkey: pubkey), relayType: .SEARCH)
        
        guard !identifier.relays.isEmpty else { return }
        
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(3) * NSEC_PER_SEC)
                await bg().perform {
                    // If we don't have the event after X seconds, fetch from relay hint
                    if Contact.fetchByPubkey(pubkey, context: bg()) == nil {
                        if let relay = identifier.relays.first {
                            ConnectionPool.shared.sendEphemeralMessage(RM.getUserMetadata(pubkey: pubkey), relay: relay)
                        }
                    }
                }
            }
            catch { }
        }
    }
    
    func naddrSearch(_ term:String) {
        guard let naddr = try? ShareableIdentifier(term),
              let kind = naddr.kind,
              let pubkey = naddr.pubkey,
              let definition = naddr.eventId
        else { return }
        
        searching = true
        contacts.nsPredicate = NSPredicate(value: false)
        
        bg().perform {
            if let article = Event.fetchReplacableEvent(
                kind,
                pubkey: pubkey,
                definition: definition,
                context: bg()) {
                
                let article = NRPost(event: article)
                
                Task { @MainActor in
                    self.nrPosts = [article]
                }
            }
            else {
                let reqTask = ReqTask(
                    prefix: "ARTICLESEARCH-",
                    reqCommand: { taskId in
                        req(RM.getArticle(pubkey: pubkey, kind:Int(kind), definition:definition, subscriptionId: taskId), relayType: .SEARCH)
                    },
                    processResponseCommand: { taskId, _, _ in
                        bg().perform {
                            if let article = Event.fetchReplacableEvent(
                                kind,
                                pubkey: pubkey,
                                definition: definition,
                                context: bg()) {
                                
                                let article = NRPost(event: article)
                                Task { @MainActor in
                                    self.nrPosts = [article]
                                }
                                
                                backlog.clear()
                            }
                        }
                    },
                    timeoutCommand: { taskId in
                        guard !naddr.relays.isEmpty else { return }
                        searchTask = Task {
                            do {
                                try await Task.sleep(nanoseconds: UInt64(3) * NSEC_PER_SEC)
                                await bg().perform {
                                    // If we don't have the event after X seconds, fetch from relay hint
                                    guard Event.fetchReplacableEvent(
                                        kind,
                                        pubkey: pubkey,
                                        definition: definition,
                                        context: bg()) == nil else { return }
                                    
                                    guard let relay = naddr.relays.first else { return }
                                    
                                    ConnectionPool
                                        .shared
                                        .sendEphemeralMessage(
                                            RM.getArticle(
                                                pubkey: pubkey,
                                                kind: Int(kind),
                                                definition: definition,
                                                subscriptionId: taskId
                                            ),
                                            relay: relay
                                        )
                                }
                            }
                            catch { }
                        }
                    })
                
                backlog.add(reqTask)
                reqTask.fetch()
            }
        }
    }
    
    func neventSearch(_ term:String) {
        guard let identifier = try? ShareableIdentifier(term),
              let noteHex = identifier.eventId
        else { return }
        
        searching = true
        contacts.nsPredicate = NSPredicate(value: false)
        
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "id = %@", noteHex)
        fr.fetchLimit = 1
        
        bg().perform {
            guard let result = try? bg().fetch(fr).first
            else { return }
            
            let nrPost = NRPost(event: result)
            Task { @MainActor in
                self.nrPosts = [nrPost]
            }
        }
        
        let searchTask1 = ReqTask(prefix: "SEA-", reqCommand: { taskId in
            req(RM.getEvent(id: noteHex, subscriptionId: taskId), relayType: .SEARCH)
        }, processResponseCommand: { taskId, _, _ in
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "id = %@", noteHex)
            fr.fetchLimit = 1
            bg().perform {
                guard let result = try? bg().fetch(fr).first
                else { return }
                let nrPost = NRPost(event: result)
                Task { @MainActor in
                    self.nrPosts = [nrPost]
                }
            }
        })
        backlog.add(searchTask1)
        searchTask1.fetch()
        
        
        guard !identifier.relays.isEmpty else { return }
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(3) * NSEC_PER_SEC)
                await bg().perform {
                    // If we don't have the event after X seconds, fetch from relay hint
                    guard (try? Event.fetchEvent(id: noteHex, context: bg())) == nil
                    else { return }
                    
                    guard let relay = identifier.relays.first else { return }
                    ConnectionPool.shared.sendEphemeralMessage(RM.getEvent(id: noteHex, subscriptionId:searchTask1.subscriptionId), relay: relay)
                }
            }
            catch { }
        }
    }
    
    func npubSearch(_ term: String) {
        searching = true
        guard NostrRegexes.default.matchingStrings(term, regex: NostrRegexes.default.cache[.npub]!).count == 1
        else { return }
        
        guard let pubkey = Keys.hex(npub: term) else { return }
        contacts.nsPredicate = NSPredicate(format: "pubkey = %@", pubkey)
        nrPosts = []
        req(RM.getUserMetadata(pubkey: pubkey), relayType: .SEARCH)
    }
    
    func nametagSearch(_ term:String) {
        let blockedPubkeys = blocks()
        searching = true
        contacts.nsPredicate = NSPredicate(format: "(name BEGINSWITH[cd] %@ OR fixedName BEGINSWITH[cd] %@ OR nip05 BEGINSWITH[cd] %@) AND NOT pubkey IN %@", term, term, term, blockedPubkeys)
        nrPosts = []
    }
    
    func hashtagSearch(_ term:String) {
        let blockedPubkeys = blocks()
        searching = true
        contacts.nsPredicate = NSPredicate(value: false)
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == 1 AND NOT pubkey IN %@ AND tagsSerialized CONTAINS[cd] %@", blockedPubkeys, serializedT(term))
        fr.fetchLimit = 150
        bg().perform {
            guard let results = try? bg().fetch(fr) else { return }
            let nrPosts = results.map { NRPost(event: $0) }
                .sorted(by: { $0.createdAt > $1.createdAt })
            
            Task { @MainActor in
                self.nrPosts = nrPosts
            }
        }
        
        let searchTask1 = ReqTask(prefix: "SEA-", reqCommand: { taskId in
            var tags = [term]
            if tags[0] != tags[0].lowercased() {
                tags.append(tags[0].lowercased())
            }
            
            let filters = [Filters(tagFilter: TagFilter(tag: "t", values: tags))]
            if let message = CM(type: .REQ, subscriptionId: taskId, filters: filters).json() {
                req(message, relayType: .SEARCH)
            }
        }, processResponseCommand: { taskId, _, _ in
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "kind == 1 AND NOT pubkey IN %@ AND tagsSerialized CONTAINS[cd] %@", blockedPubkeys, serializedT(term))
            fr.fetchLimit = 150
            let existingIds = self.nrPosts.map { $0.id }
            bg().perform {
                guard let results = try? bg().fetch(fr) else { return }
                let nrPosts = results
                    .filter { !existingIds.contains($0.id) }
                    .map { NRPost(event: $0) }
                
                Task { @MainActor in
                    self.nrPosts = (self.nrPosts + nrPosts)
                        .sorted(by: { $0.createdAt > $1.createdAt })
                }
            }
        })
        backlog.add(searchTask1)
        searchTask1.fetch()
    }
    
    func note1Search(_ term:String) {
        do {
            searching = true
            let key = try NIP19(displayString: term)
            contacts.nsPredicate = NSPredicate(value: false)
            
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "id = %@", key.hexString)
            fr.fetchLimit = 1
            bg().perform {
                guard let result = try? bg().fetch(fr).first else { return }
                let nrPost = NRPost(event: result)
                Task { @MainActor in
                    self.nrPosts = [nrPost]
                }
            }
            
            let searchTask1 = ReqTask(prefix: "SEA-", reqCommand: { taskId in
                req(RM.getEvent(id: key.hexString, subscriptionId: taskId), relayType: .SEARCH)
            }, processResponseCommand: { taskId, _, _ in
                let fr = Event.fetchRequest()
                fr.predicate = NSPredicate(format: "id = %@", key.hexString)
                fr.fetchLimit = 1
                bg().perform {
                    guard let result = try? bg().fetch(fr).first else { return }
                    
                    let nrPost = NRPost(event: result)
                    Task { @MainActor in
                        self.nrPosts = [nrPost]
                    }
                }
            })
            backlog.add(searchTask1)
            searchTask1.fetch()
        }
        catch {
            L.og.debug("note1 search fail \(error)")
            searching = false
        }
    }
    
    func hexIdSearch(_ term:String) {
        guard NostrRegexes.default.matchingStrings(term, regex: NostrRegexes.default.cache[.hexId]!).count == 1
        else { return }
        searching = true
        contacts.nsPredicate = NSPredicate(format: "pubkey = %@", term)
        req(RM.getUserMetadata(pubkey: term), relayType: .SEARCH)
        
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "id = %@", term)
        fr.fetchLimit = 1
        bg().perform {
            guard let result = try? bg().fetch(fr).first else { return }
            let nrPost = NRPost(event: result)
            Task { @MainActor in
                self.nrPosts = [nrPost]
            }
        }
        
        let searchTask1 = ReqTask(prefix: "SEA-", reqCommand: { taskId in
            req(RM.getEvent(id: term, subscriptionId: taskId), relayType: .SEARCH)
        }, processResponseCommand: { taskId, _, _ in
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "id = %@", term)
            fr.fetchLimit = 1
            bg().perform {
                guard let result = try? bg().fetch(fr).first else { return }
                let nrPost = NRPost(event: result)
                Task { @MainActor in
                    self.nrPosts = [nrPost]
                }
            }
        })
        backlog.add(searchTask1)
        searchTask1.fetch()
        
        Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(5.5) * NSEC_PER_SEC)
                Task { @MainActor in
                    searching = false
                }
            }
            catch { }
        }
    }
    
    func otherSearch(_ term:String) {
        let blockedPubkeys = blocks()
        searching = false
        contacts.nsPredicate = NSPredicate(format: "NOT pubkey IN %@ AND (name CONTAINS[cd] %@ OR display_name CONTAINS[cd] %@ OR fixedName CONTAINS[cd] %@ OR nip05 CONTAINS[cd] %@)", blockedPubkeys, term, term, term, term)
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "NOT pubkey IN %@ AND kind == 1 AND content CONTAINS[cd] %@ AND NOT content BEGINSWITH %@", blockedPubkeys, term, "lnbc")
        fr.fetchLimit = 150
        let existingIds = self.nrPosts.map { $0.id }
        bg().perform {
            guard let results = try? bg().fetch(fr) else { return }
            
            let nrPosts = results
                .filter { !existingIds.contains($0.id) }
                .map { NRPost(event: $0) }
            
            Task { @MainActor in
                self.nrPosts = (self.nrPosts + nrPosts)
                    .sorted(by: { $0.createdAt > $1.createdAt })
            }
        }
    }
    
    func nip05Search(_ nip05parts:Nip05Parts) {
        guard let url = nip05parts.nip05url else { return }
        Task {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            guard let nostrJson = try? JSONDecoder().decode(NostrJson.self, from: data) else { return }
            
            guard let pubkey = nostrJson.names[nip05parts.name], !pubkey.isEmpty else { return }
            
            hexIdSearch(pubkey)
        }
    }
    
    func urlSearch(_ term: String) {
        let blockedPubkeys = blocks()
        searching = true
        contacts.nsPredicate = NSPredicate(value: false)
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == 443 AND NOT pubkey IN %@ AND tagsSerialized CONTAINS[cd] %@", blockedPubkeys, serializedR(term))
        fr.fetchLimit = 150
        bg().perform {
            guard let results = try? bg().fetch(fr) else { return }
            let nrPosts = results
                .uniqued(on: { $0.fastTags.first(where: { $0.0 == "r" && $0.1 == term })?.1 ?? UUID().uuidString })
                .map { NRPost(event: $0) }
                .sorted(by: { $0.createdAt > $1.createdAt })
            
            nrPosts.forEach { x in
                L.og.info("kind443s: \(x.id) ")
            }
            
            Task { @MainActor in
                self.nrPosts = nrPosts
            }
        }
        
        let searchTask1 = ReqTask(
            timeout: 3.5,
            prefix: "SEA-",
            reqCommand: { taskId in
                var tags = [term]
                if tags[0] != tags[0].lowercased() {
                    tags.append(tags[0].lowercased())
                }
                
                let filters = [Filters(kinds:[443], tagFilter: TagFilter(tag: "r", values: tags))]
                if let message = CM(type: .REQ, subscriptionId: taskId, filters: filters).json() {
                    req(message, relayType: .SEARCH)
                }
            },
            processResponseCommand: { taskId, _, _ in
                let fr = Event.fetchRequest()
                fr.predicate = NSPredicate(format: "kind == 443 AND NOT pubkey IN %@ AND tagsSerialized CONTAINS[cd] %@", blockedPubkeys, serializedR(term))
                fr.fetchLimit = 150
                let existingUrls = self.nrPosts.compactMap { $0.fastTags.first(where: { $0.0 == "r" })?.1 }
                bg().perform {
                    guard let results = try? bg().fetch(fr) else { return }
                    let nrPosts = results
                        .filter { kind443 in
                            guard let url = kind443.fastTags.first(where: { $0.0 == "r" })?.1 else { return false }
                            return !existingUrls.contains(url)
                        }
                        .map { NRPost(event: $0) }
                    
                    Task { @MainActor in
                        self.nrPosts = (self.nrPosts + nrPosts)
                            .sorted(by: { $0.createdAt > $1.createdAt })
                    }
                }
            },
            timeoutCommand: { taskId in
                guard let account = account(), let pk = account.privateKey else { return  }
                let bgContext = bg()
                bgContext.perform {
                    var kind443 = NEvent(content: "Comments on \(term)")
                    kind443.publicKey = account.publicKey
                    kind443.kind = .custom(443)
                    kind443.tags.append(NostrTag(["r", term]))
                    
                    if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(kind443.publicKey)) {
                        kind443.tags.append(NostrTag(["client", "Nostur", NIP89_APP_REFERENCE]))
                    }
                    
                    
                    do {
                        let signedKind443 = try kind443.sign(NKeys(privateKeyHex: pk))
                        let unpublishedKind443 = Event.saveEvent(event: signedKind443, context: bgContext)
                        try? bgContext.save() 
                        let nrPost = NRPost(event: unpublishedKind443)
                        DispatchQueue.main.async {
                            self.nrPosts = [nrPost]
                        }
                    }
                    catch {
                        L.og.error("Problem signing kind 443")
                    }
                    
                }
            })
        backlog.add(searchTask1)
        searchTask1.fetch()
    }
}

func removeUriPrefix(_ term:String) -> String {
    if term.hasPrefix("nostr:") {
        return String(term.dropFirst(6))
    }
    return term
}
