import SwiftUI
import UIKit
import SwiftData

/// Experimental screen-capture protection for the entire app's content.
///
/// This relies on UIKit's secure text rendering implementation. Apple does
/// not publish or guarantee an API for blocking ordinary iOS screenshots.
/// Validate on a physical iPhone before enabling in a release build.
struct AppCaptureProtectedView<Content: View>: UIViewRepresentable {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> SecureContentContainer {
        SecureContentContainer(rootView: wrappedContent)
    }

    func updateUIView(_ uiView: SecureContentContainer<Content>, context: Context) {
        uiView.update(rootView: wrappedContent)
    }

    private var wrappedContent: AnyView {
        AnyView(content
            .environment(\.modelContext, modelContext)
            .environment(\.scenePhase, scenePhase)
            .environment(\.locale, locale))
    }
}

final class SecureContentContainer: UIView {
    private let secureField = UITextField(frame: .zero)
    private let hostingController: UIHostingController<AnyView>
    private let contentContainer = UIView(frame: .zero)

    init(rootView: AnyView) {
        hostingController = UIHostingController(rootView: rootView)
        super.init(frame: .zero)

        backgroundColor = .clear
        secureField.isSecureTextEntry = true
        secureField.textColor = .clear
        secureField.tintColor = .clear
        secureField.backgroundColor = .clear
        secureField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(secureField)

        NSLayoutConstraint.activate([
            secureField.leadingAnchor.constraint(equalTo: leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: trailingAnchor),
            secureField.topAnchor.constraint(equalTo: topAnchor),
            secureField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Secure text rendering is an implementation detail, not a public
        // screen-protection contract. If the secure canvas is unavailable,
        // keep the app usable rather than displaying a blank screen.
        let canvas = secureField.subviews.first {
            NSStringFromClass(type(of: $0)).contains("Canvas")
        } ?? secureField

        contentContainer.backgroundColor = .clear
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: canvas.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: canvas.bottomAnchor)
        ])

        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func update(rootView: AnyView) {
        hostingController.rootView = rootView
    }
}
