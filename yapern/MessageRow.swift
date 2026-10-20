import SwiftUI

struct MessageRow: View {
    let message: Message
    let store: FeedStore

    private var boardName: String {
        if let board = store.board(for: message) { return "y/\(board.slug)" }
        return "Yapern"
    }

    private var authorName: String {
        let name = store.authorName(for: message.userID)
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Someone" : name
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: message.createdAt, relativeTo: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(boardName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeedStyle.accent)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(authorName)
                        .font(.subheadline)
                        .foregroundStyle(FeedStyle.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(relativeDate)
                        .font(.caption)
                        .foregroundStyle(FeedStyle.muted)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityLabel("Posted \(message.createdAt.formatted(date: .long, time: .shortened))")
                }
            }

            NavigationLink(value: message) {
                Text(message.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled message" : message.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(FeedStyle.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("feed.message.\(message.id)")

            MessageBodyView(messageBody: message.body, navigationMessage: message)

            HStack {
                Spacer()
                if let url = store.messageURL(for: message) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .foregroundStyle(FeedStyle.muted)
                            .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("feed.share.\(message.id)")
                    .accessibilityLabel("Share message")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}
