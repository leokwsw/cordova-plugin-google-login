# cordova-plugin-google-login

Cordova 的 Google 登入外掛。iOS 原生程式是 Swift，使用 [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios)。Android 原生程式是 Kotlin，使用 [Credential Manager 的 Sign in with Google](https://developer.android.com/identity/sign-in/credential-manager-siwg)。

兩種平台都會把 Google ID token 交回 JavaScript。請在你自己的伺服器驗證這個 token，不要只信任 WebView 裡的結果。

## 需求

- Cordova 11 或更新版本
- cordova-android 10 或更新版本（Kotlin 會由外掛開啟）
- cordova-ios 7 或更新版本；cordova-ios 8 以上會改用 Swift Package Manager，這是建議路徑
- iOS deployment target 13 或更新版本

## 安裝

在 [Google Cloud Console](https://console.cloud.google.com/apis/credentials) 建立 OAuth 用戶端：

1. **iOS 用戶端**：Bundle ID 必須和 App 的 `PRODUCT_BUNDLE_IDENTIFIER` 相同。用戶端 ID 類似 `1234567890-abc.apps.googleusercontent.com`。反向用戶端 ID 是把這組 ID 倒過來，例如 `com.googleusercontent.apps.1234567890-abc`。
2. **網頁用戶端**：Android 一定要這組 ID，而且它是 ID token 的 audience。不要把網頁用戶端的 client secret 放進 App。
3. **Android 用戶端**：套件名稱加上 debug 與 release 的 SHA-1。Android 登入用的是網頁用戶端 ID，不是這組 Android 用戶端 ID。

```bash
cordova plugin add /path/to/cordova-plugin-google-login \
  --variable GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID \
  --variable GOOGLE_REVERSED_CLIENT_ID=YOUR_REVERSED_IOS_CLIENT_ID \
  --variable GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

`GOOGLE_REVERSED_CLIENT_ID` 會寫進 iOS 的 URL scheme。少了它，Google 登入完成後無法回到 App。

呼叫時也可以覆寫用戶端 ID：

```javascript
const user = await GoogleLogin.signIn({
  iosClientId: 'YOUR_IOS_CLIENT_ID',
  webClientId: 'YOUR_WEB_CLIENT_ID'
});
```

Android 的 `webClientId` 若沒有在呼叫時傳入，會使用安裝變數 `GOOGLE_WEB_CLIENT_ID`。

## JavaScript

外掛同時支援 Promise 和 Cordova callback。有傳 callback 時不會回傳 Promise。

```javascript
document.addEventListener('deviceready', async () => {
  try {
    const user = await GoogleLogin.silentSignIn();
    console.log(user.email, user.idToken);
  } catch (error) {
    if (error.code !== 'NO_CREDENTIAL') {
      console.error(error.code, error.message);
      return;
    }

    const user = await GoogleLogin.signIn();
    console.log(user.idToken);
  }
});
```

```javascript
GoogleLogin.signIn({}, function (user) {
  console.log(user.idToken);
}, function (error) {
  if (error.code === 'CANCELED') return;
  console.error(error.message);
});
```

| 方法 | 行為 |
| --- | --- |
| `signIn(options)` | 顯示 Google 帳號選擇畫面 |
| `silentSignIn(options)` | 還原先前授權過的帳號，不主動要求選擇 |
| `signOut()` | 清除這個 App 的 Google 登入狀態 |
| `disconnect()` | iOS 會撤銷授權；Android 會清除 Credential Manager 工作階段 |
| `getCurrentUser()` | 讀取這個行程裡已經取得的使用者，不顯示 UI |

成功時的物件：

```javascript
{
  idToken: '...',
  userId: '...',
  email: 'user@example.com',
  displayName: 'User Name',
  givenName: 'User',
  familyName: 'Name',
  photoUrl: 'https://...',
  accessToken: '...',              // 只有 iOS
  accessTokenExpiration: '...',    // 只有 iOS
  serverAuthCode: '...',           // 只有 iOS，且有設定網頁用戶端 ID
  nonce: '...'                     // 只有 Android
}
```

錯誤物件是 `{ code, message }`，不是 `Error`。

| code | 意義 |
| --- | --- |
| `CANCELED` | 使用者關閉登入畫面 |
| `NO_CREDENTIAL` | 沒有可靜默還原的帳號 |
| `NOT_SIGNED_IN` | 這個行程裡沒有已登入的使用者 |
| `MISSING_CLIENT_ID` | 缺少對應平台的用戶端 ID |
| `NO_ACTIVITY` | 原生畫面還沒準備好 |
| `SCOPES_UNSUPPORTED` | Android 不接受額外 OAuth scope |
| `NONCE_UNSUPPORTED` | iOS 不接受 `nonce` |
| `SIGN_IN_FAILED` | 其他登入失敗 |

## 平台差異

- **iOS** 回傳 ID token、access token，以及（有設定網頁用戶端 ID 時）server auth code。`scopes` 會當成額外授權範圍。`loginHint` 可預填 email。
- **Android** 使用明確的 Sign in with Google 按鈕流程，只回傳 ID token 與基本個人資料。`silentSignIn` 只會尋找先前授權過這個 App 的帳號。沒有傳 `nonce` 時，外掛會自己產生一組，並放在結果的 `nonce` 欄位；這組值也會寫進 ID token。
- Android 的 `signOut` 和 `disconnect` 都會呼叫 `clearCredentialState`。Credential Manager 沒有另外的撤銷授權 API。
- `getCurrentUser` 在 Android 只看這個行程的記憶體快取。App 重開後請改呼叫 `silentSignIn`。

## 伺服器驗證

把 `idToken` 送到你的後端，向 Google 的 token info 端點或用 Google 公開金鑰驗證簽章、`aud`、`iss` 與到期時間。`aud` 應該是你的網頁用戶端 ID。Android 若有使用 nonce，後端也要比對 token 裡的 `nonce`。
