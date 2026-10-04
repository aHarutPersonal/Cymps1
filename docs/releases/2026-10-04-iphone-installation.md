# CMPYS physical iPhone installation — 4 October 2026

The owner explicitly changed the earlier deferral and requested installation on the connected iPhone. Localization and production email remain deferred; neither was configured during this step.

## Build and signature

- Application source: integrated commit `8494984`.
- Version/build: `1.0.0 (1)`, release configuration, same bundle identity as the already installed CMPYS app.
- Signed using the existing automatic Apple development team and available development identity. No account/team change or subscription purchase.
- Xcode build succeeded in 46.7 seconds; signed app size 26.9 MB.
- Deep/strict signature verification passed. App identity, team and debug entitlement matched the embedded provisioning profile; the connected device was included in the profile.
- Compiled App.framework code SHA-256: `dd995192a85d94230e98ef2e72d1b592b4cf71f8830f81371be5ba7e4798fcca`.
- Development provisioning expires **11 October 2026, 19:49:41 Asia/Yerevan**. This is a development installation, not an App Store distribution build; it will need renewal/reinstallation when the profile expires.

## Confirmed on the physical device

The iPhone was available over USB, paired, with Developer Mode enabled. The existing app identity was checked before installation. The signed app was installed in place successfully; no uninstall, data wipe, logout or password reset was performed.

The first launch was blocked by iOS's developer-profile trust gate. Signature/profile checks were consistent. After the owner explicitly confirmed trusting the profile, CoreDevice launched the app at approximately **19:53:19 Asia/Yerevan**. The same app process was still present at **19:54:08** and **19:55:29**. This confirms successful native launch and survival for over two minutes, not a full functional acceptance test.

The installed source defaults to HTTPS. Its public HTTPS backend readiness check succeeded with normal certificate validation. Around launch, server logs contained a successful profile request; this is supporting timing evidence, not an independently attributed physical-device TLS trace.

## Scope of verification

No direct phone-screen control was available in the exposed tools. Therefore questionnaire completion, new-plan creation, week/lesson navigation, practice submission, comparison interaction, audible playback and word-highlight perception were **not newly verified on the physical phone**. Earlier simulator/native and unit results remain separate evidence and are not presented as physical-device results. User data was not changed to manufacture these checks.

The owner can now open the app normally and check the existing plan/lesson and listening controls. Real recovery-email delivery remains unavailable until a sender/service is connected. No localization or SES setup was started.
