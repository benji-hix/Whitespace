import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct GrainBackground: View {
    let theme: Theme

    @State private var grainImage: NSImage?

    var body: some View {
        ZStack {
            Color(nsColor: theme.backgroundColor)
                .ignoresSafeArea()

            theme.gradientOverlay
                .ignoresSafeArea()

            if let grain = grainImage {
                Image(nsImage: grain)
                    .resizable(resizingMode: .tile)
                    .opacity(0.055)
                    .blendMode(theme.grainIsLight ? .screen : .multiply)
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
