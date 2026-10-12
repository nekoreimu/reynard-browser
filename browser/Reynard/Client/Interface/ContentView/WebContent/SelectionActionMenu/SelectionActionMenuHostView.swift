//
//  SelectionActionMenuHostView.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import GeckoView
import UIKit

@MainActor
final class SelectionActionMenuHostView: UITextView {
    private weak var session: GeckoSession?
    private var actionId: String?
    private var availableActions = Set<String>()
    private var menuInteraction: UIInteraction?
    private let onDismissed: (GeckoSession) -> Void
    private let onFindInPage: (GeckoSession, String) -> Void
    
    override var canBecomeFirstResponder: Bool {
        true
    }
    
    override func target(forAction action: Selector, withSender sender: Any?) -> Any? {
        guard actionId != nil else {
            return nil
        }
        
        if action == #selector(copy(_:)) {
            return availableActions.contains(SelectionActionCommand.copy) ? self : nil
        }
        
        if action == #selector(selectAll(_:)) {
            return availableActions.contains(SelectionActionCommand.selectAll) ? self : nil
        }
        
        return super.target(forAction: action, withSender: sender)
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard actionId != nil else {
            return false
        }
        
        if action == #selector(copy(_:)) {
            return availableActions.contains(SelectionActionCommand.copy)
        }
        
        if action == #selector(selectAll(_:)) {
            return availableActions.contains(SelectionActionCommand.selectAll)
        }
        
        if action == #selector(findSelectedText(_:)) {
            return selectedRange.length > 0
        }
        
        return super.canPerformAction(action, withSender: sender)
    }
    
    override func copy(_ sender: Any?) {
        executeAction(SelectionActionCommand.copy)
    }
    
    override func selectAll(_ sender: Any?) {
        executeAction(SelectionActionCommand.selectAll)
    }
    
    override func firstRect(for range: UITextRange) -> CGRect {
        return bounds
    }
    
    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        return []
    }
    
    // MARK: - Lifecycle
    
    init(
        onDismissed: @escaping (GeckoSession) -> Void,
        onFindInPage: @escaping (GeckoSession, String) -> Void
    ) {
        self.onDismissed = onDismissed
        self.onFindInPage = onFindInPage
        super.init(frame: .zero, textContainer: nil)
        configureAppearance()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func configureAppearance() {
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        
        if #available(iOS 16.0, *) {
            let interaction = UIEditMenuInteraction(delegate: self)
            addInteraction(interaction)
            menuInteraction = interaction
        }
        
        if #available(iOS 18.0, *) {
            writingToolsBehavior = .limited
        }
    }
    
    // MARK: - Presentation
    
    func present(
        on view: UIView,
        session: GeckoSession,
        actionId: String,
        anchorRect: CGRect,
        selection: String,
        actions: [String]
    ) {
        self.session = session
        self.actionId = actionId
        availableActions = Set(actions)
        
        if superview !== view {
            removeFromSuperview()
            view.addSubview(self)
        }
        
        if frame != anchorRect {
            frame = anchorRect
        }
        
        text = selection
        selectedRange = NSRange(location: 0, length: (selection as NSString).length)
        
        if !isFirstResponder {
            becomeFirstResponder()
        }
        
        if #available(iOS 16.0, *),
           let interaction = menuInteraction as? UIEditMenuInteraction {
            let configuration = UIEditMenuConfiguration(
                identifier: actionId,
                sourcePoint: CGPoint(x: bounds.midX, y: bounds.midY)
            )
            configuration.preferredArrowDirection = .down
            interaction.presentEditMenu(with: configuration)
        } else {
            let menuController = UIMenuController.shared
            menuController.hideMenu(from: self)
            menuController.arrowDirection = .down
            menuController.showMenu(from: self, rect: bounds)
        }
    }
    
    func hideMenu() {
        let dismissedSession = actionId == nil ? nil : session
        if #available(iOS 16.0, *),
           let interaction = menuInteraction as? UIEditMenuInteraction {
            interaction.dismissMenu()
        } else if superview != nil {
            UIMenuController.shared.hideMenu(from: self)
        } else {
            UIMenuController.shared.hideMenu()
        }
        
        if isFirstResponder {
            resignFirstResponder()
        }
        
        actionId = nil
        availableActions.removeAll()
        if let dismissedSession {
            onDismissed(dismissedSession)
        }
    }
    
    func dismissAndRemove() {
        hideMenu()
        removeFromSuperview()
        session = nil
    }
    
    // MARK: - Actions
    
    @objc(_findSelected:) private func findSelectedText(_ sender: Any?) {
        guard let session,
              let range = selectedTextRange,
              let selection = text(in: range),
              !selection.isEmpty else {
            return
        }
        
        hideMenu()
        onFindInPage(session, selection)
    }
    
    private func executeAction(_ commandId: String) {
        guard let session, let actionId else {
            return
        }
        
        session.executeSelectionAction(actionId: actionId, commandId: commandId)
        hideMenu()
    }
}

@available(iOS 16.0, *)
extension SelectionActionMenuHostView: UIEditMenuInteractionDelegate {
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        targetRectFor configuration: UIEditMenuConfiguration
    ) -> CGRect {
        return bounds
    }
}
