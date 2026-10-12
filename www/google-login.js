var exec = require('cordova/exec');

var SERVICE = 'GoogleLogin';

function normalize(options, success, failure) {
    if (typeof options === 'function') {
        return {
            options: {},
            success: options,
            failure: success
        };
    }

    return {
        options: options || {},
        success: success,
        failure: failure
    };
}

function call(action, options, success, failure) {
    var normalized = normalize(options, success, failure);
    var args = [normalized.options];

    if (typeof normalized.success === 'function' || typeof normalized.failure === 'function') {
        exec(normalized.success || function () {}, normalized.failure || function () {}, SERVICE, action, args);
        return;
    }

    return new Promise(function (resolve, reject) {
        exec(resolve, reject, SERVICE, action, args);
    });
}

/**
 * Sign in with Google.
 * iOS is implemented in Swift with Google Sign-In.
 * Android is implemented in Kotlin with Credential Manager.
 */
var GoogleLogin = {
    /**
     * Present the Google account chooser.
     *
     * @param {Object} [options]
     * @param {string} [options.iosClientId] iOS OAuth client ID. Falls back to GOOGLE_IOS_CLIENT_ID.
     * @param {string} [options.webClientId] Web OAuth client ID. Required on Android. Falls back to GOOGLE_WEB_CLIENT_ID.
     * @param {string[]} [options.scopes] Extra OAuth scopes. iOS only.
     * @param {string} [options.loginHint] Email to prefill. iOS only.
     * @param {string} [options.nonce] Raw nonce embedded in the Android ID token. iOS rejects this.
     * @param {Function} [success]
     * @param {Function} [failure]
     * @returns {Promise<Object>|void}
     */
    signIn: function (options, success, failure) {
        return call('signIn', options, success, failure);
    },

    /**
     * Restore a previously authorized account without asking the user to choose.
     *
     * @param {Object} [options] Same fields as signIn.
     * @param {Function} [success]
     * @param {Function} [failure]
     * @returns {Promise<Object>|void}
     */
    silentSignIn: function (options, success, failure) {
        return call('silentSignIn', options, success, failure);
    },

    /**
     * Clear this app's Google sign-in state.
     *
     * @param {Object|Function} [options]
     * @param {Function} [success]
     * @param {Function} [failure]
     * @returns {Promise<boolean>|void}
     */
    signOut: function (options, success, failure) {
        return call('signOut', options, success, failure);
    },

    /**
     * iOS revokes the grant. Android clears the Credential Manager session.
     *
     * @param {Object|Function} [options]
     * @param {Function} [success]
     * @param {Function} [failure]
     * @returns {Promise<boolean>|void}
     */
    disconnect: function (options, success, failure) {
        return call('disconnect', options, success, failure);
    },

    /**
     * Read the user already obtained in this process. Does not present UI.
     *
     * @param {Object|Function} [options]
     * @param {Function} [success]
     * @param {Function} [failure]
     * @returns {Promise<Object>|void}
     */
    getCurrentUser: function (options, success, failure) {
        return call('getCurrentUser', options, success, failure);
    }
};

module.exports = GoogleLogin;
