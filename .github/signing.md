# Sign and notarize releases

Without signing secrets, the Release workflow signs Afterhours ad-hoc. macOS then says Apple can't check the app for malware, and people have to click **Open Anyway** in **System Settings > Privacy & Security**. With the secrets below, the workflow signs the app with a Developer ID certificate and the hardened runtime, sends the app and the `.dmg` to Apple's notary service, and staples the tickets to both. Gatekeeper then opens the app without a warning, even offline.

## 1. Join the Apple Developer Program

Enroll at [developer.apple.com/programs](https://developer.apple.com/programs/). It costs 99 USD a year. An individual enrollment works. Your Team ID appears under **Membership details**, and it ends up in the certificate's name, so you don't need a secret for it.

## 2. Create a Developer ID Application certificate

1. On a Mac, open **Keychain Access** and choose **Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority**. Enter your email, choose **Saved to disk**, and save the `.certSigningRequest` file.
2. At [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/add), add a certificate, choose **Developer ID Application**, pick the **G2 Sub-CA**, and upload the request. Only the Account Holder can create this certificate.
3. Download the `.cer` file and double-click it to add it to your login keychain.
4. In Keychain Access, open **My Certificates**, select **Developer ID Application: Your Name (TEAMID)**, and choose **File > Export Items**. Save it as a `.p12` file with a strong password.

Check it with `security find-identity -v -p codesigning`. It should list the identity.

## 3. Create an App Store Connect API key

`notarytool` signs in with an API key, so CI needs no Apple ID password.

1. In [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api), open **Users and Access > Integrations > App Store Connect API**. The Account Holder may have to request access first.
2. Under **Team Keys**, generate a key with the **Developer** role.
3. Download the `AuthKey_XXXXXXXXXX.p8` file. Apple lets you download it only once.
4. Note the **Key ID** shown next to the key and the **Issuer ID** shown above the list.

## 4. Add the repository secrets

Add these at **Settings > Secrets and variables > Actions** in GitHub, or with `gh secret set`:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12` | The `.p12` file in base64: `base64 -i DeveloperID.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | The password you set when you exported the `.p12` |
| `NOTARY_KEY` | The whole text of `AuthKey_XXXXXXXXXX.p8`, including the `BEGIN` and `END` lines |
| `NOTARY_KEY_ID` | The Key ID |
| `NOTARY_ISSUER_ID` | The Issuer ID |

For example:

```sh
base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_P12
gh secret set DEVELOPER_ID_P12_PASSWORD
gh secret set NOTARY_KEY < AuthKey_XXXXXXXXXX.p8
gh secret set NOTARY_KEY_ID --body XXXXXXXXXX
gh secret set NOTARY_ISSUER_ID --body xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Set all five or none. With only some of them, the workflow fails instead of shipping an unnotarized build.

## 5. Check the first notarized release

Run the Release workflow by hand from the Actions tab, or wait for the next release. Then download the `.dmg` and check it:

```sh
spctl --assess --type open --context context:primary-signature -vv Afterhours-*.dmg
xcrun stapler validate Afterhours-*.dmg
spctl --assess -vv /Applications/Afterhours.app
```

The app check should say `accepted` and `source=Notarized Developer ID`.

Once a notarized release is out, remove the Open Anyway step from `.github/release-install.md`, the Download section of `README.md`, and `apps/web/components/install-note.tsx`.

## Sign locally

`CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./apps/macos/scripts/build-app.sh` signs a local build the same way. To notarize it too, also set `NOTARY_KEY_PATH`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID`, then run `./apps/macos/scripts/package-app.sh`.
