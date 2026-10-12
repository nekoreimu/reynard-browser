//
//  SelectionActionPresenter.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView
import UIKit

@MainActor
final class SelectionActionPresenter: SelectionActionPresenting {
    private var menuHosts: [ObjectIdentifier: SelectionActionMenuHostView] = [:]
    private let onMenuDismissed: (GeckoSession) -> Void
    private let onFindInPage: (GeckoSession, String) -> Void
    
    // MARK: - Lifecycle
    
    init(
        onMenuDismissed: @escaping (GeckoSession) -> Void,
        onFindInPage: @escaping (GeckoSession, String) -> Void
    ) {
        self.onMenuDismissed = onMenuDismissed
        self.onFindInPage = onFindInPage
    }
    
    func show(_ request: SelectionActionRequest, for session: GeckoSession) {
        guard request.editable == false,
              !request.selection.isEmpty,
              let targetView = session.engineView,
              let selectionRect = localRect(for: request.clientRect, in: targetView) else {
            existingMenuHost(for: session)?.hideMenu()
            return
        }
        
        let host = menuHost(for: session)
        host.present(
            on: targetView,
            session: session,
            actionId: request.actionId,
            anchorRect: selectionRect,
            selection: request.selection,
            actions: request.actions
        )
    }
    
    func hide(for session: GeckoSession) {
        existingMenuHost(for: session)?.hideMenu()
    }
    
    // MARK: - Hosts
    
    private func existingMenuHost(for session: GeckoSession) -> SelectionActionMenuHostView? {
        menuHosts[ObjectIdentifier(session)]
    }
    
    private func menuHost(for session: GeckoSession) -> SelectionActionMenuHostView {
        let key = ObjectIdentifier(session)
        if let host = menuHosts[key] {
            return host
        }
        
        let host = SelectionActionMenuHostView(
            onDismissed: onMenuDismissed,
            onFindInPage: onFindInPage
        )
        menuHosts[key] = host
        return host
    }
    
    // MARK: - Geometry
    
    private func localRect(for clientRect: CGRect, in view: UIView) -> CGRect? {
        let window = (view as? UIWindow) ?? view.window
        guard let window else { return nil }
        
        let scale = window.screen.scale
        let localRect = CGRect(
            x: clientRect.origin.x / scale,
            y: clientRect.origin.y / scale,
            width: clientRect.size.width / scale,
            height: clientRect.size.height / scale
        )
        
        let clippedRect = localRect.intersection(view.bounds)
        guard !clippedRect.isNull, !clippedRect.isEmpty else {
            return nil
        }
        
        return clippedRect
    }
}
