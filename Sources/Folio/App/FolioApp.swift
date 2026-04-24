import SwiftUI
import CoreText

@main
struct FolioApp: App {
    init() {
        registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            Text("Folio")
                .frame(width: 800, height: 600)
        }
    }

    private func registerFonts() {
        let names = [
            "CrimsonPro-Light",
            "CrimsonPro-LightItalic",
            "CrimsonPro-Medium",
            "CrimsonPro-MediumItalic",
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                print("[Folio] Warning: font not found: \(name)")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
