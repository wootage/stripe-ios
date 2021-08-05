//
//  IdentityVerificationSheet.swift
//  StripeIdentity
//
//  Created by Mel Ludowise on 3/3/21.
//  Copyright © 2021 Stripe, Inc. All rights reserved.
//

import UIKit
@_spi(STP) import StripeCore

/**
 A drop-in class that presents a sheet for a user to verify their identity.
 This class is in beta; see https://stripe.com/docs/identity for access
 */
final public class IdentityVerificationSheet {

    /// The result of an attempt to finish an identity verification flow
    @frozen public enum VerificationFlowResult {
        /// User completed the verification flow
        case flowCompleted
        /// User canceled out of the flow or declined to give consent
        case flowCanceled
        /// Failed with error
        case flowFailed(error: Error)
    }

    /**
     The client secret of the Stripe VerificationSession object.
     See https://stripe.com/docs/api/identity/verification_sessions
     */
    public let verificationSessionClientSecret: String

    /**
     Initializes an `IdentityVerificationSheet`
     - Parameters:
       - verificationSessionClientSecret: The [client secret](https://stripe.com/docs/api/identity/verification_sessions) of a Stripe VerificationSession object.
     */
    public convenience init(verificationSessionClientSecret: String) {
        self.init(verificationSessionClientSecret: verificationSessionClientSecret,
                  analyticsClient: STPAnalyticsClient.sharedClient)
    }

    init(verificationSessionClientSecret: String,
         analyticsClient: STPAnalyticsClientProtocol) {
        self.verificationSessionClientSecret = verificationSessionClientSecret
        self.clientSecret = VerificationClientSecret(string: verificationSessionClientSecret)
        self.analyticsClient = analyticsClient

        analyticsClient.addClass(toProductUsageIfNecessary: IdentityVerificationSheet.self)
    }

    /**
     Presents a sheet for a customer to verify their identity.
     - Parameters:
       - presentingViewController: The view controller to present the identity verification sheet.
       - completion: Called with the result of the verification session after the identity verification sheet is dismissed.
     */
    @available(iOS 14.3, *)
    @available(macCatalyst, unavailable)
    @available(iOSApplicationExtension, unavailable)
    @available(macCatalystApplicationExtension, unavailable)
    public func present(
        from presentingViewController: UIViewController,
        completion: @escaping (VerificationFlowResult) -> Void
    ) {
        presentInternal(from: presentingViewController, completion: completion)
    }

    /*
     TODO(mludowise|RUN_MOBILESDK-120): Internal method for `present` so we can
     call it form tests that run on versions prior to iOS 14. This can be removed
     after we've updated our CI to run tests on iOS 14.
     */
    @available(iOSApplicationExtension, unavailable)
    @available(macCatalystApplicationExtension, unavailable)
    @available(macCatalyst, unavailable)
    func presentInternal(
        from presentingViewController: UIViewController,
        completion: @escaping (VerificationFlowResult) -> Void
    ) {
        // Overwrite completion closure to retain self until called
        let completion: (VerificationFlowResult) -> Void = { result in
            self.analyticsClient.log(analytic: VerificationSheetCompletionAnalytic.make(
                verificationSessionId: self.clientSecret?.verificationSessionId,
                sessionResult: result
            ))
            completion(result)
            self.completion = nil
        }
        self.completion = completion

        // Guard against basic user error
        guard presentingViewController.presentedViewController == nil else {
            assertionFailure("presentingViewController is already presenting a view controller")
            let error = IdentityVerificationSheetError.unknown(
                debugDescription: "presentingViewController is already presenting a view controller"
            )
            completion(.flowFailed(error: error))
            return
        }

        // Validate client secret
        guard let clientSecret = clientSecret else {
            completion(.flowFailed(error: IdentityVerificationSheetError.invalidClientSecret))
            return
        }

        let navigationController = VerificationFlowWebViewController.makeInNavigationController(
            clientSecret: clientSecret,
            delegate: self
        )
        analyticsClient.log(analytic: VerificationSheetPresentedAnalytic(verificationSessionId: clientSecret.verificationSessionId))
        presentingViewController.present(navigationController, animated: true)
    }

    // MARK: - Private

    /// Analytics client to use for logging analytics
    private let analyticsClient: STPAnalyticsClientProtocol

    /// Completion block called when the sheet is closed or fails to open
    private var completion: ((VerificationFlowResult) -> Void)?

    /// Parsed client secret string
    private let clientSecret: VerificationClientSecret?
}

// MARK: - VerificationFlowWebViewControllerDelegate

@available(iOSApplicationExtension, unavailable)
@available(macCatalystApplicationExtension, unavailable)
@available(macCatalyst, unavailable)
extension IdentityVerificationSheet: VerificationFlowWebViewControllerDelegate {
    func verificationFlowWebViewController(_ viewController: VerificationFlowWebViewController, didFinish result: VerificationFlowResult) {
        completion?(result)
    }
}

// MARK: - STPAnalyticsProtocol

/// :nodoc:
@_spi(STP) extension IdentityVerificationSheet: STPAnalyticsProtocol {
    @_spi(STP) public static var stp_analyticsIdentifier = "IdentityVerificationSheet"
}
