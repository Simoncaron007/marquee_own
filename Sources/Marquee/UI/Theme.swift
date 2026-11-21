import AppKit
import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.058, blue: 0.068)
    static let elevated = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.08)
    static let accent = Color(red: 0.98, green: 0.74, blue: 0.27)
    static let secondary = Color.white.opacity(0.66)
    static let tertiary = Color.white.opacity(0.42)
    static let posterWidth: CGFloat = 156
    static let gutter: CGFloat = 40
    static let topBarHeight: CGFloat = 52
}

extension Text {
    func sectionTitle() -> some View {
        self.font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(prominent ? Theme.accent : Color.white.opacity(0.13), in: Capsule())
            .foregroundStyle(prominent ? Color.black : Color.white)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Lets the window be dragged (and double-click-zoomed) from the custom top bar.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// TMDB artwork that fills whatever frame it's given.
struct TMDBImage: View {
    let path: String?
    var size = "w500"
    var placeholderSymbol: String?
    @State private var loaded: NSImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image = loaded ?? path.flatMap({ ImageLoader.shared.cached(path: $0, size: size) }) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Theme.elevated
                        if let placeholderSymbol {
                            Image(systemName: placeholderSymbol)
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.tertiary)
                        }
                    }
                }
            }
            .clipped()
            .task(id: path.map { size + $0 }) {
                loaded = nil
                guard let path else { return }
                loaded = await ImageLoader.shared.image(path: path, size: size)
            }
    }
}

/// Poster, or a typographic stand-in when there's no artwork (unidentified titles).
struct PosterArtwork: View {
    let path: String?
    let title: String

    var body: some View {
        if path != nil {
            TMDBImage(path: path, size: "w500")
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondary)
                    .padding(14)
            }
        }
    }
}
