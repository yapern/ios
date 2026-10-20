import SwiftUI
import SafariServices

struct WebPage: Identifiable {
    let url: URL
    var id: URL { url }
    init(path: String) { url = URL(string: "https://yapern.com/\(path)")! }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: configuration)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
