import SwiftUI
import AppKit
import StowlyShared

/// A small source-platform mark. Prefers a bundled brand logo (Resources/Media.xcassets →
/// "logo-instagram", etc.) when present; otherwise draws a recognizable vector glyph. Renders
/// nothing for `.web`.
///
/// - On the platform-colored open button (`onAccent`): a plain white glyph on the gradient/accent.
/// - On dark glass (cards): an app-icon-style chip — the platform color/gradient with a white glyph.
struct PlatformBadge: View {
    let platform: Platform
    var size: CGFloat = 14
    var onAccent: Bool = false

    var body: some View {
        if platform != .web {
            if let logo = Bundle.module.image(forResource: NSImage.Name(platform.logoAsset)) {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else if onAccent {
                PlatformGlyph(platform: platform, size: size, tint: .white)
            } else {
                PlatformGlyph(platform: platform, size: size * 0.74, tint: .white)
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .fill(platform.gradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(platform.accent))
                    )
            }
        }
    }
}

/// Recognizable, simplified vector mark per platform, drawn in a single tint so it reads as white
/// on a colored button or as a white knockout inside a colored chip. (Letterforms for LinkedIn
/// "in" / Handshake "h" *are* their wordmarks; the rest are simple geometric approximations.)
struct PlatformGlyph: View {
    let platform: Platform
    var size: CGFloat
    var tint: Color = .white

    var body: some View {
        Group {
            switch platform {
            case .instagram: instagram
            case .linkedin:  letters("in")
            case .handshake: letters("h")
            case .youtube:   Image(systemName: "play.rectangle.fill").font(.system(size: size * 0.82))
            case .tiktok:    Image(systemName: "music.note").font(.system(size: size * 0.84, weight: .bold))
            case .twitter:   Image(systemName: "xmark").font(.system(size: size * 0.82, weight: .heavy))
            case .web:       EmptyView()
            }
        }
        .foregroundStyle(tint)
        .frame(width: size, height: size)
    }

    private func letters(_ s: String) -> some View {
        Text(s).font(.system(size: size * 0.66, weight: .bold, design: .rounded))
    }

    /// Instagram camera: rounded-square body, lens circle, and the top-right dot.
    private var instagram: some View {
        let line = max(1, size * 0.11)
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .stroke(lineWidth: line)
                .frame(width: size * 0.84, height: size * 0.84)
            Circle()
                .stroke(lineWidth: line)
                .frame(width: size * 0.40, height: size * 0.40)
            Circle()
                .frame(width: size * 0.13, height: size * 0.13)
                .offset(x: size * 0.21, y: -size * 0.21)
        }
    }
}
