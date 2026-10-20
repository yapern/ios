import SwiftUI

struct MessageBodyView: View {
    let messageBody: String
    var navigationMessage: Message? = nil

    private enum Block {
        case text([MessageContent.Part])
        case image(MessageContent.Part)
        case video(MessageContent.Part)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var textParts: [MessageContent.Part] = []

        func flushText() {
            if !textParts.isEmpty {
                result.append(.text(textParts))
                textParts.removeAll(keepingCapacity: true)
            }
        }

        for part in MessageContent.parse(messageBody) {
            if part.imageURL != nil {
                flushText()
                result.append(.image(part))
            } else if part.youtubeVideoID != nil {
                flushText()
                result.append(.video(part))
            } else {
                textParts.append(part)
            }
        }
        flushText()
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let parts):
                    Text(attributedText(from: parts))
                        .font(.body)
                        .foregroundStyle(FeedStyle.text)
                        .tint(FeedStyle.accent)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                case .image(let part):
                    if let url = part.imageURL {
                        image(url: url, label: part.text)
                    }
                case .video(let part):
                    if let videoID = part.youtubeVideoID,
                       let videoURL = part.url ?? URL(string: "https://www.youtube.com/watch?v=\(videoID)") {
                        Link(destination: MessageContent.externalLinkURL(videoURL)) {
                            videoPreview(videoID: videoID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play YouTube video")
                    }
                }
            }
        }
    }

    private func attributedText(from parts: [MessageContent.Part]) -> AttributedString {
        var result = AttributedString()
        for part in parts {
            var fragment = AttributedString(part.text)
            if let url = part.url {
                fragment.link = MessageContent.externalLinkURL(url)
            }
            result.append(fragment)
        }
        return result
    }

    @ViewBuilder
    private func image(url: URL, label: String) -> some View {
        let imageView = GeometryReader { proxy in
            ZStack {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .accessibilityLabel(label.isEmpty ? "Attached image" : label)
                    case .failure:
                        mediaPlaceholder(symbol: "photo", title: "Image unavailable")
                    case .empty:
                        mediaPlaceholder(symbol: "photo", title: "Loading image")
                    @unknown default:
                        mediaPlaceholder(symbol: "photo", title: "Image unavailable")
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxHeight: 320)

        if let navigationMessage {
            NavigationLink(value: navigationMessage) { imageView }
                .buttonStyle(.plain)
                .accessibilityLabel("Open attached image in message detail")
        } else {
            Link(destination: MessageContent.externalLinkURL(url)) { imageView }
                .buttonStyle(.plain)
                .accessibilityLabel("Open original image")
        }
    }

    private func videoPreview(videoID: String) -> some View {
        let thumbnailURL = URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
        return ZStack {
            AsyncImage(url: thumbnailURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FeedStyle.skeleton
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.035))
            Image(systemName: "play.circle.fill")
                .font(.system(size: 52))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.62))
                .shadow(color: .black.opacity(0.25), radius: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxHeight: 260)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("YouTube video preview")
    }

    private func mediaPlaceholder(symbol: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.subheadline)
        .foregroundStyle(FeedStyle.muted)
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}
