import SwiftUI
import WakTrainerDesignSystem

/// App-local adaptive surfaces keep the shared design system unchanged.
enum CoufunchColor {
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 11/255, green: 14/255, blue: 17/255, alpha: 1)
            : .white
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 23/255, green: 27/255, blue: 32/255, alpha: 1)
            : UIColor(red: 246/255, green: 247/255, blue: 249/255, alpha: 1)
    })
    static let textPrimary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 247/255, green: 248/255, blue: 249/255, alpha: 1)
            : UIColor(red: 22/255, green: 26/255, blue: 31/255, alpha: 1)
    })
    static let primary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 140/255, green: 246/255, blue: 108/255, alpha: 1)
            : UIColor(red: 35/255, green: 123/255, blue: 44/255, alpha: 1)
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
