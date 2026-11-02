<div align="center">

<img src="https://raw.githubusercontent.com/NPP-exe/Harmony-Music/main/assets/images/header.png" onerror="this.src='https://github.com/anandnet/Harmony-Music/blob/main/cover.png'" width="100%" alt="Harmony Music Cover" />

# 🎵 Harmony Music

**A modern, cross-platform, ad-free music streaming & local audio player built with Flutter.**

[![Latest Release](https://img.shields.io/github/v/release/NPP-exe/Harmony-Music?style=for-the-badge&color=00E5FF&label=Release)](https://github.com/NPP-exe/Harmony-Music/releases/latest)
[![Web App](https://img.shields.io/badge/Web_App-Live_Demo-06B6D4?style=for-the-badge&logo=googlechrome&logoColor=white)](https://npp-exe.github.io/Harmony-Music/)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](LICENSE)
[![Translation Status](https://hosted.weblate.org/widget/harmony-music/project-translations/multi-auto.svg)](https://hosted.weblate.org/engage/harmony-music/)

---

### 🌟 Actively Maintained by [@NPP-exe](https://github.com/NPP-exe)
*Originally created by [@anandnet](https://github.com/anandnet) and enriched by community contributors.*

[**Explore Releases**](https://github.com/NPP-exe/Harmony-Music/releases/latest) • [**Web Version**](https://npp-exe.github.io/Harmony-Music/) • [**Report Bug**](https://github.com/NPP-exe/Harmony-Music/issues) • [**Translate**](https://hosted.weblate.org/projects/harmony-music/project-translations/)

---

</div>

## 📖 Overview

**Harmony Music** is an elegant, full-featured music player offering seamless online streaming from YouTube Music, Piped, and Invidious backends alongside local music playback with embedded pure Dart metadata extraction. 

Designed with an ambient neon glassmorphism UI, it gives you a clean listening experience with **zero advertisements**, **zero telemetry**, and **no mandatory account login**.

---

## ✨ Features

### 🎧 Online Streaming & Endless Discovery
* **YouTube Music & Piped Integration**: Stream millions of songs, albums, and playlists seamlessly.
* **Smart Infinite Radio**: Generate continuous, personalized radio streams from any song or artist.
* **Curated Discovery**: Quick Picks, Trending Charts, and Top Music Videos tailored to your listening habits.
* **Background Playback**: Smooth, uninterrupted background audio with system notification controls and media keys.
* **Custom Streaming Quality**: Switch between High and Low quality to conserve bandwidth or maximize audio clarity.

### 💾 Local Audio & Offline Music
* **Pure Dart Metadata Extraction**: Reads embedded ID3v2, MP4, FLAC, and Vorbis tags without native library dependencies.
* **Multi-Folder Library Scan**: Recursively scan and organize audio files from multiple custom directories.
* **Batch Multi-Select Removal**: Select and remove multiple local tracks at once with an intuitive selection mode.
* **Online Fallback for Local Tracks**: Start instant radio or retrieve extended artist/album info directly from your local songs.
* **Supported Formats**: `.mp3`, `.m4a`, `.flac`, `.wav`, `.ogg`, `.opus`, `.aac`, and `.wma`.

### 🗂️ Advanced Playlist Management & Smart Sorting
* **Order Added Sorting**: Maintain the exact order in which tracks were added using index keys.
* **Multi-Criteria Sorting**: Sort by Title, Artist, Album, Duration, or Custom Drag-and-Drop Position.
* **Per-Playlist Preference Memory**: Each playlist remembers its unique sort mode independently.
* **Export & Import**: Backup or share playlists easily in **JSON** or **CSV** formats.
* **Piped Sync & Blacklist**: Synchronize your cloud playlists bidirectionally or blacklist specific lists.

### 📝 Synchronized & Plain Lyrics
* **Real-time Karaoke Lyrics**: Powered by [LRCLIB](https://lrclib.net) with millisecond-accurate synchronized highlighting.
* **Offline Caching**: Lyrics are cached automatically for instant offline access.
* **Manual Search Fallback**: Search and align lyrics manually if a song tag differs.

### 🎨 Ambient Neon Glassmorphism UI
* **Frosted Glass Cards**: Built with 22px Gaussian backdrop blur, luminous border highlights, and specular reflections.
* **Dynamic Artwork Theming**: Accent colors adapt in real-time to the currently playing song artwork.
* **Custom Typography**: Stylized branding featuring Slicey Heallow, Bastliga One, and Rafika typefaces.
* **Responsive Layout**: Adapts dynamically across platforms—responsive Side Navigation Rail on desktop/tablets and smooth Bottom Navigation on mobile.

### 🛡️ Transactional Backup & Data Safety
* **Two-Phase Journal Engine**: Settings and playlist backups execute with rollback protection to prevent corruption.
* **Zero Account Lock-in**: Full portability—export and restore your entire library whenever you wish.

### 🎛️ Audio Engine & Power Controls
* **Dual Audio Architecture**: High-fidelity `just_audio` on mobile/web and robust `media_kit` (mpv-backed) on Windows and Linux.
* **Sleep Timer**: Set automatic stop timers before going to bed.
* **Silence Skipping & Loudness Normalization**: Smooth transitions between varied audio mastering levels.
* **Car & Desktop Integration**: Supports Android Auto on mobile and MPRIS media control on Linux.

---

## 🚀 Platforms & Installation

Harmony Music is built to run everywhere with dedicated optimizations for each target platform:

| Platform | Format / Source | Installation / Status |
| :--- | :--- | :--- |
| **Android** | `.apk` (Universal, arm64-v8a, armeabi-v7a, x86_64) | [Download from Latest Releases](https://github.com/NPP-exe/Harmony-Music/releases/latest) |
| **Windows** | `.exe` (Installer & Portable) | [Download from Latest Releases](https://github.com/NPP-exe/Harmony-Music/releases/latest) |
| **Linux** | `.deb`, `.rpm`, Binary | [Download from Latest Releases](https://github.com/NPP-exe/Harmony-Music/releases/latest) |
| **Nix / NixOS** | Flake Package & Dev Shell | `nix run github:NPP-exe/Harmony-Music` |
| **Web** | Online & Local Offline Bundle | [Launch Live Web App](https://npp-exe.github.io/Harmony-Music/) |
| **macOS / iOS** | Native App Bundles | Build via Flutter toolchain |

### ❄️ Nix (Linux x86_64)
Run or package Harmony Music with Nix flakes enabled:

```sh
# Run the pinned stable release
nix run github:NPP-exe/Harmony-Music

# Build the package locally
nix build github:NPP-exe/Harmony-Music

# Launch development shell
nix develop github:NPP-exe/Harmony-Music
flutter run
```
*For NixOS and Home Manager modules, refer to [nix/README.md](nix/README.md).*

### 🌐 Web & Local Web Bundle
* **Live Web App**: Visit [https://npp-exe.github.io/Harmony-Music/](https://npp-exe.github.io/Harmony-Music/) directly in your browser.
* **Offline Local Web Bundle**: Download `harmonymusic-web-local.zip` from workflow artifacts or releases. Run `run-local.bat` (Windows) or `sh run-local.sh` (macOS/Linux) to start a lightweight zero-dependency local server at `http://127.0.0.1:8000`.

---

## 🌐 Translations

Harmony Music supports multiple languages thanks to contributors worldwide.

<div align="center">

[![Weblate Translation](https://hosted.weblate.org/widget/harmony-music/project-translations/multi-auto.svg)](https://hosted.weblate.org/engage/harmony-music/)

Help translate Harmony Music into your language on [Weblate](https://hosted.weblate.org/projects/harmony-music/project-translations/)!

</div>

---

## 🛠️ Troubleshooting

* **Playback stops when screen turns off (Android)**: 
  Disable battery optimizations for Harmony Music in `Settings -> Miscellaneous -> Ignore Battery Optimization` or in your Android device settings.
* **Notification Controls Missing (Android 13+)**:
  Ensure notification permissions are granted in device settings.
* **Windows Audio Output**:
  If audio does not initialize, ensure the latest Visual C++ Redistributable is installed on your Windows machine.

---

## 🤝 Maintainers & Credits

### Maintainer & Lead
* **[@NPP-exe](https://github.com/NPP-exe)** — Project maintainer, feature development, UI/UX refactoring, and release management.

### Original Creator
* **[@anandnet](https://github.com/anandnet)** — Original creator of Harmony Music.

### Community Contributors
Special thanks to everyone contributing code, bug reports, and maintenance improvements:
* **[@BandhanPramanik](https://github.com/BandhanPramanik)**
* **[@Meralchen](https://github.com/Meralchen)**
* **[@theblackcoderbr](https://github.com/theblackcoderbr)**
* **[@jaxenisr](https://github.com/jaxenisr)**
* ...and all of our beta testers and Weblate translators!

### Key Open-Source Libraries
* [just_audio](https://pub.dev/packages/just_audio) & [media_kit](https://pub.dev/packages/media_kit) — Audio engines
* [audio_service](https://pub.dev/packages/audio_service) — Background audio lifecycle
* [GetX](https://pub.dev/packages/get) — State and dependency management
* [Hive](https://pub.dev/packages/hive) — Fast, lightweight local database
* [LRCLIB](https://lrclib.net) — Synchronized lyrics provider
* [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart) — Stream resolving

---

## 📄 License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.
* Copies and modifications cannot be used for non-free or commercial purposes.
* Modified or copied versions may not be distributed on closed-source app stores (Play Store, App Store).

See the [LICENSE](LICENSE) file for the complete terms.

---

## ⚠️ Disclaimer

This project is created for educational and learning purposes. It is not affiliated with, sponsored by, or endorsed by Google, YouTube, or any content providers. All songs, artwork, and trademarks are the intellectual property of their respective owners. Harmony Music is distributed "as-is" without warranty of any kind.
