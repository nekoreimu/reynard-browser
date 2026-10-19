//
//  WebContentErrorView.swift
//  Reynard
//
//  Created by Minh Ton on 18/10/26.
//

import GeckoView
import UIKit

final class WebContentErrorView: UIView, UITextViewDelegate {
    private enum UX {
        static let horizontalInset: CGFloat = 40
        static let verticalInset: CGFloat = 32
        static let maximumWidth: CGFloat = 550
        static let widthPriority = UILayoutPriority(999)
        static let spacing: CGFloat = 24
        static let buttonSpacing: CGFloat = 12
        static let buttonHeight: CGFloat = 48
        static let cornerRadiusDivisor: CGFloat = 2
        static let symbolHeight: CGFloat = 96
        static let symbolSize: CGFloat = 72
        static let lineSpacing: CGFloat = 2
        static let paragraphSpacing: CGFloat = 10
        static let bulletIndent: CGFloat = 14
        static let separatorHeight: CGFloat = 1
    }
    
    enum Action: Equatable {
        case retry
        case back
        case acceptCertificate
        case continueHTTP
        case openLink(URL)
    }
    
    private var error: WebRequestError?
    
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let messageView = UITextView()
    private let errorCodeLabel = UILabel()
    private let primaryButton = UIButton(type: .system)
    private let advancedButton = UIButton(type: .system)
    private let continueHTTPButton = UIButton(type: .system)
    private let advancedPanel = UIStackView()
    private let separator = UIView()
    private let technicalLabel = UILabel()
    private let advancedBackButton = UIButton(type: .system)
    private let acceptButton = UIButton(type: .system)
    
    var onAction: ((Action) -> Void)?
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
        configureConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard #unavailable(iOS 26.0) else {
            return
        }
        
        stack.layoutIfNeeded()
        for button in [primaryButton, advancedButton, continueHTTPButton, advancedBackButton, acceptButton] {
            button.layer.cornerRadius = button.bounds.height / UX.cornerRadiusDivisor
        }
    }
    
    // MARK: - Configuration
    
    private func configureHierarchy() {
        backgroundColor = .systemBackground
        clipsToBounds = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.scrollsToTop = false
        scrollView.showsVerticalScrollIndicator = false
        stack.axis = .vertical
        stack.spacing = UX.spacing
        advancedPanel.axis = .vertical
        advancedPanel.spacing = UX.spacing
        symbolView.contentMode = .left
        symbolView.tintColor = .label
        titleLabel.font = UIFont(
            descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2)
                .withSymbolicTraits(.traitBold)!,
            size: 0
        )
        titleLabel.accessibilityTraits.insert(.header)
        
        for label in [titleLabel, errorCodeLabel, technicalLabel] {
            label.textColor = .label
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            label.adjustsFontForContentSizeCategory = true
        }
        
        for label in [errorCodeLabel, technicalLabel] {
            label.font = .preferredFont(forTextStyle: .body)
        }
        
        messageView.isEditable = false
        messageView.isScrollEnabled = false
        messageView.backgroundColor = .clear
        messageView.font = .preferredFont(forTextStyle: .body)
        messageView.adjustsFontForContentSizeCategory = true
        messageView.textContainerInset = .zero
        messageView.textContainer.lineFragmentPadding = 0
        messageView.linkTextAttributes = [
            .foregroundColor: UIColor.label,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        messageView.setContentCompressionResistancePriority(.required, for: .vertical)
        messageView.delegate = self
        
        for button in [primaryButton, advancedButton, continueHTTPButton, advancedBackButton, acceptButton] {
            let isPrimary = button === primaryButton || button === advancedBackButton
            button.tintColor = .label
            
            if #available(iOS 26.0, *) {
                var configuration = isPrimary
                ? UIButton.Configuration.prominentGlass()
                : UIButton.Configuration.glass()
                configuration.baseBackgroundColor = isPrimary ? .label : nil
                configuration.baseForegroundColor = isPrimary ? nil : .label
                configuration.cornerStyle = .capsule
                configuration.buttonSize = .large
                button.configuration = configuration
            } else {
                button.backgroundColor = isPrimary ? .label : .secondarySystemBackground
                button.setTitleColor(isPrimary ? .systemBackground : .label, for: .normal)
                button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
                button.contentEdgeInsets = UIEdgeInsets(
                    top: UX.buttonSpacing,
                    left: UX.buttonSpacing,
                    bottom: UX.buttonSpacing,
                    right: UX.buttonSpacing
                )
            }
            
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.textAlignment = .center
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: UX.buttonHeight)
                .withPriority(.defaultHigh)
                .isActive = true
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        }
        
        advancedButton.setTitle(NSLocalizedString("Advanced…", tableName: "WebContentErrorLocalizable", comment: ""), for: .normal)
        advancedBackButton.setTitle(NSLocalizedString("Go Back (Recommended)", tableName: "WebContentErrorLocalizable", comment: ""), for: .normal)
        continueHTTPButton.setTitle(NSLocalizedString("Continue to HTTP Website", tableName: "WebContentErrorLocalizable", comment: ""), for: .normal)
        acceptButton.setTitle(NSLocalizedString("Accept the Risk and Continue", tableName: "WebContentErrorLocalizable", comment: ""), for: .normal)
        errorCodeLabel.text = NSLocalizedString("Error Code: NS_ERROR_OFFLINE", tableName: "WebContentErrorLocalizable", comment: "")
        separator.backgroundColor = .separator
        
        addSubview(scrollView)
        scrollView.addSubview(stack)
        [
            symbolView, titleLabel, messageView, errorCodeLabel,
            primaryButton, advancedButton, continueHTTPButton,
        ].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(UX.buttonSpacing, after: primaryButton)
        [separator, technicalLabel, advancedBackButton, acceptButton].forEach(advancedPanel.addArrangedSubview)
    }
    
    private func configureConstraints() {
        for view in [scrollView, stack] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        
        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            content.widthAnchor.constraint(equalTo: frame.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: frame.heightAnchor),
            content.heightAnchor.constraint(equalTo: frame.heightAnchor).withPriority(.defaultLow),
            
            stack.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -UX.horizontalInset * 2)
                .withPriority(UX.widthPriority),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: UX.maximumWidth),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: UX.verticalInset),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -UX.verticalInset),
            
            symbolView.heightAnchor.constraint(equalToConstant: UX.symbolHeight).withPriority(.defaultHigh),
            separator.heightAnchor.constraint(equalToConstant: UX.separatorHeight),
        ])
    }
    
    func configureContentLayout(topAnchor: NSLayoutYAxisAnchor, bottomAnchor: NSLayoutYAxisAnchor) {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    // MARK: - Error Presentation
    
    func configure(error: WebRequestError?, canGoBack: Bool) {
        let isSamePage = self.error == error
        self.error = error
        isHidden = error == nil
        scrollView.scrollsToTop = error != nil
        
        guard let error else {
            return
        }
        
        let highRisk = isHighRisk(error.kind)
        primaryButton.isHidden = !canGoBack && (highRisk || error.kind == .httpsOnly)
        advancedBackButton.isHidden = !canGoBack
        
        guard !isSamePage else {
            return
        }
        
        scrollView.setContentOffset(.zero, animated: false)
        advancedPanel.removeFromSuperview()
        let content = content(for: error.kind)
        titleLabel.text = content.title
        let message = highRisk ? String(format: content.message, error.uri ?? "") : content.message
        let attributedText = attributedMessage(message)
        if error.kind == .contentCrashed {
            let linkText = NSLocalizedString("report the problem", comment: "Inline link in the Page Stopped Working message")
            attributedText.addAttribute(
                .link,
                value: URL(string: "https://github.com/minh-ton/reynard-browser/issues")!,
                range: (message as NSString).range(of: linkText)
            )
        }
        messageView.attributedText = attributedText
        symbolView.image = content.symbol.flatMap {
            UIImage(named: $0, in: .main, with: UIImage.SymbolConfiguration(pointSize: UX.symbolSize))
        }
        symbolView.isHidden = content.symbol == nil
        
        let primaryTitle: String
        switch error.kind {
        case .noInternet:
            primaryTitle = NSLocalizedString("Reload", tableName: "WebContentErrorLocalizable", comment: "")
        case .httpsOnly:
            primaryTitle = NSLocalizedString("Go Back (Recommended)", tableName: "WebContentErrorLocalizable", comment: "")
        default:
            primaryTitle = highRisk
            ? NSLocalizedString("Go Back", tableName: "WebContentErrorLocalizable", comment: "")
            : NSLocalizedString("Try Again", tableName: "WebContentErrorLocalizable", comment: "")
        }
        
        primaryButton.setTitle(primaryTitle, for: .normal)
        advancedButton.isHidden = error.kind != .securityBadCertificate && error.kind != .badHSTSCertificate
        continueHTTPButton.isHidden = error.kind != .httpsOnly
        acceptButton.isHidden = error.kind != .securityBadCertificate
        errorCodeLabel.isHidden = error.kind != .noInternet
    }
    
    private func attributedMessage(_ text: String) -> NSMutableAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [.font: messageView.font!, .foregroundColor: UIColor.label]
        )
        
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byParagraphs) { paragraph, range, _, _ in
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            style.lineSpacing = UX.lineSpacing
            style.paragraphSpacing = UX.paragraphSpacing
            if paragraph?.hasPrefix("• ") == true {
                style.headIndent = UX.bulletIndent
            }
            attributed.addAttribute(.paragraphStyle, value: style, range: NSRange(range, in: text))
        }
        
        return attributed
    }
    
    private func isHighRisk(_ kind: WebRequestError.Kind) -> Bool {
        return [.malware, .unwanted, .harmful, .phishing, .harmfulAddon].contains(kind)
    }
    
    // MARK: - Actions
    
    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        onAction?(.openLink(url))
        return false
    }
    
    @objc private func buttonTapped(_ button: UIButton) {
        guard let error else {
            return
        }
        
        switch button {
        case primaryButton:
            let action: Action = isHighRisk(error.kind) || error.kind == .httpsOnly
            ? .back
            : .retry
            onAction?(action)
        case advancedBackButton:
            onAction?(.back)
        case acceptButton:
            onAction?(.acceptCertificate)
        case continueHTTPButton:
            onAction?(.continueHTTP)
        case advancedButton:
            toggleAdvanced(for: error)
        default:
            break
        }
    }
    
    private func toggleAdvanced(for error: WebRequestError) {
        if advancedPanel.superview != nil {
            advancedPanel.removeFromSuperview()
            return
        }
        
        let uri = error.uri ?? ""
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
        let text: String
        if error.kind == .badHSTSCertificate {
            text = String(
                format: NSLocalizedString("%@ has a security policy called HTTP Strict Transport Security (HSTS), which means that %@ can only connect to it securely. You can’t add an exception to visit this website.", tableName: "WebContentErrorLocalizable", comment: "Website URL, app name"),
                uri, appName
            )
        } else {
            text = String(
                format: NSLocalizedString("Someone could be trying to impersonate the website and you should not continue.\n\nWebsites prove their identity via certificates. %@ does not trust %@ because its certificate issuer is unknown, the certificate is self-signed, or the server is not sending the correct intermediate certificates.", tableName: "WebContentErrorLocalizable", comment: "App name, website URL"),
                appName, uri
            )
        }
        
        let attributed = attributedMessage(text)
        if !uri.isEmpty, let range = text.range(of: uri) {
            attributed.addAttribute(
                .font,
                value: UIFont.preferredFont(forTextStyle: .headline),
                range: NSRange(range, in: text)
            )
        }
        
        technicalLabel.attributedText = attributed
        stack.addArrangedSubview(advancedPanel)
        layoutIfNeeded()
        let target = acceptButton.isHidden ? technicalLabel : acceptButton
        scrollView.scrollRectToVisible(target.convert(target.bounds, to: scrollView), animated: true)
    }
    
    // MARK: - Error Messages
    
    private func content(for kind: WebRequestError.Kind) -> (title: String, message: String, symbol: String?) {
        switch kind {
        case .unknown:
            return (
                NSLocalizedString("Cannot Complete Request", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("Additional information about this problem or error is currently unavailable.", tableName: "WebContentErrorLocalizable", comment: ""),
                nil
            )
        case .securitySSL, .securityBadCertificate:
            return (
                NSLocalizedString("Secure Connection Failed", tableName: "WebContentErrorLocalizable", comment: ""),
                kind == .securitySSL
                ? NSLocalizedString("• The page you are trying to view cannot be shown because the authenticity of the received data could not be verified.\n• Please contact the website owners to inform them of this problem.", tableName: "WebContentErrorLocalizable", comment: "")
                : NSLocalizedString("• This could be a problem with the server’s configuration, or it could be someone trying to impersonate the server.\n• If you have connected to this server successfully in the past, the error may be temporary, and you can try again later.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.lock.open.fill"
            )
        case .netInterrupt:
            return (
                NSLocalizedString("The Connection Was Interrupted", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The browser connected successfully, but the connection was interrupted while transferring information. Please try again.\n• The website could be temporarily unavailable or too busy. Try again in a few moments.\n• If you are unable to load any pages, check your device’s data or Wi-Fi connection.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.exclamationmark.bubble"
            )
        case .netTimeout:
            return (
                NSLocalizedString("The Connection Has Timed Out", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The requested website did not respond to a connection request and the browser has stopped waiting for a reply.\n• Could the server be experiencing high demand or a temporary outage? Try again later.\n• Are you unable to browse other websites? Check the device’s network connection.\n• Is your device or network protected by a firewall or proxy? Incorrect settings can interfere with Web browsing.\n• Still having trouble? Consult your network administrator or Internet provider for assistance.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.clock"
            )
        case .connectionRefused, .localNetworkAccessDenied:
            return (
                NSLocalizedString("Unable to Connect", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("• The website could be temporarily unavailable or too busy. Try again in a few moments.\n• If you are unable to load any pages, check your device’s data or Wi-Fi connection.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.questionmark.circle"
            )
        case .unknownSocketType:
            return (
                NSLocalizedString("Unexpected Response from Server", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The website responded to the network request in an unexpected way and the browser cannot continue.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.questionmark.circle"
            )
        case .redirectLoop:
            return (
                NSLocalizedString("The Page Isn’t Redirecting Properly", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The browser has stopped trying to retrieve the requested item. The website is redirecting the request in a way that will never complete.\n• Have you disabled or blocked cookies required by this website?\n• If accepting the website’s cookies does not resolve the problem, it is likely a server configuration issue and not your device.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
            )
        case .offline:
            return (
                NSLocalizedString("Offline Mode", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The browser is operating in its offline mode and cannot connect to the requested item.\n• Is the device connected to an active network?\n• Press “Try Again” to switch to online mode and reload the page.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.wifi.slash"
            )
        case .portBlocked:
            return (
                NSLocalizedString("Port Restricted for Security Reasons", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The requested address specified a port (e.g., mozilla.org:80 for port 80 on mozilla.org) normally used for purposes other than Web browsing. The browser has canceled the request for your protection and security.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.lock.fill"
            )
        case .netReset:
            return (
                NSLocalizedString("The Connection Was Reset", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The network link was interrupted while negotiating a connection. Please try again.\n• The website could be temporarily unavailable or too busy. Try again in a few moments.\n• If you are unable to load any pages, check your device’s data or Wi-Fi connection.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.bolt.slash"
            )
        case .unsafeContentType:
            return (
                NSLocalizedString("Unsafe File Type", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("• Please contact the website owners to inform them of this problem.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.text.page.badge.magnifyingglass"
            )
        case .corruptedContent:
            return (
                NSLocalizedString("Corrupted Content Error", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The page you are trying to view cannot be shown because an error in the data transmission was detected.\n• Please contact the website owners to inform them of this problem.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.questionmark.text.page"
            )
        case .contentCrashed:
            return (
                NSLocalizedString("Page Stopped Working", comment: ""),
                String(
                    format: NSLocalizedString("The page stopped working unexpectedly.\n\nTry reloading the page. If this keeps happening, please %@.", comment: "Link to report the problem"),
                    NSLocalizedString("report the problem", comment: "Inline link in the Page Stopped Working message")
                ),
                "reynard.exclamationmark.triangle"
            )
        case .invalidContentEncoding:
            return (
                NSLocalizedString("Content Encoding Error", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The page you are trying to view cannot be shown because it uses an invalid or unsupported form of compression.\n• Please contact the website owners to inform them of this problem.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.exclamationmark.triangle"
            )
        case .unknownHost:
            return (
                NSLocalizedString("Address Not Found", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The browser could not find the host server for the provided address.\n• Check the address for typing errors such as ww.example.com instead of www.example.com.\n• If you are unable to load any pages, check your device’s data or Wi-Fi connection.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.questionmark.circle"
            )
        case .noInternet:
            return (
                NSLocalizedString("Looks Like There’s a Problem with Your Internet Connection", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("Try connecting on a different device. Check your modem or router. Disconnect and reconnect to Wi-Fi.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.wifi.slash"
            )
        case .malformedURI:
            return (
                NSLocalizedString("Invalid Address", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The provided address is not in a recognized format. Please check the location bar for mistakes and try again.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.questionmark.circle"
            )
        case .unknownProtocol:
            return (
                NSLocalizedString("Unknown Protocol", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The address specifies a protocol (e.g., wxyz://) the browser does not recognize, so the browser cannot properly connect to the website.\n• Are you trying to access multimedia or other non-text services? Check the website for extra requirements.\n• Some protocols may require third-party software or plugins before the browser can recognize them.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.questionmark.circle"
            )
        case .fileNotFound:
            return (
                NSLocalizedString("File Not Found", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("• Could the item have been renamed, removed, or relocated?\n• Is there a spelling, capitalization, or other typographical error in the address?\n• Do you have sufficient access permissions to the requested item?", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.questionmark.circle"
            )
        case .fileAccessDenied:
            return (
                NSLocalizedString("Access to the File Was Denied", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("• It may have been removed, moved, or file permissions may be preventing access.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.lock.document"
            )
        case .proxyConnectionRefused:
            return (
                NSLocalizedString("Proxy Server Refused Connection", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The browser is configured to use a proxy server, but the proxy refused a connection.\n• Is the browser’s proxy configuration correct? Check the settings and try again.\n• Does the proxy service allow connections from this network?\n• Still having trouble? Consult your network administrator or Internet provider for assistance.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.questionmark.circle"
            )
        case .unknownProxyHost:
            return (
                NSLocalizedString("Proxy Server Not Found", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The browser is configured to use a proxy server, but the proxy could not be found.\n• Is the browser’s proxy configuration correct? Check the settings and try again.\n• Is the device connected to an active network?\n• Still having trouble? Consult your network administrator or Internet provider for assistance.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.bolt.slash"
            )
        case .malware:
            return (
                NSLocalizedString("Malware Website Issue", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The website at %@ has been reported as an attack website and has been blocked based on your security preferences.", tableName: "WebContentErrorLocalizable", comment: "Website URL"),
                nil
            )
        case .unwanted:
            return (
                NSLocalizedString("Unwanted Website Issue", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The website at %@ has been reported as serving unwanted software and has been blocked based on your security preferences.", tableName: "WebContentErrorLocalizable", comment: "Website URL"),
                nil
            )
        case .harmful:
            return (
                NSLocalizedString("Harmful Website Issue", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("The website at %@ has been reported as a potentially harmful website and has been blocked based on your security preferences.", tableName: "WebContentErrorLocalizable", comment: "Website URL"),
                nil
            )
        case .phishing:
            return (
                NSLocalizedString("Deceptive Website Issue", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("This web page at %@ has been reported as a deceptive website and has been blocked based on your security preferences.", tableName: "WebContentErrorLocalizable", comment: "Website URL"),
                nil
            )
        case .harmfulAddon:
            return (
                NSLocalizedString("Website Blocked for Your Safety", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("This web page at %@ has been blocked because one of your add-ons tried to open it. This website could be used to steal your info — like passwords or credit card numbers.", tableName: "WebContentErrorLocalizable", comment: "Website URL"),
                nil
            )
        case .httpsOnly:
            return (
                NSLocalizedString("Secure Website Not Available", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("Most likely, the website simply does not support HTTPS.", tableName: "WebContentErrorLocalizable", comment: "")
                + "\n\n" + NSLocalizedString("However, it’s also possible that an attacker is involved. If you continue to the website, you should not enter any sensitive info. If you continue, HTTPS-Only mode will be turned off temporarily for the website.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.lock.open.fill"
            )
        case .badHSTSCertificate:
            return (
                NSLocalizedString("This Website Requires a Secure Connection.", tableName: "WebContentErrorLocalizable", comment: ""),
                NSLocalizedString("• The page you are trying to view cannot be shown because this website requires a secure connection.\n• The issue is most likely with the website, and there is nothing you can do to resolve it.\n• You can notify the website’s administrator about the problem.", tableName: "WebContentErrorLocalizable", comment: ""),
                "reynard.lock.fill"
            )
        }
    }
}
