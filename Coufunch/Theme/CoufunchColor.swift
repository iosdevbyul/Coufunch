import SwiftUI
import WakTrainerDesignSystem

/// App-local adaptive surfaces keep the shared design system unchanged.
enum CoufunchColor {
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 11.0/255.0, green: 14.0/255.0, blue: 17.0/255.0, alpha: 1)
            : .white
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 23.0/255.0, green: 27.0/255.0, blue: 32.0/255.0, alpha: 1)
            : UIColor(red: 246.0/255.0, green: 247.0/255.0, blue: 249.0/255.0, alpha: 1)
    })
    static let textPrimary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 247.0/255.0, green: 248.0/255.0, blue: 249.0/255.0, alpha: 1)
            : UIColor(red: 22.0/255.0, green: 26.0/255.0, blue: 31.0/255.0, alpha: 1)
    })
    static let primary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 140.0/255.0, green: 246.0/255.0, blue: 108.0/255.0, alpha: 1)
            : UIColor(red: 35.0/255.0, green: 123.0/255.0, blue: 44.0/255.0, alpha: 1)
    })
}

struct CoufunchCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(WakSpacing.regular)
            .background(CoufunchColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: WakRadius.card,
                                        style: .continuous))
    }
}
