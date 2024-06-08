//
//  NewPostModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/06/2023.
//

import Foundation
import SwiftUI
import Combine
import NostrEssentials

public final class TypingTextModel: ObservableObject {
    var draft: String {
        get { NRState.shared.draft  }
        set { 
            DispatchQueue.main.async {
                NRState.shared.draft = newValue
            }
        }
    }
    
    var restoreDraft: String {
        get { NRState.shared.restoreDraft  }
        set { 
            DispatchQueue.main.async {
                NRState.shared.restoreDraft = newValue
            }
        }
    }
    
    @Published var text: String = "" {
        didSet {
            draft = text
        }
    }
    @Published var pastedImages:[PostedImageMeta] = []
    @Published var selectedMentions:Set<Contact> = [] // will become p-tags in the final post
    @Published var unselectedMentions:Set<Contact> = [] // unselected from reply-p's, but maybe mentioned as nostr:npub, so should not be put back in p
    @Published var sending = false
    @Published var uploading = false
    private var subscriptions = Set<AnyCancellable>()
    
    init() {
        if !draft.isEmpty { // Restore after Cancel
            let isMentionPrefix = draft.hasPrefix("@") && draft.count < 20
            if !isMentionPrefix {
                text = draft
            }
        }
        restoreDraft = ""
    }
}

public final class NewPostModel: ObservableObject {
    @AppStorage("nip96_api_url") private var nip96apiUrl = ""
    @ObservedObject public var uploader = Nip96Uploader()
    
    public var typingTextModel = TypingTextModel()
    private var mentioning = false
    @Published var showMentioning = false // To reduce rerendering, use this flag instead of (vm.mentioning && !vm.filteredContactSearchResults.isEmpty)
    private var term: String = ""
    var nEvent:NEvent?
    var lastHit:String = "NOHIT"
    var textView:SystemTextView?
    
    @Published var uploadError:String?
    var requiredP:String? = nil
    @Published var availableContacts:Set<Contact> = [] // are available to toggle on/off for notifications
    
    @Published var previewNRPost:NRPost?
    @Published var gifSheetShown = false
    
    @Published var contactSearchResults:[Contact] = []
    @Published var activeAccount:CloudAccount? = nil
    
    private var subscriptions = Set<AnyCancellable>()
    
    public init(dueTime: TimeInterval = 0.2) {
        self.typingTextModel.$text
            .removeDuplicates()
            .debounce(for: .seconds(dueTime), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                self?.textChanged(value)
            })
            .store(in: &subscriptions)
    }
    
    var filteredContactSearchResults:[Contact] {
        let wot = WebOfTrust.shared
        if WOT_FILTER_ENABLED() {
            return contactSearchResults
                // WoT enabled, so put in-WoT before non-WoT
                .sorted(by: { wot.isAllowed($0.pubkey) && !wot.isAllowed($1.pubkey) })
                // Put following before non-following
                .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
        }
        else {
            // WoT disabled, just following before non-following
            return contactSearchResults
                .sorted(by: { isFollowing($0.pubkey) && !isFollowing($1.pubkey) })
        }
    }
    
    static let rules: [HighlightRule] = [
        HighlightRule(pattern: NewPostModel.mentionRegex, formattingRules: [
            TextFormattingRule(key: .foregroundColor, value: UIColor(Themes.default.theme.accent)),
            TextFormattingRule(fontTraits: .traitBold)
        ]),
        HighlightRule(pattern: NewPostModel.typingRegex, formattingRules: [
            TextFormattingRule(key: .foregroundColor, value: UIColor(Themes.default.theme.accent)),
            TextFormattingRule(fontTraits: .traitBold)
        ])
    ]
    static let typingRegex = try! NSRegularExpression(pattern: "((?:^|\\s)@\\x{2063}\\x{2064}[^\\x{2063}\\x{2064}]+\\x{2064}\\x{2063}|(?<![/\\?])#)", options: [])
    static let mentionRegex = try! NSRegularExpression(pattern: "((?:^|\\s)@\\w+|(?<![/\\?])#\\S+)", options: [])
    
    public func sendNow(replyTo:Event? = nil, quotingEvent:Event? = nil, onDismiss: @escaping () -> Void) {
        if (!typingTextModel.pastedImages.isEmpty) {
            typingTextModel.uploading = true
            
            if !nip96apiUrl.isEmpty { // new nip96 media services
                guard let nip96apiURL = URL(string: nip96apiUrl) else {
                    sendNotification(.anyStatus, ("Problem with Custom File Storage Server", "NewPost"))
                    return
                }
                guard let pk = activeAccount?.privateKey, let keys = try? Keys(privateKeyHex: pk) else {
                    sendNotification(.anyStatus, ("Problem with account", "NewPost"))
                    return
                }
                
                let maxWidth:CGFloat = 2800.0
                let mediaRequestBags = typingTextModel.pastedImages
                    .compactMap { imageMeta in // Resize images
                        let scale = imageMeta.imageData.size.width > maxWidth ? imageMeta.imageData.size.width / maxWidth : 1
                        let size = CGSize(width: imageMeta.imageData.size.width / scale, height: imageMeta.imageData.size.height / scale)
                        
                        let format = UIGraphicsImageRendererFormat()
                        format.scale = 1 // 1x scale, for 2x use 2, and so on
                        let renderer = UIGraphicsImageRenderer(size: size, format: format)
                        let scaledImage = renderer.image { _ in
                            imageMeta.imageData.draw(in: CGRect(origin: .zero, size: size))
                        }
                        
                        if let imageData = scaledImage.jpegData(compressionQuality: 0.85) {
                            return (imageData, PostedImageMeta.ImageType.jpeg, imageMeta.index)
                        }
                        return nil
                    }
                    .map { (resizedImage, type, index) in
                        MediaRequestBag(apiUrl: nip96apiURL, filename: type == PostedImageMeta.ImageType.png ? "media.png" : "media.jpg", mediaData: resizedImage, index: index)
                    }
                
                uploader.queued = mediaRequestBags
                uploader.onFinish = {
                    let imetas:[Nostur.Imeta] = mediaRequestBags
                        .compactMap {
                            guard let url = $0.downloadUrl else { return nil }
                            return Imeta(url: url, dim: $0.dim, hash: $0.sha256)
                        }
                    self._sendNow(imetas: imetas, replyTo: replyTo, quotingEvent: quotingEvent, onDismiss: onDismiss)
                }
                uploader.uploadingPublishers(for: mediaRequestBags, keys: keys)
                    .receive(on: RunLoop.main)
                    .sink(receiveCompletion: { result in
                        switch result {
                        case .failure(let error as URLError) where error.code == .userAuthenticationRequired:
                            L.og.error("Error uploading images (401): \(error.localizedDescription)")
                            self.uploadError = "Media upload authorization error"
                            sendNotification(.anyStatus, ("Media upload authorization error", "NewPost"))
                        case .failure(let error):
                            L.og.error("Error uploading images: \(error.localizedDescription)")
                            self.uploadError = "Image upload error"
                            sendNotification(.anyStatus, ("Upload error: \(error.localizedDescription)", "NewPost"))
                        case .finished:
                            L.og.debug("All images uploaded successfully")
                        }
                    }, receiveValue: { mediaRequestBags in
                        for mediaRequestBag in mediaRequestBags {
                            self.uploader.processResponse(mediaRequestBag: mediaRequestBag)
                        }
//                        if (self.uploader.finished) {
//                            let imetas:[Imeta] = mediaRequestBags.compactMap {
//                                guard let url = $0.downloadUrl else { return nil }
//                                return Imeta(url: url, dim: $0.dim, hash: $0.sha256hex)
//                            }
//                            self._sendNow(imetas: imetas, replyTo: replyTo, quotingEvent: quotingEvent, dismiss: dismiss)
//                        }
                    })
                    .store(in: &subscriptions)
            }
            else { // old media upload services
                uploadImages(images: typingTextModel.pastedImages)
                    .receive(on: RunLoop.main)
                    .sink(receiveCompletion: { result in
                        switch result {
                        case .failure(let error):
                            L.og.error("Error uploading images: \(error.localizedDescription)")
                            self.uploadError = "Image upload error"
                            sendNotification(.anyStatus, ("Upload error: \(error.localizedDescription)", "NewPost"))
                        case .finished:
                            L.og.debug("All images uploaded successfully")
                        }
                    }, receiveValue: { urls in
                        if (self.typingTextModel.pastedImages.count == urls.count) {
                            let imetas = urls.map { Imeta(url: $0) }
                            self._sendNow(imetas: imetas, replyTo: replyTo, quotingEvent: quotingEvent, onDismiss: onDismiss)
                        }
                    })
                    .store(in: &subscriptions)
            }
        }
        else {
            self._sendNow(imetas: [], replyTo: replyTo, quotingEvent: quotingEvent, onDismiss: onDismiss)
        }
    }
    
    // TODO: NOTE: When updating this func, also update HighlightComposer.send or refactor.
    private func _sendNow(imetas: [Imeta], replyTo: Event? = nil, quotingEvent: Event? = nil, onDismiss: @escaping () -> Void) {
        guard let account = activeAccount else { return }
        account.lastLoginAt = .now
        guard isFullAccount(account) else { showReadOnlyMessage(); return }
        let publicKey = account.publicKey
        var nEvent = nEvent ?? NEvent(content: "")
        nEvent.publicKey = publicKey
        var pTags:[String] = []
        nEvent.createdAt = NTimestamp.init(date: Date())
        
        if !imetas.isEmpty {
            // send message with images
            for imeta in imetas {
                nEvent.content += "\n\(imeta.url)"
                
                var imetaParts:[String] = ["imeta", "url \(imeta.url)"]
                if let dim = imeta.dim {
                    imetaParts.append("dim \(dim)")
                }
                if let hash = imeta.hash {
                    imetaParts.append("sha256 \(hash)")
                }

                nEvent.tags.append(NostrTag(imetaParts))
            }
        }
        // Typed @mentions to nostr:npub
        if #available(iOS 16.0, *) {
            nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected: typingTextModel.selectedMentions)
        }
        else {
            nEvent.content = replaceMentionsWithNpubs15(nEvent.content, selected: typingTextModel.selectedMentions)
        }
        
        // Pasted @npubs to nostr:npub and return pTags
        let (content, atNpubs) = replaceAtWithNostr(nEvent.content)
        nEvent.content = content
        let atPtags = atNpubs.compactMap { Keys.hex(npub: $0) }
        
        // Scan for any nostr:npub and return pTags
        let npubs = getNostrNpubs(nEvent.content)
        let nostrNpubTags = npubs.compactMap { Keys.hex(npub: $0) }
        
        // Scan for any nostr:note1 or nevent1 and return q tags
        let qTags = Set(getQuoteTags(nEvent.content))
        
        // #hashtags to .t tags
        nEvent = putHashtagsInTags(nEvent)

        // Include .p tags for @mentions (should no longer be needed, because we get them nostr:npubs in text now)
        let selectedPtags = typingTextModel.selectedMentions.map { $0.pubkey }
        var unselectedPtags = typingTextModel.unselectedMentions.map { $0.pubkey }
        
        // always include the .p of pubkey we are replying to (not required by spec, but more healthy for nostr)
        if let requiredP = requiredP {
            pTags.append(requiredP)
            unselectedPtags.removeAll(where: { $0 == requiredP })
        }
        
        // Merge and deduplicate all p pubkeys, remove all unselected p pubkeys and turn into NostrTag
        let nostrTags = Set(pTags + selectedPtags + atPtags + nostrNpubTags)
            .subtracting(Set(unselectedPtags))
            .map { NostrTag(["p", $0]) }
        
        nEvent.tags.append(contentsOf: nostrTags)
        
        // If we are quote reposting, include the quoted post as nostr:note1 at the end
        // TODO: maybe at .q tag, need to look up if there is a spec
        if let quotingEvent {
            if let note1id = note1(quotingEvent.id) {
                nEvent.content = (nEvent.content + "\nnostr:" + note1id)
            }
            nEvent.tags.insert(NostrTag(["q", quotingEvent.id]), at: 0) // TODO: Add relay hint
            
            if !nEvent.pTags().contains(quotingEvent.pubkey) {
                nEvent.tags.append(NostrTag(["p", quotingEvent.pubkey]))
            }
        }
        
        qTags.forEach { qTag in
            nEvent.tags.append(NostrTag(["q", qTag]))
        }
        
        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            nEvent.content = replaceNsecWithHunter2(nEvent.content)
        }
        
        if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(nEvent.publicKey)) {
            nEvent.tags.append(NostrTag(["client", "Nostur", NIP89_APP_REFERENCE]))
        }

        // Need draft here because it might be cleared before we need it because async later
        self.typingTextModel.restoreDraft = self.typingTextModel.draft
        
        let cancellationId = UUID()
        if account.isNC {
            nEvent = nEvent.withId()
            
            // Save unsigned event:
            let bgContext = bg()
            bgContext.perform {
                let savedEvent = Event.saveEvent(event: nEvent, flags: "nsecbunker_unsigned", context: bgContext)
                savedEvent.cancellationId = cancellationId
                DispatchQueue.main.async {
                    sendNotification(.newPostSaved, savedEvent)
                }
                DataProvider.shared().bgSave()
                
                DispatchQueue.main.async {
                    NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account, whenSigned: { signedEvent in
                        bg().perform {
                            savedEvent.sig = signedEvent.signature
                            savedEvent.flags = "awaiting_send"
                            savedEvent.cancellationId = cancellationId
//                            savedEvent.updateNRPost.send(savedEvent)
                            ViewUpdates.shared.updateNRPost.send(savedEvent)
                            DispatchQueue.main.async {
                                _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId)
                            }
                        }
                    })
                }
            }
        }
        else if let signedEvent = try? account.signEvent(nEvent) {
            let bgContext = bg()
            bgContext.perform {
                let savedEvent = Event.saveEvent(event: signedEvent, flags: "awaiting_send", context: bgContext)
                savedEvent.cancellationId = cancellationId
                // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                if nEvent.kind == .reaction {
                    do {
                        try Event.updateReactionTo(savedEvent, context: bg()) // TODO: Revert this on 'undo'
                    } catch {
                        L.og.error("🦋🦋🔴🔴🔴 problem updating Like relation .id \(nEvent.id)")
                    }
                }
                
                DataProvider.shared().bgSave()
                if ([1,6,9802,30023,34235].contains(savedEvent.kind)) {
                    DispatchQueue.main.async {
                        sendNotification(.newPostSaved, savedEvent)
                    }
                }
            }
            _ = Unpublisher.shared.publish(signedEvent, cancellationId: cancellationId)
        }
        
        if let replyTo {
            bg().perform {
                let replyToNEvent = replyTo.toNEvent()
                let replyToId = replyTo.id
                DispatchQueue.main.async {
                    sendNotification(.postAction, PostActionNotification(type: .replied, eventId: replyToId))
                    // Republish post being replied to
                    Unpublisher.shared.publishNow(replyToNEvent)
                }
            }
        }
        if let quotingEvent {
            let quotingNEvent = quotingEvent.toNEvent()
            let quotingEventId = quotingEvent.id
            bg().perform {
                DispatchQueue.main.async {
                    sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: quotingEventId))
                    // Republish post being quoted
                    Unpublisher.shared.publishNow(quotingNEvent)
                }
            }
        }
        onDismiss()
        sendNotification(.didSend)
    }
    
    public func showPreview(quotingEvent:Event? = nil) {
        guard let account = activeAccount else { return }
        var nEvent = nEvent ?? NEvent(content: "")
        var pTags:[String] = []
        nEvent.publicKey = account.publicKey
        
        // @mentions to nostr:npub
        if #available(iOS 16.0, *) {
            nEvent.content = replaceMentionsWithNpubs(nEvent.content, selected: typingTextModel.selectedMentions)
        }
        else {
            nEvent.content = replaceMentionsWithNpubs15(nEvent.content, selected: typingTextModel.selectedMentions)
        }
        
        // @npubs to nostr:npub and return pTags
        let (content, atNpubs) = replaceAtWithNostr(nEvent.content)
        nEvent.content = content
        let atPtags = atNpubs.compactMap { Keys.hex(npub: $0) }
        
        // Scan for any nostr:npub and return pTags
        let npubs = getNostrNpubs(nEvent.content)
        let nostrNpubTags = npubs.compactMap { Keys.hex(npub: $0) }

        // #hashtags to .t tags
        nEvent = putHashtagsInTags(nEvent)
        
        // Include .p tags for @mentions (should no longer be needed, because we get them nostr:npubs in text now)
        let selectedPtags = typingTextModel.selectedMentions.map { $0.pubkey }
        var unselectedPtags = typingTextModel.unselectedMentions.map { $0.pubkey }
        
        // always include the .p of pubkey we are replying to (not required by spec, but more healthy for nostr)
        if let requiredP = requiredP {
            pTags.append(requiredP)
            unselectedPtags.removeAll(where: { $0 == requiredP })
        }
        
        // Merge and deduplicate all p pubkeys, remove all unselected p pubkeys and turn into NostrTag
        let nostrTags = Set(pTags + selectedPtags + atPtags + nostrNpubTags)
            .subtracting(Set(unselectedPtags))
            .map { NostrTag(["p", $0]) }
        
        nEvent.tags.append(contentsOf: nostrTags)
        
        // If we are quote reposting, include the quoted post as nostr:note1 at the end
        // TODO: maybe at .q tag, need to look up if there is a spec
        if let quotingEvent {
            if let note1id = note1(quotingEvent.id) {
                nEvent.content = (nEvent.content + "\nnostr:" + note1id)
            }
            nEvent.tags.insert(NostrTag(["q", quotingEvent.id]), at: 0) // TODO: Add relay hint
            
            if !nEvent.pTags().contains(quotingEvent.pubkey) { 
                nEvent.tags.append(NostrTag(["p", quotingEvent.pubkey]))
            }
        }

        if (SettingsStore.shared.replaceNsecWithHunter2Enabled) {
            nEvent.content = replaceNsecWithHunter2(nEvent.content)
        }
        
        for index in typingTextModel.pastedImages.indices {
            nEvent.content = nEvent.content + "\n--@!^@\(index)@^!@--"
        }
        
        if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(nEvent.publicKey)) {
            nEvent.tags.append(NostrTag(["client", "Nostur", NIP89_APP_REFERENCE]))
        }
    
        
        bg().perform { [weak self] in
            guard let self else { return }
            let previewEvent = createPreviewEvent(nEvent)
            if (!self.typingTextModel.pastedImages.isEmpty) {
                previewEvent.previewImages = self.typingTextModel.pastedImages
            }
            let nrPost = NRPost(event: previewEvent, withFooter: false, isScreenshot: true, isPreview: true)
            DispatchQueue.main.async { [weak self] in
                self?.previewNRPost = nrPost
            }
            bg().delete(previewEvent)
        }
    }
    
    public func selectContactSearchResult(_ contact:Contact) {
        guard textView != nil else { return }
        let mentionName = contact.handle
        typingTextModel.text = "\(typingTextModel.text.dropLast(term.count))\u{2063}\u{2064}\(mentionName)\u{2064}\u{2063} "
        availableContacts.insert(contact)
        typingTextModel.selectedMentions.insert(contact)
        mentioning = false
        lastHit = mentionName
        term = ""
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // after 0.3 sec to get the new .endOfDocument
            let newPosition = self.textView!.endOfDocument
            self.textView!.selectedTextRange = self.textView!.textRange(from: newPosition, to: newPosition)
        }
    }
    
    public func textChanged(_ newText:String) {
        if (nEvent == nil) {
            nEvent = NEvent(content: newText)
        } else {
            nEvent!.content = newText
        }
        
        if let mentionTerm = mentionTerm(newText) {
            if mentionTerm == lastHit {
                mentioning = false
            }
            else {
                mentioning = true
                term = mentionTerm
                self.searchContacts(mentionTerm)
            }
            
        }
        else {
            if mentioning {
                mentioning = false
            }
        }
        
        let showMentioning = mentioning && !filteredContactSearchResults.isEmpty
        if showMentioning != self.showMentioning { // check first to reduce rerendering
            self.showMentioning = showMentioning
        }
    }
    
    private func searchContacts(_ mentionTerm:String) {
        let fr = Contact.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.nip05verifiedAt, ascending: false)]
        fr.predicate = NSPredicate(format: "(display_name CONTAINS[cd] %@ OR name CONTAINS[cd] %@) AND NOT pubkey IN %@", mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), mentionTerm.trimmingCharacters(in: .whitespacesAndNewlines), NRState.shared.blockedPubkeys)
        
        let contactSearchResults = Array(((try? DataProvider.shared().viewContext.fetch(fr)) ?? []).prefix(60))
        
        // check first to reduce rerendering, if both are already empty, don't re-set it.
        if self.contactSearchResults.isEmpty && contactSearchResults.isEmpty {
            return
        }
        self.contactSearchResults = contactSearchResults
    }
    
    public func loadQuotingEvent(_ quotingEvent:Event) {
        var newQuoteRepost = NEvent(content: typingTextModel.text)
        newQuoteRepost.kind = .textNote
        nEvent = newQuoteRepost
    }
    
    public func loadReplyTo(_ replyTo:Event) {
        var newReply = NEvent(content: typingTextModel.text)
        newReply.kind = .textNote
        guard let replyTo = replyTo.toMain() else {
            L.og.error("🔴🔴 Problem getting event from viewContext")
            return
        }
        let existingPtags = TagsHelpers(replyTo.tags()).pTags()
        let availableContacts = Set(Contact.fetchByPubkeys(existingPtags.map { $0.pubkey }, context: DataProvider.shared().viewContext))
        requiredP = replyTo.contact?.pubkey
        self.availableContacts = Set([replyTo.contact].compactMap { $0 } + availableContacts)
        typingTextModel.selectedMentions = Set([replyTo.contact].compactMap { $0 } + availableContacts)
        
        let root = TagsHelpers(replyTo.tags()).replyToRootEtag()
        
        if (root != nil) { // ADD "ROOT" + "REPLY"
            let newRootTag = NostrTag(["e", root!.tag[1], "", "root"]) // TODO RECOMMENDED RELAY HERE
            newReply.tags.append(newRootTag)
            
            let newReplyTag = NostrTag(["e", replyTo.id, "", "reply"])
            
            newReply.tags.append(newReplyTag)
        }
        else { // ADD ONLY "ROOT"
            let newRootTag = NostrTag(["e", replyTo.id, "", "root"])
            newReply.tags.append(newRootTag)
        }
        
        let rootA = replyTo.toNEvent().replyToRootAtag()
        
        if (rootA != nil) { // ADD EXISTING "ROOT" (aTag) FROM REPLYTO
            let newRootATag = NostrTag(["a", rootA!.tag[1], "", "root"]) // TODO RECOMMENDED RELAY HERE
            newReply.tags.append(newRootATag)
        }
        else if replyTo.kind == 30023 { // ADD ONLY "ROOT" (aTag) (DIRECT REPLY TO ARTICLE)
            let newRootTag = NostrTag(["a", replyTo.aTag, "", "root"]) // TODO RECOMMENDED RELAY HERE
            newReply.tags.append(newRootTag)
        }

        nEvent = newReply
    }
    
    public func directMention(_ contact:Contact) {
        guard textView != nil else { return }
        let mentionName = contact.handle
        typingTextModel.text = "@\u{2063}\u{2064}\(mentionName)\u{2064}\u{2063} "
        availableContacts.insert(contact)
        typingTextModel.selectedMentions.insert(contact)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // after 0.3 sec to get the new .endOfDocument
            let newPosition = self.textView!.endOfDocument
            self.textView!.selectedTextRange = self.textView!.textRange(from: newPosition, to: newPosition)
        }
    }
}

func mentionTerm(_ text:String) -> String? {
    if let rangeStart = text.lastIndex(of: Character("@")) {
        let extractedString = String(text[rangeStart..<text.endIndex].dropFirst(1))
        return extractedString
    }
    return nil
}

struct Imeta {
    let url:String
    var dim:String?
    var hash:String?
}
