# Publishing MQTT Plus

This guide covers how to create releases for **MQTT Plus** using GitHub Actions via ad-hoc signing.

> [!WARNING]
> **Ad-Hoc Signing (Free Distribution)**
> This app is signed without a paid Apple Developer ID.
> **Users will see a "Developer cannot be verified" warning.**
>
> **Installation Instructions for Users:**
>
> 1. Download `MQTT Plus.dmg`
> 2. Drag to Applications
> 3. Right-click the app icon
> 4. Select **Open**
> 5. Click **Open** in the dialog

---

## Distribution Channel

| Channel | Trigger | Output |
|---------|---------|--------|
| **GitHub Releases** | Push tag `v*` (e.g., `v1.0.0`) | Ad-hoc signed DMG |

---

## Prerequisites

1. **GitHub repository** with Actions enabled
2. No Apple Developer account required!

---

## Secrets Setup

**No secrets are required!**
Since we are using ad-hoc signing (`CODE_SIGN_IDENTITY="-"`), we don't need any certificates or passwords in GitHub Secrets.

---

## Releasing

To publish a new version:

1. **Update Version**: Open Xcode and update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.

2. **Tag and Push**:

   ```bash
   git add .
   git commit -m "Bump version to 1.0.0"
   git tag v1.0.0
   git push origin v1.0.0
   ```

The workflow will automatically:

1. Build the app using ad-hoc signing
2. Create a DMG
3. Publish a GitHub Release with the DMG attached
4. Include a warning in the release notes about the Gatekeeper workaround

---

## Versioning Strategy

- **Format**: `v{MAJOR}.{MINOR}.{PATCH}`
- **Example**: `v1.0.0`

---

## Troubleshooting

### "Unidentified Developer" Warning

This is expected behavior for ad-hoc signed apps. See the warning at the top of this guide.

### Build Failures

Check the GitHub Actions logs. Common issues might includes:

- Missing dependencies (though libraries are vendored)
- Xcode version mismatches (workflow uses `latest-stable`)
