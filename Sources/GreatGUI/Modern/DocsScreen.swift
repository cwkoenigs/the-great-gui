import AppKit
import SwiftUI
import TerminalDesign
import WebKit

struct DocsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        let docs = model.docs
        Screen(palette: palette, kicker: "Knowledge base", title: "Docs") {
            if docs.url != nil {
                Button { docs.openInBrowser() } label: { Label("Open in Browser", systemImage: "arrow.up.right.square") }
                    .secondaryButton(palette)
            } else {
                Button { docs.openCanon() } label: { Label("Open Canon", systemImage: "book") }
                    .primaryButton(palette)
                    .disabled(docs.opening || docs.building)
            }
            Button { docs.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .secondaryButton(palette)
                .disabled(docs.building || docs.opening)
        } help: {
            Text("Refresh rebuilds the local knowledge base with ds-next. Use Open in Browser to read it in a separate window.")
                .font(.callout)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if docs.building || docs.opening {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(docs.building ? "Building docs…" : "Opening canon…")
                    }
                    .font(.callout)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                }
                if let note = docs.note, !note.ok {
                    NoteLine(note: note, palette: palette).padding(.horizontal, 24).padding(.vertical, 12)
                }
                if let url = docs.url {
                    DocsWebView(url: url, revision: docs.revision)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !docs.building && !docs.opening {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Canon and team skills").font(.headline)
                        Text("Browse standards, decisions, and team procedures.")
                            .foregroundStyle(palette.muted)
                    }
                    .font(.callout)
                    .padding(24)
                }
            }
        }
    }
}

private struct DocsWebView: NSViewRepresentable {
    let url: URL
    let revision: Int

    func makeCoordinator() -> Navigation { Navigation() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let navigation = context.coordinator
        if navigation.origin != url {
            navigation.origin = url
            navigation.revision = revision
            webView.load(URLRequest(url: url))
        } else if navigation.revision != revision {
            navigation.revision = revision
            if webView.url != nil {
                webView.reloadFromOrigin()
            } else {
                webView.load(URLRequest(url: url))
            }
        }
    }

    final class Navigation: NSObject, WKNavigationDelegate {
        var origin: URL?
        var revision = 0

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let origin, let url = action.request.url, url.scheme == origin.scheme,
               url.host == origin.host, url.port == origin.port {
                if action.targetFrame == nil {
                    webView.load(action.request)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
                return
            }

            if action.navigationType == .linkActivated, let url = action.request.url,
               url.scheme == "https" || url.scheme == "http" {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
