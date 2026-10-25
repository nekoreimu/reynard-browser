//
//  ImportExportProgressAlert.swift
//  Reynard
//
//  Created by Minh Ton on 23/10/26.
//

import UIKit

enum ImportExportProgressAlert {
    private enum UX {
        static let activityIndicatorSpacing: CGFloat = 8
    }
    
    static func run<Value>(
        from presenter: UIViewController,
        message: String,
        operation: () async throws -> Value
    ) async throws -> Value {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.isModalInPresentation = true
        
        await withCheckedContinuation { continuation in
            presenter.present(alert, animated: true) {
                installActivityIndicator(in: alert)
                continuation.resume()
            }
        }
        
        let result: Result<Value, Error>
        do {
            result = .success(try await operation())
        } catch {
            result = .failure(error)
        }
        
        await withCheckedContinuation { continuation in
            alert.dismiss(animated: true) {
                continuation.resume()
            }
        }
        return try result.get()
    }
    
    private static func installActivityIndicator(in alert: UIAlertController) {
        guard let message = alert.message,
              let messageLabel = alert.view.firstDescendantLabel(withText: message) else {
            return
        }
        
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.setContentCompressionResistancePriority(.required, for: .horizontal)
        spinner.startAnimating()
        
        let label = UILabel()
        label.font = messageLabel.font
        label.textColor = messageLabel.textColor
        label.text = message
        label.numberOfLines = 0
        
        let contentView = UIStackView(arrangedSubviews: [spinner, label])
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.axis = .horizontal
        contentView.alignment = .center
        contentView.spacing = UX.activityIndicatorSpacing
        alert.view.addSubview(contentView)
        messageLabel.textColor = .clear
        messageLabel.isAccessibilityElement = false
        
        NSLayoutConstraint.activate([
            contentView.centerXAnchor.constraint(equalTo: messageLabel.centerXAnchor),
            contentView.centerYAnchor.constraint(equalTo: messageLabel.centerYAnchor),
            contentView.leadingAnchor.constraint(greaterThanOrEqualTo: alert.view.layoutMarginsGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(lessThanOrEqualTo: alert.view.layoutMarginsGuide.trailingAnchor),
        ])
    }
}
