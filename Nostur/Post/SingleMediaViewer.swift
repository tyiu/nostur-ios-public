//
//  SingleMediaViewer.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/03/2023.
//

import SwiftUI
import NukeUI
import Nuke

struct SingleMediaViewer: View {
    @EnvironmentObject var theme:Theme
    let url:URL
    let pubkey:String
    var height:CGFloat?
    let imageWidth:CGFloat
    var fullWidth:Bool = false
    var autoload = false
    var contentPadding:CGFloat = 0.0
    @State var imagesShown = false
    @State var loadNonHttpsAnyway = false
//    @State var actualSize:CGSize? = nil

    var body: some View {
        if url.absoluteString.prefix(7) == "http://" && !loadNonHttpsAnyway {
            VStack {
                Text("non-https media blocked", comment: "Displayed when an image in a post is blocked")
                    .frame(maxWidth: .infinity, alignment:.center)
                Button(String(localized: "Show anyway", comment: "Button to show the blocked content anyway")) {
                    imagesShown = true
                    loadNonHttpsAnyway = true
                }
            }
            .padding(10)
            .frame(maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
            .background(theme.lineColor.opacity(0.2))
        }
        else if autoload || imagesShown {
            LazyImage(request: ImageRequest(url: url,
                                            processors: [.resize(width: imageWidth, upscale: true)],
                                            userInfo: [.scaleKey: UIScreen.main.scale])) { state in
                if state.error != nil {
                    Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                        .centered()
                        .frame(maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                        .background(theme.lineColor.opacity(0.2))
                        .onAppear {
                            L.og.error("Failed to load image: \(state.error?.localizedDescription ?? "")")
                        }
                }
                else if let container = state.imageContainer, container.type ==  .gif, let data = container.data {
                    if fullWidth {
                        GIFImage(data: data)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .onTapGesture {
                                sendNotification(.fullScreenView, FullScreenItem(url: url))
                            }
                            .padding(.horizontal, -contentPadding)
//                            .transaction { transaction in
//                                transaction.animation = nil
//                            }
//                                .readSize { size in
//                                    actualSize = size
//                                }
//                                .overlay(alignment: .bottomTrailing) {
//                                    if let actualSize = actualSize {
//                                        Text("Size: \(actualSize.debugDescription)")
//                                            .background(.black)
//                                            .foregroundColor(.white)
//                                            .fontWeight(.bold)
//                                    }
//                                }
                    }
                    else {
                        GIFImage(data: data)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
//                                .readSize { size in
//                                    actualSize = size
//                                }
//                                .overlay(alignment: .bottomTrailing) {
//                                    if let actualSize = actualSize {
//                                        Text("Size: \(actualSize.debugDescription)")
//                                            .background(.black)
//                                            .foregroundColor(.white)
//                                            .fontWeight(.bold)
//                                    }
//                                }
                            .frame(minHeight: DIMENSIONS.MIN_MEDIA_ROW_HEIGHT, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                            .onTapGesture {
                                sendNotification(.fullScreenView, FullScreenItem(url: url))
                            }
//                            .transaction { transaction in
//                                transaction.animation = nil
//                            }
                    }
                }
                else if let image = state.image {
                    if fullWidth {
                        image
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
//                                    .readSize { size in
//                                        actualSize = size
//                                    }
//                                    .overlay(alignment: .bottomTrailing) {
//                                        if let actualSize = actualSize {
//                                            Text("Size: \(actualSize.debugDescription)")
//                                                .background(.black)
//                                                .foregroundColor(.white)
//                                                .fontWeight(.bold)
//                                        }
//                                    }
                            .frame(minHeight: DIMENSIONS.MIN_MEDIA_ROW_HEIGHT)
//                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, -contentPadding)
                            .onTapGesture {
                                sendNotification(.fullScreenView, FullScreenItem(url: url))
                            }
//                            .transaction { transaction in
//                                transaction.animation = nil
//                            }
                            .overlay(alignment:.topLeading) {
                                if state.isLoading { // does this conflict with showing preview images??
                                    HStack(spacing: 5) {
                                        ImageProgressView(progress: state.progress)
                                        Text("Loading...")
                                    }
                                }
                            }
                    }
                    else {
                        image
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(minHeight: DIMENSIONS.MIN_MEDIA_ROW_HEIGHT, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
//                            .fixedSize(horizontal: false, vertical: true)
                            .onTapGesture {
                                sendNotification(.fullScreenView, FullScreenItem(url: url))
                            }
//                            .transaction { transaction in
//                                transaction.animation = nil
//                            }
                            .overlay(alignment:.topLeading) {
                                if state.isLoading { // does this conflict with showing preview images??
                                    HStack(spacing: 5) {
                                        ImageProgressView(progress: state.progress)
                                        Text("Loading...")
                                    }
                                }
                            }
                    }
                }
                else if state.isLoading { // does this conflict with showing preview images??
                    HStack(spacing: 5) {
                        ImageProgressView(progress: state.progress)
                        Image(systemName: "multiply.circle.fill")
                            .padding(10)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                imagesShown = false
                            }
                    }
                    .centered()
                    .frame(maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                }
                else {
                    Color(.secondarySystemBackground)
                        .frame(maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                }
            }
            .pipeline(ImageProcessing.shared.content)
        }
        else {
            Text("Tap to load media", comment: "An image placeholder the user can tap to load media (usually an image or gif)")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(10)
                .background(theme.lineColor.opacity(0.2))
                .highPriorityGesture(
                   TapGesture()
                       .onEnded { _ in
                           imagesShown = true
                       }
                )
        }
    }
}

enum SingleMediaState {
    case initial
    case loading
    case loaded
    case error
}

struct SingleMediaViewer_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            
//            let content1 = "one image: https://nostur.com/screenshots/badges.png dunno"
//            let content1 = "one image: https://nostur.com/screenshots/lightning-invoices.png dunno"
            let content1 = "one image: https://media.tenor.com/8ZwnfDCNcUoAAAAC/doctor-dr.gif dunno"
            
            let urlsFromContent = getImgUrlsFromContent(content1)
            
            SingleMediaViewer(url:urlsFromContent[0],  pubkey: "dunno", imageWidth: UIScreen.main.bounds.width, fullWidth: false, autoload: true)
            
            Button("Clear cache") {
                ImageProcessing.shared.content.cache.removeAll()
            }
        }
        .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}


struct Gif_Previews: PreviewProvider {
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadMedia()
        }) {
            SmoothListMock {
                if let nrPost = PreviewFetcher.fetchNRPost("8d49bc0204aad2c0e8bb292b9c99b7dc1bdd6c520a877d908724c27eb5ab8ce8") {
                    Box {
                        PostRowDeletable(nrPost: nrPost)
                    }
                      
                }
                if let nrPost = PreviewFetcher.fetchNRPost("1c0ba51ba48e5228e763f72c5c936d610088959fe44535f9c861627287fe8f6d") {
                    Box {
                        PostRowDeletable(nrPost: nrPost)
                    }
                }
            }
        }
    }
}


func getGifDimensions(data: Data) -> CGSize? {
    // Create a CGImageSource with the Data
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
        return nil
    }

    // Get the properties of the first image in the animated GIF
    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        return nil
    }

    return CGSize(width: width, height: height)
}

import Combine

struct ImageProgressView: View {
    let progress: FetchImage.Progress
    @State var percent:Int = 0
    @State var subscriptions = Set<AnyCancellable>()

    var body: some View {
        ProgressView()
            .onAppear {
                progress.objectWillChange
                    .sink { _ in
                        if Int(progress.fraction * 100) % 3 == 0 {
                            if Int(ceil(progress.fraction * 100)) != percent {
                                percent = Int(ceil(progress.fraction * 100))
                            }
                        }
                    }
                    .store(in: &subscriptions)
            }
        if (percent != 0) {
            Text(percent, format: .percent)
        }
    }
}
