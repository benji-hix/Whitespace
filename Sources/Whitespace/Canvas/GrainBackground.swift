import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct GrainBackground: View {
    let themeStore: ThemeStore

    @State private var grainImage: NSImage?

    private var theme: Theme { themeStore.current }
    private var previous: Theme { themeStore.previous }
    private var progress: Double { themeStore.transitionProgress }

    var body: some View {
        ZStack {
            Color(nsColor: themeStore.displayedBackgroundColor)
                .ignoresSafeArea()

            // Cross-fade gradient overlays (paper has a vignette, dark has none).
            ZStack {
                previous.gradientOverlay
                    .opacity(1 - progress)
                theme.gradientOverlay
                    .opacity(progress)
            }
            .ignoresSafeArea()

            if let grain = grainImage {
                // Cross-fade the grain blend mode by stacking two passes.
                ZStack {
                    Image(nsImage: grain)
                        .resizable(resizingMode: .tile)
                        .opacity(0.055 * (1 - progress))
                        .blendMode(previous.grainIsLight ? .screen : .multiply)
                    Image(nsImage: grain)
                        .resizable(resizingMode: .tile)
                        .opacity(0.055 * progress)
                        .blendMode(theme.grainIsLight ? .screen : .multiply)
                }
                .ignoresSafeArea()
            }
        }
        .task(id: theme) {
            grainImage = await makeGrainImage()
        }
    }

    private func makeGrainImage() async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            let size = CGSize(width: 512, height: 512)
            guard let filter = CIFilter(name: "CIRandomGenerator"),
                  let output = filter.outputImage else { return nil }
            let cropped = output.cropped(to: CGRect(origin: .zero, size: size))
            let context = CIContext()
            guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else { return nil }
            return NSImage(cgImage: cgImage, size: size)
        }.value
    }
}
