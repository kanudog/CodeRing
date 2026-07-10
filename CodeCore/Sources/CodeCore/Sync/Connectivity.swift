// Connectivity.swift — thin WCSession wrapper.
// Everything crossing the bridge is a SyncEnvelope { kind, JSON data }.
// Phone → watch: drug sets, custom events, settings.
// Watch → phone: completed sessions.
// Delivery: sendMessage when reachable, transferUserInfo as the queued fallback.

import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity

public enum SyncKind: String, Codable, Sendable {
    case drugSets, customEvents, session, settings
}

public struct SyncEnvelope: Codable, Sendable {
    public let kind: SyncKind
    public let data: Data
    public init(kind: SyncKind, data: Data) { self.kind = kind; self.data = data }
}

public final class ConnectivityManager: NSObject, WCSessionDelegate {

    public static let shared = ConnectivityManager()

    /// App layer sets this to merge incoming payloads. Always called on main.
    public var onReceive: ((SyncKind, Data) -> Void)?

    private override init() { super.init() }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Sending

    public func send<T: Encodable>(_ kind: SyncKind, _ value: T) {
        guard WCSession.isSupported() else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let payload = try? enc.encode(value),
              let envelope = try? JSONEncoder().encode(SyncEnvelope(kind: kind, data: payload))
        else { return }

        let dict: [String: Any] = ["env": envelope]
        let session = WCSession.default
        if session.activationState == .activated && session.isReachable {
            session.sendMessage(dict, replyHandler: nil) { _ in
                session.transferUserInfo(dict)   // fall back to queued delivery
            }
        } else if session.activationState == .activated {
            session.transferUserInfo(dict)
        }
    }

    // MARK: - Receiving

    private func handle(_ dict: [String: Any]) {
        guard let raw = dict["env"] as? Data,
              let envelope = try? JSONDecoder().decode(SyncEnvelope.self, from: raw)
        else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onReceive?(envelope.kind, envelope.data)
        }
    }

    public func session(_ session: WCSession,
                        didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    public func session(_ session: WCSession,
                        didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handle(userInfo)
    }

    // MARK: - Required delegate plumbing

    public func session(_ session: WCSession,
                        activationDidCompleteWith activationState: WCSessionActivationState,
                        error: Error?) { }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) { }
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}

/// Decoding helper the app layers use inside onReceive.
public enum SyncDecoder {
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(type, from: data)
    }
}
#endif
