import SwiftUI
import SwiftData
import UIKit

/// Experimental app-wide screenshot protection.
///
/// Secure-text rendering is not an Apple-supported API for shielding arbitrary
/// views. It may change between iOS releases; verify on a physical iPhone.
struct AppCaptureProtectedView<Content: View>: UIViewControllerRepresentable {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> SecureContentViewController {
        SecureContentViewController(rootView: wrappedContent)
    }

    func updateUIViewController(_ controller: SecureContentViewController, context: Context) {
        controller.update(rootView: wrappedContent)
    }

    private var wrappedContent: AnyView {
        AnyView(
            content
                .environment(\.modelContext, modelContext)
                .environment(\.scenePhase, scenePhase)
                .environment(\.locale, locale)
                .environment(\.colorScheme, colorScheme)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
                .environment(\.layoutDirection, layoutDirection)
        )
    }
}

/// A full-size UIKit controller preserves the host window's dimensions and
/// safe-area handling for SwiftUI navigation, sheets, and keyboard behavior.
@MainActor
final class SecureContentViewController: UIViewController {
    private let secureField = UITextField(frame: .zero)
    private let hostingController: UIHostingController<AnyView>

    init(rootView: AnyView) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // This background remains visible to the screenshot compositor when
        // the protected canvas is omitted from the captured image.
        view.backgroundColor = .black
        secureField.isSecureTextEntry = true
        secureField.backgroundColor = .clear
        secureField.textColor = .clear
        secureField.tintColor = .clear

        // The UIKit text canvas normally has text-field-sized bounds. Move it
        // into the full-size controller and pin it to every edge instead of
        // constraining the SwiftUI hierarchy to the field's internal layout.
        let secureCanvas = secureField.subviews.first {
            NSStringFromClass(type(of: $0)).contains("Canvas")
        }

        let surface: UIView
        if let secureCanvas {
            secureCanvas.removeFromSuperview()
            surface = secureCanvas
        } else {
            // Never silently claim screenshot protection when UIKit changes.
            NSLog("[Coufunch] Secure text canvas unavailable; screenshot protection is inactive.")
            surface = UIView(frame: .zero)
        }

        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.backgroundColor = .clear
        surface.isUserInteractionEnabled = true
        view.addSubview(surface)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Proper view-controller containment is needed for NavigationStack,
        // sheet presentation, safe-area insets, and SwiftUI layout updates.
        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: surface.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    func update(rootView: AnyView) {
        hostingController.rootView = rootView
    }
}
