# Cassette — Lossless FLAC & ALAC Music Player for iPhone 4S (iOS 9)

A native Objective-C + CoreAudio lossless music player built specifically for **iPhone 4S (32-bit `armv7`, iOS 9.0–9.3.6, 3.5" Retina screen)** with a skeuomorphic **rolling cassette deck UI**, **24-bit/48kHz lossless FLAC & ALAC playback**, **10-band EQ**, **Spotify-style library/queue/playlists**, and an **in-app Wi-Fi song uploader**.

---

## Features

- **Bit-Accurate Lossless Audio Engine** ([`LosslessAudioEngine.m`](CassettePlayer/CassettePlayer/Audio/LosslessAudioEngine.m)):
  - **FLAC** (`.flac`): Decoded natively in C via [`dr_flac.h`](CassettePlayer/CassettePlayer/Audio/dr_flac.h) to 32-bit float PCM (16-bit & 24-bit lossless).
  - **ALAC** (`.m4a`, `.alac`, `.caf`, `.wav`, `.aiff`): Decoded via CoreAudio `ExtAudioFile` directly to 32-bit float PCM.
  - **10-Band Parametric Equalizer**: `AUGraph` + `kAudioUnitSubType_NBandEQ` with presets (*Flat (Pure)*, *Warm Cassette*, *Bass Boost*, *Vocal*, *Jazz*, *Rock*, *Acoustic*).
  - **Real-Time Analog VU Meters**: Lock-free RMS metering directly from the CoreAudio render callback.
- **Rolling Cassette Deck UI** ([`CassetteDeckView.m`](CassettePlayer/CassettePlayer/UI/CassetteDeckView.m)):
  - 60fps `CADisplayLink` spinning reels that accelerate during fast-forward/rewind/skip.
  - Supply & take-up magnetic tape spools dynamically resize based on track progress.
  - Displays track title, artist, and exact lossless quality badge (e.g. `FLAC • 24-bit / 48 kHz`).
- **Spotify-Style Library & Playback** ([`MusicLibrary.m`](CassettePlayer/CassettePlayer/Library/MusicLibrary.m), [`PlaybackManager.m`](CassettePlayer/CassettePlayer/Library/PlaybackManager.m)):
  - Browse by **Songs**, **Albums**, **Artists**, **Playlists**, and **Favorites**.
  - **Play Next**, **Add to Queue**, **Up Next** queue viewer, **Shuffle**, **Repeat (Off / All / One)**, and **Instant Search**.
  - **Lock Screen & Control Center**: `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` + background audio.
- **In-App Wi-Fi Uploader** ([`WiFiUploadServer.m`](CassettePlayer/CassettePlayer/Server/WiFiUploadServer.m)):
  - Tap **Wi-Fi Upload** in the Library tab to start an HTTP server on port `8080`, then drag & drop `.flac` / `.m4a` (ALAC) files from your Windows PC browser directly into the iPhone 4S.

---

## Step 1: Jailbreaking Your iPhone 4S (Optional, Recommended for Permanent Install)

You can install this app **without** jailbreaking (using Sideloadly with a free Apple ID, which requires re-signing every 7 days), OR **jailbreak** your iPhone 4S on iOS 9.3.5 / 9.3.6 so unsigned `.ipa` files install permanently:

1. On Windows, install **iTunes** (direct Apple download, not Microsoft Store) and **Sideloadly** (`https://sideloadly.io`).
2. Download the **Phoenix** (`Phoenix6.ipa`) or **Kok3shi9** IPA for iOS 9.3.5 / 9.3.6.
3. Connect your iPhone 4S via USB, open **Sideloadly**, drop the Phoenix/Kok3shi9 IPA, enter your Apple ID, and click **Start**.
4. On your iPhone 4S: **Settings → General → Device Management** → Trust your Apple ID → Open **Phoenix / Kok3shi9** → Tap **Prepare For Jailbreak**.
5. Once **Cydia** appears, open Cydia, add Karen's repo (`https://cydia.akemi.ai/`), and install **AppSync Unified** (this allows permanent `.ipa` installation without 7-day expiry).

---

## Step 2: Building the `.ipa` from Windows

Because Apple's iOS SDK and Xcode only run on macOS (and Xcode 14+ dropped 32-bit `armv7` support), this repo includes a GitHub Actions workflow ([`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml)) using **Xcode 13.4.1** on `macos-12` to compile a 32-bit `armv7` + `arm64` `.ipa`:

1. Push this repository to **GitHub**.
2. Go to the **Actions** tab → **Build iOS 9 CassettePlayer IPA** → **Run workflow**.
3. Download the `CassettePlayer-iOS9-IPA` artifact (`CassettePlayer-iOS9.ipa`).

*(If you have a Mac with Xcode 11–13, run `cd CassettePlayer && xcodegen generate` and build/run directly to your iPhone 4S.)*

---

## Step 3: Uploading & Installing on iPhone 4S

1. Open **Sideloadly** on Windows with your iPhone 4S connected via USB.
2. Drag `CassettePlayer-iOS9.ipa` into Sideloadly.
   - If jailbroken with **AppSync Unified**: under Advanced Options, you can use **Ad-hoc sign** or normal Apple ID sign (won't expire with AppSync).
   - If not jailbroken: enter your Apple ID and click **Start** (re-sign every 7 days).
3. Launch **Cassette** on your iPhone 4S, go to **Library → Wi-Fi Upload**, and open the shown `http://<iPhone-IP>:8080` URL on your PC browser to load your FLAC and ALAC music!
