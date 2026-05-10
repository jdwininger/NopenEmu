# 🎮 NopenEmu - Custom OpenEmu Build 🎮

A customized build of OpenEmu with enhanced audio and disc support for classic gaming! 🚀

## ✨ Features

### 🕹️ Dreamcast Support
- **Play CDI files** - Full Dreamcast disc image support via Flycast v2.6 🌀
- Smooth emulation with modern graphics rendering

### 🔊 Enhanced Sega Genesis Audio

#### 🎵 MSU-MD Support
- Play Genesis ROMs with enhanced audio tracks
- Support for `.cue` and `.bin` companion files
- Perfect for romhacks and enhanced releases

#### 🎼 MD+ Support  
- Full MP3 audio enhancement for Mega Drive games
- Automatic discovery of track files (numeric patterns, cue sheets, suffix patterns)
- YX5200 cartridge mapper support

#### 🎶 Organized Per-Game Library
- Each enhanced pack gets its own folder to prevent filename collisions
- Automatic sidecar file management (tracks, cue sheets, bin files)
- "Copy to Library" fully supported

### 🎨 Super Nintendo Entertainment System

#### 🎺 MSU-1 Audio Support
- Enhanced SNES ROM audio via MSU-1 format
- Full support for music packs with companion files
- PCM and OGG audio track support
- Automatic track discovery and fallback patterns

## 🔧 Technical Details

### Core Versions
| Component | Version | Notes |
|-----------|---------|-------|
| **SNES9x** | 1.63 | Latest stable release with MSU-1 support |
| **Genesis Plus GX** | Current (05.09.2026) | Up-to-date Mega Drive/Genesis emulation |
| **Flycast** | v2.6 | Modern Dreamcast emulator with 3D graphics |

### Build Architecture
- **macOS x86_64** - Intel Mac native build
- **Hardened Runtime** - Notarization-ready code signing
- **All Cores Bundled** - Complete set of emulators in single app bundle

## 📦 Import Features

### Smart Archive Detection
Automatically recognizes and properly unpacks:
- **MSU-1 Packs** (`.msu1` files or `.zip` with SNES ROM + audio)
- **MD+ Packs** (`.zip` with Genesis ROM + `.cue`/`.mp3` files)
- **MSU-MD Packs** (Genesis ROM + audio sidecars)

### Sidecar File Support
Automatically copies companion files for:
- `.cue`, `.m3u` - Disc descriptors
- `.bin`, `.iso`, `.img` - Disc images
- `.mp3`, `.wav`, `.flac` - Audio tracks
- `.msu`, `.pcm` - MSU-1 audio data
- `.bps`, `.ips`, `.ups` - ROM patches

## 🎯 Quick Start

1. **Import Enhanced ROMs** 📥
   - Drag MSU-1/MSU-MD/MD+ packs into OpenEmu
   - Enable "Copy to Library" for organized storage
   - Games automatically get their own folder

2. **Launch & Play** ▶️
   - Select game from library
   - Enhanced audio loads automatically
   - Enjoy your upgraded soundtrack! 🎵

3. **Dreamcast Gaming** 🌀
   - Drop CDI files into Dreamcast section
   - Flycast handles rendering with modern graphics
   - Play your favorite Dreamcast classics

## 📝 License

This is a customized build based on OpenEmu. See original project at: https://github.com/OpenEmu/OpenEmu

## 🎉 Enjoy!

With these enhancements, your classic gaming library just got a whole lot better! Whether it's enhanced Genesis soundtracks, SNES with full CD-quality music, or experiencing Dreamcast perfection on Mac—this build brings it all together. 🚀✨

Happy gaming! 🎮💫
