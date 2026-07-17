# WakeGuard — Complete Setup Guide (Zero to Running)

This guide assumes **you have nothing installed** and **you have never written or run code before**. Follow it top to bottom. Copy each command exactly, paste it into the Terminal, press **Return**, and wait for it to finish before moving to the next one.

If a step says "this can take 10–40 minutes," that is normal — big tools are downloading. Do not close the Terminal while something is running.

---

## 0. What you are setting up

- **WakeGuard** is a phone app (the folder `smart_ble_alarm/`) built with **Flutter** (a coding toolkit made by Google).
- The app is an alarm clock that talks to a physical Arduino clock over **Bluetooth**.
- To run the app you need: **Git** (downloads the code), **Flutter** (builds/runs the app), and at least one place to run it — an **iPhone Simulator**, an **Android Emulator**, or a **real phone**.
- **Good news:** the Firebase login/cloud files are already included in the code, so you do **not** need to set up any accounts or servers. You only install tools and press "run."

### Two important facts before you start

1. **Bluetooth does NOT work on simulators/emulators.** The app will *open and run* on a simulator so you can see the screens, but to actually connect to the Arduino clock you must use a **real phone**. (This is a limitation of Apple/Google, not the app.)
2. **iPhone building requires a Mac.** Windows/Linux can only build the **Android** version. This guide's main path is **macOS** (which can do both). A Windows-only Android path is in the [Appendix](#appendix-windows-android-only).

---

## 1. Open the Terminal (macOS)

The **Terminal** is a text window where you type commands.

1. Press `Command (⌘)` + `Space` to open Spotlight search.
2. Type `Terminal`
3. Press `Return`.

A window opens with a blinking cursor. This is where every command below goes. To run a command: click the code block, copy it, paste into Terminal, press `Return`.

> Tip: If a command asks for your password, type your Mac login password. **The screen will not show anything as you type — that is normal.** Type it and press `Return`.

---

## 2. Install Apple's Command Line Tools

These provide `git` basics and compilers the other tools need.

```bash
xcode-select --install
```

A popup appears — click **Install**, then **Agree**. Wait for it to finish (can take 10–20 min). If you see `command line tools are already installed`, that's fine — move on.

---

## 3. Install Homebrew (the app installer for Mac)

Homebrew lets you install other tools with one command each.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

- It will ask for your password (type it, press Return — remember, it stays invisible).
- Wait for `Installation successful!`.

Now tell your Terminal where Homebrew lives. **Apple Silicon Macs (M1/M2/M3/M4)** — run these two lines:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Check it worked:

```bash
brew --version
```

You should see something like `Homebrew 4.x.x`. If you see `command not found`, close the Terminal, reopen it (Step 1), and run `brew --version` again.

---

## 4. Install Git and configure your identity

```bash
brew install git
```

Then set your name and email (used to label any code changes you make). Replace the example values with your own:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

Verify:

```bash
git --version
```

You should see `git version 2.x.x`.

---

## 5. Install Rosetta (Apple Silicon Macs only — required)

This app uses Google's ML Kit, which needs Rosetta to build for the iPhone Simulator. Skip this only if you have an old Intel Mac.

```bash
softwareupdate --install-rosetta --agree-to-license
```

Wait for `Install of Rosetta 2 finished successfully` (or a message that it's already installed).

---

## 6. Install Flutter (the toolkit that runs the app)

We install Flutter by downloading it with Git into your home folder.

```bash
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
```

This downloads ~1 GB and can take 5–15 min. Wait for the cursor to return.

Now make the `flutter` command usable everywhere by adding it to your PATH:

```bash
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc
```

Reload your Terminal settings so the change takes effect now:

```bash
source ~/.zshrc
```

Check Flutter is found (this first run downloads a bit more and can take a few minutes):

```bash
flutter --version
```

You should see a Flutter version and `channel stable`. If you get `command not found`, close and reopen the Terminal, then try again.

> This project requires the Dart SDK version `^3.12.0`, which the current Flutter **stable** channel provides. Installing stable (as above) is correct. If `flutter pub get` later complains the SDK is too old, run `flutter upgrade`.

---

## 7. Install Xcode (needed for iPhone building)

> Skip Steps 7–8 if you **only** want to run on Android. But Xcode is required for any iPhone/iOS work.

1. Open the **App Store** (Command+Space → type `App Store` → Return).
2. Search for **Xcode**, click **Get / Install**. **This is a very large download (7+ GB) — expect 30–90 min.**
3. When done, run these commands to point the tools at Xcode and accept its license:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

4. Install the iOS platform support:

```bash
xcodebuild -downloadPlatform iOS
```

### Install CocoaPods (manages iPhone code libraries)

```bash
brew install cocoapods
```

Verify:

```bash
pod --version
```

---

## 8. Install Android Studio (needed for Android building)

> Skip this if you **only** want to run on iPhone. Required for any Android work.

1. Download it with Homebrew:

```bash
brew install --cask android-studio
```

2. Open **Android Studio** (Command+Space → `Android Studio` → Return).
3. On first launch a **Setup Wizard** appears. Click **Next** through it and choose **Standard** installation. It downloads the Android SDK and an emulator — click **Finish** and let it complete (10–30 min).
4. Once the wizard finishes, tell Flutter to accept the Android licenses. Run this and press `y` + Return each time it asks:

```bash
flutter doctor --android-licenses
```

---

## 9. Install a code editor (VS Code) — recommended

You can run everything from the Terminal, but an editor makes it easier to read the code and click "run."

```bash
brew install --cask visual-studio-code
```

Then install the Flutter extension (adds run buttons and error highlighting):

```bash
code --install-extension Dart-Code.flutter
```

If `code` is `command not found`: open VS Code manually, press `Command+Shift+P`, type `Shell Command: Install 'code' command in PATH`, press Return, then re-run the line above.

---

## 10. Check everything is installed correctly

Run Flutter's built-in health check:

```bash
flutter doctor
```

You want **check marks (✓)** next to:
- Flutter
- Android toolchain (if you did Step 8)
- Xcode (if you did Step 7)
- Connected device / VS Code

An **[!]** with "cannot find connected devices" is normal until you start a simulator (next steps). Warnings about "Android Studio not installed" only matter if you plan to build Android. If `flutter doctor` prints a specific fix command, run it, then run `flutter doctor` again.

---

## 11. Download the WakeGuard code

Pick a folder for your projects and download the code into it:

```bash
mkdir -p ~/development
cd ~/development
git clone https://github.com/unfound-2/WakeGuard.git
```

If it asks you to sign in to GitHub, this is a **private repository** — you'll need access from the project owner. Enter the GitHub username and, for the password, a **Personal Access Token** (not your normal password). If you don't have access yet, ask the owner to add you.

Now move into the app folder (**this exact folder is important** — the app is in the `smart_ble_alarm` subfolder, not the top level):

```bash
cd ~/development/WakeGuard/smart_ble_alarm
```

Download the app's code libraries:

```bash
flutter pub get
```

Wait for `Got dependencies!`.

> **Every command from here on must be run from inside `~/development/WakeGuard/smart_ble_alarm`.** If you open a new Terminal, run `cd ~/development/WakeGuard/smart_ble_alarm` first.

---

## 12. Run the app on an iPhone Simulator (Mac only)

1. Start the iPhone Simulator:

```bash
open -a Simulator
```

A fake iPhone appears on your screen. Wait until it fully boots to the home screen.

2. Confirm Flutter sees it:

```bash
flutter devices
```

You should see an entry like `iPhone 15 (mobile)`.

3. Run the app:

```bash
flutter run
```

If more than one device is listed, Flutter asks which one — type the number for the iPhone and press Return. The first build takes several minutes. The app then launches inside the simulator.

**While `flutter run` is active**, press these keys in the Terminal:
- `r` = hot reload (apply code changes instantly)
- `R` = hot restart (full restart)
- `q` = quit the app

> Reminder: Bluetooth features won't work in the simulator — but you can see and navigate all the screens.

---

## 13. Run the app on an Android Emulator

1. Open **Android Studio** → on the welcome screen click **More Actions** → **Virtual Device Manager** → **Create Device** → pick e.g. **Pixel 7** → **Next** → download a system image (e.g. the latest, click the download arrow) → **Finish**.
2. Press the **▶ (play)** button next to your new virtual device to start it. Wait for the fake Android phone to boot.
3. Back in the Terminal (inside `smart_ble_alarm`):

```bash
flutter devices
```

You should see an Android emulator listed. Then:

```bash
flutter run
```

Same hot-reload keys apply (`r`, `R`, `q`).

---

## 14. Run on your OWN iPhone (real Bluetooth works here)

You need: an iPhone, its charging cable, and a free **Apple ID**.

1. Plug the iPhone into the Mac with a cable.
2. On the iPhone: tap **Trust This Computer** and enter your passcode.
3. Turn on Developer Mode: on the iPhone go to **Settings → Privacy & Security → Developer Mode → On**, then restart the iPhone when prompted.
4. Register your Apple ID as a free signing account:
   - Open the project in Xcode: from the Terminal (inside `smart_ble_alarm`) run

     ```bash
     open ios/Runner.xcworkspace
     ```
   - In Xcode's left sidebar click the top **Runner**, select the **Runner** target, go to **Signing & Capabilities**.
   - Under **Team**, click **Add an Account…**, sign in with your Apple ID, then pick your name as the Team. If it shows a "bundle identifier" error, change the **Bundle Identifier** to something unique (e.g. add your initials on the end) and try again.
5. Back in the Terminal (inside `smart_ble_alarm`):

```bash
flutter devices
```

Your iPhone should appear by name. Then:

```bash
flutter run
```

6. The first time, the app is blocked as "untrusted." On the iPhone go to **Settings → General → VPN & Device Management**, tap your Apple ID, tap **Trust**. Re-run `flutter run`.

> A free Apple ID lets the app run for 7 days before you must re-run `flutter run` to renew it. That's fine for testing.

---

## 15. Run on your OWN Android phone (real Bluetooth works here)

1. On the phone: go to **Settings → About phone** and tap **Build number** seven times until it says "You are now a developer."
2. Go to **Settings → System → Developer options** and turn on **USB debugging**.
3. Plug the phone into the computer with a cable. On the phone, tap **Allow** for USB debugging.
4. In the Terminal (inside `smart_ble_alarm`):

```bash
flutter devices
```

Your phone should appear by name. Then:

```bash
flutter run
```

If the phone doesn't show up, unplug/replug the cable and make sure you tapped **Allow** on the phone.

---

## 16. Everyday commands cheat sheet

Always run these from inside `~/development/WakeGuard/smart_ble_alarm`.

| What you want to do | Command |
|---|---|
| Go to the app folder | `cd ~/development/WakeGuard/smart_ble_alarm` |
| Download/refresh code libraries | `flutter pub get` |
| See connected phones/simulators | `flutter devices` |
| Run the app (asks which device) | `flutter run` |
| Run on a specific device | `flutter run -d <device-id-from-flutter-devices>` |
| Check your setup is healthy | `flutter doctor` |
| Get the latest code changes | `git pull` |
| Clean out old build files (fixes weird errors) | `flutter clean` then `flutter pub get` |
| Build a release Android app file | `flutter build apk` |
| Quit a running app | press `q` in the Terminal |

---

## 17. Troubleshooting

**`command not found: flutter` (or `brew`, or `git`)**
Close the Terminal completely and reopen it. If still broken, re-run the `echo '... >> ~/.zshrc'` / `~/.zprofile` line for that tool from its install step, then `source ~/.zshrc`.

**`flutter run` fails with pod / CocoaPods errors (iPhone)**
Run:
```bash
cd ios
pod install --repo-update
cd ..
flutter clean
flutter pub get
flutter run
```

**iPhone Simulator build fails mentioning `MLImage` / `arm64` / ML Kit**
Make sure Rosetta is installed (Step 5). This project is already configured to build the simulator under x86_64; if it still fails, run `flutter clean`, then `cd ios && pod install --repo-update && cd ..`, then `flutter run` again.

**"No devices found"**
Start a simulator/emulator first (Steps 12–13) or plug in a real phone (Steps 14–15), then re-run `flutter devices`.

**Android build fails on licenses**
Run `flutter doctor --android-licenses` and press `y` + Return for each prompt.

**Everything is weird / stale after pulling new code**
```bash
flutter clean
flutter pub get
flutter run
```

**Bluetooth won't connect**
Expected on simulators/emulators — Bluetooth only works on a **real phone** (Steps 14–15). Also make sure the phone's Bluetooth is ON and you granted the app Bluetooth + Location permissions when it asked.

---

## Appendix: Windows (Android only)

Windows cannot build for iPhone, but it can run the Android version. Quick outline:

1. Install **Git for Windows**: download from <https://git-scm.com/download/win> and run the installer (accept defaults).
2. Install **Flutter**: follow <https://docs.flutter.dev/get-started/install/windows> — download the Flutter zip, extract to `C:\src\flutter`, and add `C:\src\flutter\bin` to your PATH via **Edit environment variables for your account**.
3. Install **Android Studio** from <https://developer.android.com/studio>, run its Setup Wizard (Standard), then run `flutter doctor --android-licenses` in a new **PowerShell** window and accept all.
4. Verify with `flutter doctor`.
5. Get the code:
   ```powershell
   git clone https://github.com/unfound-2/WakeGuard.git
   cd WakeGuard\smart_ble_alarm
   flutter pub get
   ```
6. Start an Android emulator (Android Studio → Virtual Device Manager) or plug in a real Android phone with **USB debugging** on (Step 15), then:
   ```powershell
   flutter run
   ```

All the everyday commands in Section 16 work the same on Windows (use `cd WakeGuard\smart_ble_alarm`).
