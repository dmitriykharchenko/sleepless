# Sleepless

Sleepless is a macOS menu bar app for observing and manually toggling the
system-wide `SleepDisabled` power setting. It is a small control for advanced
users—not a lid-only switch, thermal safeguard, or automatic recovery service.

> **Safety:** When sleep is disabled, a Mac may remain awake with its lid closed.
> Heat can build up and the battery can drain. Keep the Mac ventilated and do
> not leave it running in a closed bag or other poorly ventilated space.

## Release downloads

Find releases on the
[Sleepless GitHub Releases page](https://github.com/dmitriykharchenko/sleepless/releases).
For `v1.0.0`, use the Apple-silicon archive
`Sleepless-v1.0.0-macos-arm64.zip` and `SHA256SUMS.txt` listed with that release.
The release page shows which assets are available. See [Install from a GitHub
release](#install-from-a-github-release) for checksum verification and setup.

## What the status means

Sleepless shows text in the menu bar and no status icon:

| Status | What macOS reported |
| --- | --- |
| `SOMNIA` | `SleepDisabled` is `0`; normal system sleep is allowed. |
| `INSOMNIA` | `SleepDisabled` is `1`; system sleep is disabled. |
| `?` | The setting could not be read or parsed reliably. |

These labels describe the observed power setting only. `SOMNIA` does not
guarantee that a Mac will sleep: other macOS settings, connected devices, or
apps may keep it awake. The setting is read on launch, every five seconds, and
after macOS wakes. Choose **Refresh Status** from the right-click menu to read it
again at any time.

## Use the menu bar control

- **Left-click** while the status is known to request the opposite setting.
  Sleepless reads the current value again first, so it does not blindly toggle
  from an outdated label.
- **Left-click when the status is `?`** only retries the read; it does not guess
  which value to write.
- **Right-click** for the current status, the last operation error (if any),
  **Refresh Status**, **About Sleepless and Safety…**, and **Quit Sleepless…**.
- While a read or change is in progress, further toggle requests are ignored
  rather than queued.

A change is made only after the user requests it. The read command is
`/usr/bin/pmset -g`. A requested change uses one of two fixed AppleScript
commands to run `/usr/bin/pmset -a disablesleep 1` or
`/usr/bin/pmset -a disablesleep 0` with administrator privileges. macOS may ask
for administrator approval or credentials. Sleepless does not collect or store
your password, and it does not construct privileged commands from user input.

After a write attempt—including a failure or cancelled authorization—the app
reads the setting again. A successful process exit by itself is not treated as
proof of success. If the read fails, the status becomes `?`; if macOS reports a
different value than requested, the observed value remains displayed and the
app reports an error. It does not keep retrying the change automatically.

## Quit and restoration

Before quitting normally, Sleepless refreshes the observed setting. If the app
requested that sleep be disabled during the current run and the setting is
still observed as disabled, it offers **Restore and Quit**, **Quit Without
Restoring**, or **Cancel**. Restoring requires an explicit choice, may require
administrator approval, and must be confirmed by another read. If restoration
cannot be verified, the app stays open so you can choose what to do next.

If Sleepless cannot verify the state after it requested no-sleep, it warns that
the setting may remain enabled and offers **Quit Without Changing** or
**Cancel**. It will not make a speculative restoration. A setting that was
already disabled before launch is not treated as Sleepless-owned and is not
automatically restored. If a refresh observes normal sleep, Sleepless gives up
its offer to restore; a later external change is not assumed to belong to the
app.

This is a current-process safeguard, not durable ownership tracking. Choosing
**Quit Without Restoring**, force-quitting, or a crash can leave sleep disabled.
The app has no crash recovery, restart recovery, thermal monitoring, automatic
overheating response, or login-time repair mechanism.

## Safety and manual recovery

Sleepless changes `disablesleep` with `pmset -a`, which applies across power
profiles. This macOS setting is undocumented and persists independently of
Sleepless. It is **not a lid-only setting**; disabling sleep can prevent normal
sleep, including sleep on lid close, depending on the Mac and macOS version.
Actual closed-lid behavior is hardware- and system-dependent and has not been
runtime-tested for this project.

If sleep is disabled after Sleepless quits, crashes, or is force-quit, reopen
the app and request normal sleep, or use Terminal to restore the system setting
for all power profiles:

```sh
sudo pmset -a disablesleep 0
```

`sudo` may ask for your administrator password in Terminal. To inspect the
reported value without changing it, run:

```sh
pmset -g | grep SleepDisabled
```

Restoring `SleepDisabled` to `0` does not override other macOS clamshell
settings, apps, or conditions that prevent sleep. Keep vents unobstructed and
avoid leaving an awake Mac in an enclosed or poorly ventilated location. The
app does not monitor temperature, battery level, or airflow and cannot protect
hardware from unsafe conditions.

## Troubleshooting

- **The menu bar shows `?`:** Left-click the text or choose **Refresh Status**
  from the right-click menu. Sleepless does not guess the setting or write a
  value when it cannot read the current state. If it persists, inspect the
  reported value with `pmset -g | grep SleepDisabled` and check the menu for a
  last-attempt error.
- **A change could not be verified:** Right-click to review the last-attempt
  error and choose **Refresh Status**. Sleepless displays the value it can
  actually read and does not retry the change automatically. If no-sleep is
  still enabled and you want normal sleep, use the manual recovery command
  above.
- **`INSOMNIA` remains after quitting:** The setting persists independently of
  the app. Verify it with `pmset -g | grep SleepDisabled`; if it is `1`, restore
  normal sleep with `sudo pmset -a disablesleep 0`.
- **The Mac stays awake while `SOMNIA` is shown:** `SleepDisabled` is only one
  power setting. Sleepless cannot identify or resolve other settings, apps, or
  conditions that may prevent sleep.

## Requirements and support limits

- `Package.swift` declares a **macOS 13.0 minimum**. That deployment target is
  build metadata, not proof of runtime compatibility: the app has not been
  runtime-tested on macOS 13.
- The `v1.0.0` release build is **Apple silicon (`arm64`) only**. No Intel or
  universal release binary is provided. A local source build is not a promise
  of support for other architectures.
- The app runs as a menu bar accessory and has no main window or Dock icon.
- The app does not install a helper, daemon, launch-at-login item, updater, or
  privileged background service.
- The power setting is undocumented; behavior may differ by hardware and macOS
  version. The physical lid-close effect and real authorization UI have not
  been verified.

## Install from a GitHub release

1. On the [Releases page](https://github.com/dmitriykharchenko/sleepless/releases),
   open `v1.0.0` and download `Sleepless-v1.0.0-macos-arm64.zip` and
   `SHA256SUMS.txt` from that same release.
2. In Terminal, change to the directory containing both files and verify the
   archive against the published checksum list:

   ```sh
   shasum -a 256 -c SHA256SUMS.txt
   ```

   Continue only if the checksum check reports success for the archive.
3. Expand the ZIP, move the included `Sleepless.app` to `/Applications`, and
   open it from Finder. Right-click the menu bar text for help and quit options.

The packaging script applies a local **ad-hoc** signature when `codesign` is
available. Ad-hoc signing is not Developer ID signing, does not identify a
publisher, and is not notarization. macOS may warn about or prevent opening a
downloaded app. Do not disable Gatekeeper globally or run an untrusted
workaround; verify the exact release and checksum and consult Apple's current
security guidance for your macOS version before making an informed choice.

## Update or uninstall

There is no automatic updater or installer. To update, quit Sleepless from its
menu, verify and extract the newer release as above, then replace
`/Applications/Sleepless.app` with the new copy. Updating or removing the app
does not reset the system-wide power setting.

To uninstall, quit the app and move `Sleepless.app` from `/Applications` to the
Trash. If Sleepless enabled no-sleep during the current run, its normal quit
flow gives you a chance to restore normal sleep. If you quit without restoring
or force-quit, use the manual recovery command above; uninstalling cannot undo a
persistent `pmset` setting.

## Build, test, and package from source

Build and test on macOS with a Swift 6 toolchain. The package declares no
third-party Swift package dependencies. From the repository root:

```sh
swift build
swift test
```

To assemble a local app bundle:

```sh
./Scripts/package-app.sh
open build/Sleepless.app
```

The packaging script builds the release executable and creates
`build/Sleepless.app`. It replaces any existing bundle at that path. It writes
`CFBundleShortVersionString` `1.0`, `CFBundleVersion` `1`, and a declared minimum
system version of `13.0`; the corresponding Git release tag is
`v1.0.0`. The script validates the bundle's property list and generated icon. If
`codesign` is available, it applies and verifies a local ad-hoc signature.
It does not Developer ID sign or notarize the app. Build outputs under
`.build/` and `build/` are ignored by Git.

The app icon is generated locally: `Scripts/render-app-icon.swift` draws a red
dot on a dark-gray gradient at the required sizes,
`Scripts/assemble-app-icon.swift` packages the representations as
`AppIcon.icns`, and `Scripts/check-app-icon.sh` checks the bundle icon and its
ten pixel sizes. The **menu bar itself uses native text without an icon**.

`swift test` runs the `SleeplessCoreTests` and `SleeplessIconTests` targets. The
power-setting tests use fake process and settings services; they do not call
`pmset` or request real administrator authorization. Icon tests exercise the
renderer, ICNS assembly, and presentation without launching the app. Passing
these checks is not a live power, authorization-dialog, UI, lid-close, or
macOS-13 runtime test.

## Project map

- [`Package.swift`](Package.swift) — Swift package, macOS deployment target,
  executable and test targets.
- [`Sources/Sleepless/main.swift`](Sources/Sleepless/main.swift) — AppKit menu
  bar lifecycle, refreshes, menus, help, and quit flow.
- [`Sources/Sleepless/StatusItemPresentation.swift`](Sources/Sleepless/StatusItemPresentation.swift)
  — text-only status label and accessibility presentation.
- [`Sources/SleeplessCore/PowerSettings.swift`](Sources/SleeplessCore/PowerSettings.swift)
  — fixed `pmset`/`osascript` operations, output parsing, and error types.
- [`Sources/SleeplessCore/SleepController.swift`](Sources/SleeplessCore/SleepController.swift)
  — serialized read/write operations, readback, and current-run restoration
  policy.
- [`Scripts/package-app.sh`](Scripts/package-app.sh) — local `.app` packaging.
- [`Scripts/render-app-icon.swift`](Scripts/render-app-icon.swift),
  [`Scripts/assemble-app-icon.swift`](Scripts/assemble-app-icon.swift), and
  [`Scripts/check-app-icon.sh`](Scripts/check-app-icon.sh) — icon creation,
  assembly, and validation.
- `Tests/SleeplessCoreTests/` and `Tests/SleeplessIconTests/` — behavior,
  presentation, and icon tests.
- `.agents/skills/canvas-design/` — retained third-party design reference
  material and its Apache license; not an app runtime dependency.

## Licensing and third-party material

No project-wide software license has been selected or included for Sleepless.
Public source visibility by itself does not grant permission to copy, modify,
or redistribute the app's source. Do not infer that a license in `.agents/`
applies to Sleepless.

The public source tree includes
[`.agents/skills/canvas-design/LICENSE.txt`](.agents/skills/canvas-design/LICENSE.txt),
which contains the Apache License 2.0 for that retained reference material
only. It does not license Sleepless. Apple Human Interface Guidelines developer
references are excluded from the public source snapshot, source archives, and
release assets; they are not app resources or Swift package dependencies.

## Verification limits

The code and tests can verify parsing, fixed command construction, observed
readback, error handling, ownership policy, presentation, and icon generation.
They cannot establish what a particular Mac will do when its lid closes, prove
that real administrator authorization succeeds, or prove runtime support on
every declared macOS version or architecture. No app launch, real
`pmset`/`osascript` operation, or live power-setting change is part of the
offline test suite.
