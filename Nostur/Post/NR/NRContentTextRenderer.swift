//
//  NRContentTextRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/05/2023.
//

import SwiftUI

struct NRContentTextRenderer: View {
    public let attributedStringWithPs:AttributedStringWithPs
    public var isDetail = false
    public var isPreview = false
    @State var text:AttributedString? = nil
    
    var body: some View {
        Group {
            if isPreview {
                Text(text ?? attributedStringWithPs.output)
                    .lineSpacing(3)
                    .lineLimit(isDetail ? 3000 : 20)
                    .fixedSize(horizontal: false, vertical: true) // <-- Needed or text gets truncated in VStack
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            else {
                NRText(text ?? attributedStringWithPs.output)
                    .id(text ?? attributedStringWithPs.output)
            }
        }
        .onReceive(
            Importer.shared.contactSaved
                .filter { pubkey in
                    guard !attributedStringWithPs.input.isEmpty else { return false }
                    guard !attributedStringWithPs.pTags.isEmpty else { return false }
                    return self.attributedStringWithPs.pTags.contains(pubkey)
                }
                .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
        ) { pubkey in
            
            bg().perform {
                let reparsed = NRTextParser.shared.parseText(attributedStringWithPs.event, text: attributedStringWithPs.input)
                if self.text != reparsed.output {
                    L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.output)")
                    DispatchQueue.main.async {
                        self.text = reparsed.output
                    }
                }
            }
        }
        //            .transaction { t in
        //                t.animation = nil
        //            }
    }
}
