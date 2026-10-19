//
//  NavigationDelegate.swift
//  Reynard
//
//  Created by Minh Ton on 22/2/26.
//

import Foundation

// MARK: - Navigation Models

public enum LoadRequestTarget {
    case current
    case new
    case background
}

public struct LoadRequest {
    public let uri: String
    public let triggerUri: String?
    public let target: LoadRequestTarget
    public let isRedirect: Bool
    public let hasUserGesture: Bool
    public let isUserInitiatedNavigation: Bool
    public let isDirectNavigation: Bool
}

private func loadRequestTarget(from value: Int32) -> LoadRequestTarget {
    switch value {
    case 0, 1:
        return .current
    case 5:
        return .background
    default:
        return .new
    }
}

private func loadRequest(from message: [String: Any?]?) -> LoadRequest? {
    guard let uri = message?["uri"] as? String else {
        return nil
    }
    
    let flags = PayloadValue.int(message?["flags"]) ?? 0
    let targetValue = PayloadValue.int32(message?["where"]) ?? 0
    let hasUserGesture = message?["hasUserGesture"] as? Bool ?? false
    let isRedirectFlag = 0x800000
    
    return LoadRequest(
        uri: uri,
        triggerUri: message?["triggerUri"] as? String,
        target: loadRequestTarget(from: targetValue),
        isRedirect: (flags & isRedirectFlag) != 0,
        hasUserGesture: hasUserGesture,
        isUserInitiatedNavigation:
            message?["isUserInitiatedNavigation"] as? Bool ?? hasUserGesture,
        isDirectNavigation: true
    )
}

// MARK: - Navigation Delegate

public protocol NavigationDelegate {
    func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission])
    func onCanGoBack(session: GeckoSession, canGoBack: Bool)
    func onCanGoForward(session: GeckoSession, canGoForward: Bool)
    func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny
    func onPreNavigation(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny
    func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny
    func onLoadError(session: GeckoSession, error: WebRequestError) -> String?
    func onNewSession(
        session: GeckoSession,
        uri: String,
        windowId: String,
        target: LoadRequestTarget
    ) async -> GeckoSession?
}

extension NavigationDelegate {
    public func onLocationChange(session: GeckoSession, url: String?, permissions: [ContentPermission]) {}
    public func onCanGoBack(session: GeckoSession, canGoBack: Bool) {}
    public func onCanGoForward(session: GeckoSession, canGoForward: Bool) {}
    public func onLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny { .allow }
    public func onPreNavigation(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny { .allow }
    public func onSubframeLoadRequest(session: GeckoSession, request: LoadRequest) async -> AllowOrDeny { .allow }
    public func onLoadError(session: GeckoSession, error: WebRequestError) -> String? { nil }
    public func onNewSession(session: GeckoSession, uri: String, windowId: String, target: LoadRequestTarget) async -> GeckoSession? { nil }
}

// MARK: - Navigation Events

enum NavigationEvents: String, CaseIterable {
    case locationChange = "GeckoView:LocationChange"
    case onNewSession = "GeckoView:OnNewSession"
    case onLoadError = "GeckoView:OnLoadError"
    case onLoadRequest = "GeckoView:OnLoadRequest"
    case preNavigation = "GeckoView:OnPreNavigation"
}

// MARK: - Navigation Handler

func newNavigationHandler(_ session: GeckoSession) -> GeckoSessionHandler {
    GeckoSessionHandler(
        moduleName: "GeckoViewNavigation",
        events: NavigationEvents.allCases.map(\.rawValue),
        session: session
    ) { @MainActor session, delegate, type, message in
        guard let event = NavigationEvents(rawValue: type) else {
            throw GeckoHandlerError("unknown message \(type)")
        }
        
        let delegate = delegate as? NavigationDelegate
        switch event {
        case .locationChange:
            if message?["isTopLevel"] as? Bool == true {
                let permissionPayloads = message?["permissions"] as? [[String: Any?]]
                delegate?.onLocationChange(
                    session: session,
                    url: message?["uri"] as? String,
                    permissions: permissionPayloads?.map(ContentPermission.fromDictionary) ?? []
                )
            }
            
            delegate?.onCanGoBack(session: session, canGoBack: message?["canGoBack"] as? Bool ?? false)
            delegate?.onCanGoForward(
                session: session,
                canGoForward: message?["canGoForward"] as? Bool ?? false
            )
            return nil
            
        case .onNewSession:
            guard
                let uri = message?["uri"] as? String,
                let requestedWindowID = message?["newSessionId"] as? String
            else {
                return false
            }
            
            let target = loadRequestTarget(
                from: PayloadValue.int32(message?["where"]) ?? 2
            )
            
            if let newSession = await delegate?.onNewSession(
                session: session,
                uri: uri,
                windowId: requestedWindowID,
                target: target
            ) {
                if let windowId = newSession.id,
                   windowId != requestedWindowID {
                    assertionFailure("GeckoSession was opened with mismatched window id")
                    return false
                }
                if !newSession.isOpen() {
                    newSession.open(windowId: requestedWindowID)
                }
                return true
            }
            return false
            
        case .onLoadError:
            return delegate?.onLoadError(session: session, error: WebRequestError(message: message))
            
        case .onLoadRequest:
            guard let request = loadRequest(from: message) else {
                return true
            }
            
            let isTopLevel = message?["isTopLevel"] as? Bool ?? true
            if isTopLevel {
                // GeckoView expects this response to mean "handled by the app".
                // Allow must therefore return false so Gecko continues the load itself.
                return await delegate?.onLoadRequest(session: session, request: request) == .deny
            }
            return await delegate?.onSubframeLoadRequest(session: session, request: request) == .deny
            
        case .preNavigation:
            guard let request = loadRequest(from: message) else {
                return false
            }
            return await delegate?.onPreNavigation(session: session, request: request) == .deny
        }
    }
}
