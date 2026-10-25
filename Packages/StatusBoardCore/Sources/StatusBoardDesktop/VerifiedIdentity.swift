import Foundation

struct VerifiedIdentity: Equatable {
    let id: String
    let namespace: String
    let readScope: DesktopReadScope
    var fingerprint: String {
        // Length-prefix the components so boundaries are unambiguous. Include
        // the authenticated user scope, since a workspace can have many users.
        let principal = [namespace, id, readScope.identityKey]
            .map { "\($0.utf8.count):\($0)" }.joined()
        return DesktopReadScope.digest(Data(principal.utf8))
    }
    static func read(_ rpc: any DesktopRPC) throws -> VerifiedIdentity {
        let response: [String: Any]
        do { response = try rpc.request("account/read", ["refreshToken": false]) }
        catch { throw StageFailure(stage: .account, cause: error) }
        guard let routing = response["workspaceRouting"] as? [String: Any],
              let id = routing["chatgptAccountId"] as? String, !id.isEmpty,
              let namespace = routing["backendOrigin"] as? String, !namespace.isEmpty else { throw DesktopFailure.unavailable }
        do {
            let auth = try rpc.request("getAuthStatus", ["includeToken": true, "refreshToken": false])
            return VerifiedIdentity(id: id, namespace: namespace, readScope: try .authenticated(auth, account: id))
        } catch { throw StageFailure(stage: .authentication, cause: error) }
    }
}

