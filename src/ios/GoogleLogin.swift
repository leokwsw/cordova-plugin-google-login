#if canImport(Cordova)
import Cordova
#endif
import Foundation
import GoogleSignIn
import UIKit

/// Cordova bridge for Sign in with Google.
///
/// The JavaScript service name is `GoogleLogin`. Selectors must keep the
/// trailing colon so they match `CDVCommandQueue`'s `action:` lookup.
@objc(GoogleLogin)
class GoogleLogin: CDVPlugin {
    private var currentCommand: CDVInvokedUrlCommand?
    private let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    override func pluginInitialize() {
        super.pluginInitialize()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didOpenURL(_:)),
            name: Notification.Name(CDVPluginHandleOpenURLNotification),
            object: nil
        )
        GIDSignIn.wrapperIdentifier = "cordova-plugin-google-login"
        GIDSignIn.sharedInstance.configure { _ in }
    }

    override func dispose() {
        NotificationCenter.default.removeObserver(self)
        super.dispose()
    }

    @objc func didOpenURL(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    override func onReset() {
        currentCommand = nil
    }

    @objc(signIn:)
    func signIn(_ command: CDVInvokedUrlCommand) {
        let options = dictionaryArgument(from: command)
        guard beginInteractive(command, options: options) else { return }

        guard let viewController = self.viewController else {
            currentCommand = nil
            fail(command, code: "NO_ACTIVITY", message: "The view controller is not available.")
            return
        }

        GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController,
            hint: stringOption(options, key: "loginHint"),
            additionalScopes: additionalScopes(from: options)
        ) { [weak self] result, error in
            guard let self = self else { return }
            self.finishInteractive(command, result: result, error: error)
        }
    }

    @objc(silentSignIn:)
    func silentSignIn(_ command: CDVInvokedUrlCommand) {
        let options = dictionaryArgument(from: command)
        guard beginInteractive(command, options: options) else { return }

        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            guard let self = self else { return }
            defer { self.currentCommand = nil }

            if let error = error {
                self.fail(command, error: error, fallback: "NO_CREDENTIAL")
                return
            }
            guard let user = user else {
                self.fail(command, code: "NO_CREDENTIAL", message: "No saved Google sign-in was found.")
                return
            }
            guard let payload = self.userPayload(user: user, serverAuthCode: nil) else {
                self.fail(command, code: "SIGN_IN_FAILED", message: "Google did not return an ID token.")
                return
            }
            self.send(CDVPluginResult(status: .ok, messageAs: payload), callbackId: command.callbackId)
        }
    }

    @objc(signOut:)
    func signOut(_ command: CDVInvokedUrlCommand) {
        GIDSignIn.sharedInstance.signOut()
        send(CDVPluginResult(status: .ok, messageAs: true), callbackId: command.callbackId)
    }

    @objc(disconnect:)
    func disconnect(_ command: CDVInvokedUrlCommand) {
        let signIn = GIDSignIn.sharedInstance
        if signIn.currentUser != nil {
            revoke(command)
            return
        }
        if !signIn.hasPreviousSignIn() {
            send(CDVPluginResult(status: .ok, messageAs: true), callbackId: command.callbackId)
            return
        }

        signIn.restorePreviousSignIn { [weak self] user, _ in
            guard let self = self else { return }
            if user == nil {
                signIn.signOut()
                self.send(CDVPluginResult(status: .ok, messageAs: true), callbackId: command.callbackId)
                return
            }
            self.revoke(command)
        }
    }

    @objc(getCurrentUser:)
    func getCurrentUser(_ command: CDVInvokedUrlCommand) {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            fail(command, code: "NOT_SIGNED_IN", message: "No Google user is signed in for this process.")
            return
        }
        guard let payload = userPayload(user: user, serverAuthCode: nil) else {
            fail(command, code: "SIGN_IN_FAILED", message: "Google did not return an ID token.")
            return
        }
        send(CDVPluginResult(status: .ok, messageAs: payload), callbackId: command.callbackId)
    }

    private func beginInteractive(_ command: CDVInvokedUrlCommand, options: [String: Any]) -> Bool {
        if stringOption(options, key: "nonce") != nil {
            fail(command, code: "NONCE_UNSUPPORTED", message: "nonce is not supported on iOS.")
            return false
        }
        if isPresent(options["scopes"]) {
            guard let rawScopes = options["scopes"] as? [Any], rawScopes.allSatisfy({ $0 is String }) else {
                fail(command, code: "SIGN_IN_FAILED", message: "scopes must be an array of strings.")
                return false
            }
        }
        guard let iosClientId = resolved(options, key: "iosClientId", preference: "GoogleIOSClientId") else {
            fail(command, code: "MISSING_CLIENT_ID", message: "iosClientId is required.")
            return false
        }
        if currentCommand != nil {
            fail(command, code: "REQUEST_IN_PROGRESS", message: "A Google sign-in request is already in progress.")
            return false
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: iosClientId,
            serverClientID: resolved(options, key: "webClientId", preference: "GoogleWebClientId")
        )
        currentCommand = command
        return true
    }

    private func finishInteractive(
        _ command: CDVInvokedUrlCommand,
        result: GIDSignInResult?,
        error: Error?
    ) {
        defer { currentCommand = nil }

        if let error = error {
            fail(command, error: error, fallback: "SIGN_IN_FAILED")
            return
        }
        guard let result = result else {
            fail(command, code: "SIGN_IN_FAILED", message: "Google did not return a sign-in result.")
            return
        }
        guard let payload = userPayload(user: result.user, serverAuthCode: result.serverAuthCode) else {
            fail(command, code: "SIGN_IN_FAILED", message: "Google did not return an ID token.")
            return
        }
        send(CDVPluginResult(status: .ok, messageAs: payload), callbackId: command.callbackId)
    }

    private func revoke(_ command: CDVInvokedUrlCommand) {
        GIDSignIn.sharedInstance.disconnect { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.fail(command, error: error, fallback: "SIGN_IN_FAILED")
                return
            }
            self.send(CDVPluginResult(status: .ok, messageAs: true), callbackId: command.callbackId)
        }
    }

    private func dictionaryArgument(from command: CDVInvokedUrlCommand) -> [String: Any] {
        guard let arguments = command.arguments,
              let options = arguments.first as? [String: Any] else {
            return [:]
        }
        return options
    }

    private func resolved(_ options: [String: Any], key: String, preference: String) -> String? {
        if let value = stringOption(options, key: key) {
            return value
        }
        return self.preference(preference)
    }

    private func preference(_ name: String) -> String? {
        let settings = commandDelegate.settings as NSDictionary
        let value = settings[name.lowercased()] as? String
        return trimmed(value)
    }

    private func stringOption(_ options: [String: Any], key: String) -> String? {
        return trimmed(options[key] as? String)
    }

    private func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private func isPresent(_ value: Any?) -> Bool {
        guard let value = value else { return false }
        return !(value is NSNull)
    }

    private func additionalScopes(from options: [String: Any]) -> [String]? {
        guard let values = options["scopes"] as? [Any] else { return nil }
        let scopes = values.compactMap { item -> String? in
            guard let text = item as? String else { return nil }
            return trimmed(text)
        }
        return scopes.isEmpty ? nil : scopes
    }

    private func json(_ value: String?) -> Any {
        if let value = value, !value.isEmpty {
            return value
        }
        return NSNull()
    }

    private func userPayload(user: GIDGoogleUser, serverAuthCode: String?) -> [String: Any]? {
        guard let idToken = user.idToken?.tokenString, !idToken.isEmpty else { return nil }

        let profile = user.profile
        var photo: Any = NSNull()
        if let profile = profile, profile.hasImage, let url = profile.imageURL(withDimension: 120) {
            photo = url.absoluteString
        }

        let expiration: Any
        if let date = user.accessToken.expirationDate {
            expiration = iso8601.string(from: date)
        } else {
            expiration = NSNull()
        }

        return [
            "idToken": idToken,
            "userId": json(user.userID),
            "email": json(profile?.email),
            "displayName": json(profile?.name),
            "givenName": json(profile?.givenName),
            "familyName": json(profile?.familyName),
            "photoUrl": photo,
            "accessToken": user.accessToken.tokenString,
            "accessTokenExpiration": expiration,
            "serverAuthCode": json(serverAuthCode)
        ]
    }

    private func send(_ result: CDVPluginResult, callbackId: String) {
        DispatchQueue.main.async {
            self.commandDelegate.send(result, callbackId: callbackId)
        }
    }

    private func fail(_ command: CDVInvokedUrlCommand, code: String, message: String) {
        let payload: [String: Any] = [
            "code": code,
            "message": message
        ]
        send(CDVPluginResult(status: .error, messageAs: payload), callbackId: command.callbackId)
    }

    private func fail(_ command: CDVInvokedUrlCommand, error: Error, fallback: String) {
        let nsError = error as NSError
        var code = fallback
        if nsError.domain == kGIDSignInErrorDomain {
            switch nsError.code {
            case -5:
                code = "CANCELED"
            case -4:
                code = "NO_CREDENTIAL"
            default:
                break
            }
        }
        fail(command, code: code, message: nsError.localizedDescription)
    }
}
