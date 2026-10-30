import SwiftUI
import UIKit
import XCTest
@testable import Coufunch

@MainActor
final class AppCaptureProtectedViewTests: XCTestCase {
    func testSecureSurfaceAndHostedContentFillPortraitWindowSizes() throws {
        let controller = SecureContentViewController(rootView: AnyView(Color.white))
        controller.loadViewIfNeeded()

        let hostingView = try XCTUnwrap(controller.children.first?.view)
        let surface = try XCTUnwrap(hostingView.superview)

        for size in [
            CGSize(width: 375, height: 667),
            CGSize(width: 393, height: 852),
            CGSize(width: 430, height: 932)
        ] {
            controller.view.frame = CGRect(origin: .zero, size: size)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            XCTAssertEqual(surface.frame, controller.view.bounds)
            XCTAssertEqual(hostingView.frame, surface.bounds)
        }
    }

    func testSecureContainerRetainsHostedViewController() {
        let controller = SecureContentViewController(rootView: AnyView(Text("Coufunch")))
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.children.count, 1)
        XCTAssertTrue(controller.children[0].parent === controller)
    }
}
