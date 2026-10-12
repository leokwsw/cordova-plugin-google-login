export interface GoogleLoginUser {
    idToken: string;
    userId: string;
    email: string | null;
    displayName: string | null;
    givenName: string | null;
    familyName: string | null;
    photoUrl: string | null;
    /** iOS only. */
    accessToken?: string | null;
    /** iOS only. ISO-8601 timestamp. */
    accessTokenExpiration?: string | null;
    /** iOS only. Present when a web client ID is configured. */
    serverAuthCode?: string | null;
    /** Android only. The raw nonce embedded in the ID token. */
    nonce?: string;
}

export interface GoogleLoginOptions {
    /** iOS OAuth client ID. Falls back to the GOOGLE_IOS_CLIENT_ID install variable. */
    iosClientId?: string;
    /** Web OAuth client ID. Required on Android. Falls back to GOOGLE_WEB_CLIENT_ID. */
    webClientId?: string;
    /** Extra OAuth scopes. Honored on iOS. Android rejects a non-empty list. */
    scopes?: string[];
    /** Email to prefill. Honored on iOS. */
    loginHint?: string;
    /**
     * Raw nonce placed in the Android ID token.
     * When omitted on Android, the plugin generates one and returns it on the user.
     * iOS rejects this option.
     */
    nonce?: string;
}

export interface GoogleLoginError {
    code:
        | "CANCELED"
        | "NO_CREDENTIAL"
        | "NOT_SIGNED_IN"
        | "MISSING_CLIENT_ID"
        | "NO_ACTIVITY"
        | "SCOPES_UNSUPPORTED"
        | "NONCE_UNSUPPORTED"
        | "REQUEST_IN_PROGRESS"
        | "SIGN_IN_FAILED"
        | string;
    message: string;
}

interface GoogleLoginPlugin {
    signIn(options?: GoogleLoginOptions): Promise<GoogleLoginUser>;
    signIn(
        options: GoogleLoginOptions,
        success: (user: GoogleLoginUser) => void,
        failure?: (error: GoogleLoginError) => void
    ): void;
    silentSignIn(options?: GoogleLoginOptions): Promise<GoogleLoginUser>;
    silentSignIn(
        options: GoogleLoginOptions,
        success: (user: GoogleLoginUser) => void,
        failure?: (error: GoogleLoginError) => void
    ): void;
    signOut(): Promise<boolean>;
    signOut(success: (ok: boolean) => void, failure?: (error: GoogleLoginError) => void): void;
    disconnect(): Promise<boolean>;
    disconnect(success: (ok: boolean) => void, failure?: (error: GoogleLoginError) => void): void;
    getCurrentUser(): Promise<GoogleLoginUser>;
    getCurrentUser(
        success: (user: GoogleLoginUser) => void,
        failure?: (error: GoogleLoginError) => void
    ): void;
}

declare const GoogleLogin: GoogleLoginPlugin;

export default GoogleLogin;
