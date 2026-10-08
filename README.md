<h1 align="center">Winvoy</h1>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0--or--later-yellow?style=for-the-badge" alt="License: GPL-3.0-or-later"></a>
</p>

Winvoy runs Windows PC games on an iPhone, with no jailbreak. Games run as they
are, unmodified, inside a single iOS app.

Winvoy is a fork of **[Madeira](https://github.com/willfaust/Madeira)** by
willfaust, which does all of the heavy lifting described below. Madeira is
licensed under GPL-3.0-or-later and so is this fork; all original copyright and
licence notices are kept. The sections after "What Winvoy changes" are
Madeira's own documentation, and internal names (`madeira.cfg`, `MADEIRA_*`
settings, log tags) are unchanged.

> [!NOTE]
> Like Madeira, Winvoy is a research project. Many games start and some play
> well, but performance and compatibility vary from game to game. Expect rough
> edges.

## Tested

| | |
|---|---|
| Game | **God of War (2018)**, PC version (Steam build, with a Lua script-loader mod) |
| Device | **iPhone 15 Pro** (A17 Pro, 8 GB RAM), iOS 27.0.1 |
| Result | Boots, loads saves and plays to the first troll fight and beyond (sessions up to ~17 minutes) on the lowest settings, roughly 10-25 fps, with 2-4 s stalls while new areas stream in |
| Limits | iOS terminates the app at ~6.1 GB on an 8 GB phone, so a game this size leans on Madeira's swap file; the phone also throttles to about half CPU speed after a few minutes |

| | |
|---|---|
| Game | **X-Men Origins: Wolverine (2009)**, 32-bit DirectX 9, Unreal Engine 3 |
| Device | **iPad Air (4th generation)** (A14, 4 GB RAM), iOS 27.0.1 |
| Result | Menus and gameplay at about 20 fps |
| Needed | NVIDIA PhysX 2.8.1 runtime (see [32-bit games and PhysX](#32-bit-games-and-physx)) |

Other games are untested in Winvoy, but every change below is general and none
of them is specific to God of War or Wolverine.

## Supported iPhones

| | |
|---|---|
| **Minimum** | iPhone 15 Pro / 15 Pro Max (A17 Pro, 8 GB) and later, on iOS 26 or later |
| **Recommended** | iPhone 17 Pro / 17 Pro Max (12 GB) and later |

Memory is what decides how big a game can run: Winvoy gets roughly the phone's
RAM minus 1.5 GB before iOS terminates it (about 6.1 GB on a 15 Pro, about
10 GB on a 17 Pro). Better cooling on newer Pro models also delays thermal
throttling. Lighter and older games need much less and run far more smoothly.

Older devices can run older games: an **iPad Air 4** (A14, 4 GB) runs a
2009 32-bit game at about 20 fps. On such a device Winvoy gets about 2.8 GB of
memory, and iOS gives the app a smaller address map (454 GB instead of 512 GB),
which Winvoy now handles (see below).

## What Winvoy changes, and why

Winvoy keeps Madeira's design (FEX + Wine + DXMT in one iOS process) and changes
only what measurement on the device showed to be wrong. The fixes are on the
`winvoy` branches of the FEX, Wine and DXMT submodules.

| Problem found | What Madeira did | What Winvoy does instead | Why |
|---|---|---|---|
| x86 `lock` instructions on addresses that cross a 16-byte boundary (legal on x86, a fault on ARM) | Emulated each fault in its Mach exception handler (ml431); other atomic kinds went to FEX's handler | **FEX JIT**: every atomic (cmpxchg, xadd, xchg, add, sub, and, or, xor, neg) detects the split case inline and runs under one shared lock | The fault path cost ~8 µs per instruction (a game spun on one 120,000 times a second), and the two handlers did not exclude each other, so a cmpxchg and an xadd on the same counter could lose an update and hang a job system |
| A thread sleeping in `WaitOnAddress` while the value it waits on had already changed | Fixed one lost-wake cause by sharing the wait table between ntdll copies (ml441) | **Wine ntdll**: infinite address waits re-check every 100 ms (`alert-inf-recheck-ms`) | Windows allows spurious wakes, so callers re-check anyway; any remaining lost wake now costs 100 ms instead of a permanent hang |
| Games that create a zero-size buffer | Returned `E_INVALIDARG`, like native D3D11 | **DXMT**: an empty placeholder buffer | Apple's D3DMetal (CrossOver) accepts it; a modified God of War asset with a zero-index mesh ran under CrossOver but crashed here |
| DXMT's worker pool failing to start a thread under memory pressure | Threw a C++ exception | **DXMT**: pool growth never throws; work stays queued for existing workers | On iOS the exception cannot unwind through the JIT-pool copy of `d3d11.dll`, so it escaped as a crash |
| Per-draw dynamic buffers re-created every frame | Kept 64 recycled versions per buffer | **DXMT**: up to 2048 versions within 1 MB per buffer, 128 MB in total | Buffer reuse went from 57% to 99% and fresh allocations from ~1M to ~50k per session |
| Available memory reported to games | Device-wide free pages | **Wine ntdll**: this app's real headroom before iOS terminates it | Free pages say nothing about how close the app is to its own limit |
| A 454 GB address map (iPad Air 4): only ~5 GB above the GPU carveout, and the JIT pool's write alias sat on the one 4 GB slot a 32-bit game can use | Assumed a 512 GB or a 63 GB map | **App + Wine ntdll + FEX**: on maps that end between 452 and 456 GB, the write alias moves to a low hole (or above the slot), Wine uses the kernel's real map end, FEX's host band is the space above the slot, and the swap tier stays out of it | 32-bit games could not start at all ("no guest window", then "no FEX host arena") |
| FEX's host memory for 32-bit games ran out at ~21 threads on that map | 16 MB call-ret stack per thread, compile buffers handed between threads only after 5 s idle, 8 MB 64-bit stack per WoW64 thread | **FEX WOW64**: 64 KB call-ret stack (the shadow stack is compiled out of that module), compile buffers reusable after 250 ms; **Wine**: 1 MB 64-bit stacks for 32-bit programs (upstream Wine's size) | The loading-screen hang was a thread that could not get memory and died holding FEX's thread-creation lock; 64-bit games are unchanged |
| Building on a Mac | Scripts reconstructed from the developer's machine | **Build scripts** fixed for macOS hosts, plus helpers in `build/winvoy/` | The FEX configure, Wine headers, wineserver base archive, LLVM for iOS and DXMT shader headers were missing or failed on a clean Mac |

Settings that make heavy games fit on an 8 GB iPhone (all in `madeira.cfg`,
see "Running Winvoy on your iPhone" below) are configuration, not code changes.

## How it works

| Layer | What it does |
|---|---|
| **[FEX-Emu](https://github.com/FEX-Emu/FEX)** | Translates the game's x86 and x86-64 code to ARM64 as it runs. |
| **[Wine](https://www.winehq.org/)** 11.4 | Provides Windows. It is built for ARM64EC, so Wine itself runs natively and only the game's own code is translated. 32-bit games run through WoW64. |
| **[DXMT](https://github.com/3Shain/DXMT)** | Draws Direct3D 9, 10 and 11 with Metal. |
| **[madeira-d3d12](madeira-d3d12)** | Madeira's own Direct3D 12 implementation on Metal, converting DXIL shaders at run time with Apple's Metal Shader Converter. |

iOS apps cannot start other programs, so everything runs in one process: even
Wine's server runs as a thread instead of a separate program.

## Features

- **Game library** with artwork, search and a Windows desktop session.
- **Steam**: sign in, browse the games you own, install and update them, and
  start them through Valve's own Windows Steam client (Madeira Dock).
- **Steam Cloud saves**: saves sync with Steam Cloud when Madeira starts and
  before a game starts, and **Upload saves and close Madeira** in the game
  menu sends them when you stop playing. Saves that
  changed on both sides are never overwritten without asking, and anything a
  sync replaces is backed up.
- **Controllers**: Bluetooth controllers through XInput, plus customisable
  on-screen touch controls.
- **Keyboard, mouse and trackpad** passed through to games as real input.
- **Video and audio** for cutscenes and music, through FFmpeg, VideoToolbox and AudioToolbox.

## Running Winvoy on your iPhone

There is no prebuilt Winvoy app yet, so it is built from source with Xcode. You
need a Mac, Xcode, an Apple ID (a free one works; the app must be re-signed
every 7 days) and a supported iPhone.

### Quick install: the IPA (no Mac build)

Each [release](https://github.com/Dhinesh0906/Winvoy/releases) has an unsigned
`Winvoy-unsigned.ipa` for iPhone and iPad, built from this repository.

1. Sign and install it with SideStore, AltStore, Sideloadly or Plume.
2. Set up JIT ([docs/JIT.md](docs/JIT.md)); iOS 26 or later.
3. Add Microsoft's Visual C++ runtime (below). It is not in the IPA because
   Microsoft's licence does not allow it, and many games need it.
4. Copy a game folder into Winvoy and add its `.exe` to the library.

#### Microsoft's Visual C++ runtime DLLs

Winvoy needs these 12 x64 files, unmodified:

```
concrt140.dll   msvcp140.dll   msvcp140_1.dll   msvcp140_2.dll
msvcp140_atomic_wait.dll   msvcp140_codecvt_ids.dll   vcamp140.dll
vccorlib140.dll   vcomp140.dll   vcruntime140.dll   vcruntime140_1.dll
vcruntime140_threads.dll
```

**On Windows:** install Microsoft's
[Visual C++ Redistributable (x64)](https://aka.ms/vs/17/release/vc_redist.x64.exe)
if it is not installed already, then copy the 12 files above from
`C:\Windows\System32` into a folder (on 64-bit Windows, `System32` holds the
x64 versions).

**On a Mac:** download the same
[`vc_redist.x64.exe`](https://aka.ms/vs/17/release/vc_redist.x64.exe), then in
Terminal, in the folder you downloaded it to:

```sh
brew install cabextract
cabextract -q -d vcredist vc_redist.x64.exe
for cab in vcredist/a*; do
  cabextract -l "$cab" 2>/dev/null | grep -q 'vcruntime140.dll_amd64' && cabextract -q -d x86_64-vcruntime "$cab"
done
cd x86_64-vcruntime && for f in *_amd64; do mv "$f" "${f%_amd64}"; done && ls
```

That leaves the 12 files in `x86_64-vcruntime`.

**Then, on the iPhone or iPad:** open Winvoy once, and copy the 12 files into
**Files › On My iPhone (or iPad) › Winvoy › `x86_64-vcruntime`** (create the
folder if it is not there). From a computer, use Finder (Mac) or iTunes / the
Apple Devices app (Windows) › your device › Files › Winvoy, or AirDrop them
and move them in the Files app.

On first launch Winvoy writes starting settings sized to the device into
`madeira.cfg` (8 GB+ devices and smaller ones get different values; anything
you change later is kept). Notes:

- Big games need the **increased memory limit** entitlement. Check that
  Settings › Memory+ shows a green check after sideloading; some free-account
  sideloaders drop it.
- A free Apple account's signature lasts 7 days.

The rest of this section builds Winvoy from source on a Mac.

### 1. Install the tools

```sh
xcode-select --install                     # plus Xcode from the App Store
brew install cmake ninja meson bison flex pkgconf
curl https://sh.rustup.rs -sSf | sh && rustup target add aarch64-apple-ios
xcodebuild -downloadComponent MetalToolchain
```

### 2. Get the source

```sh
git clone --recurse-submodules https://github.com/Dhinesh0906/Winvoy.git
cd Winvoy
git -C FEX submodule update --init --recursive --depth 1
git -C dxmt submodule update --init --depth 1
git clone --depth 1 --branch VER-2-13-3 https://github.com/freetype/freetype.git research/freetype
```

### 3. Inputs that are not in the repository

- **llvm-mingw** (the Windows cross compiler): download
  `llvm-mingw-20260421-ucrt-macos-universal.tar.xz` from
  [mstorsjo/llvm-mingw](https://github.com/mstorsjo/llvm-mingw/releases/tag/20260421),
  check SHA-256 `bd85a3975723815cef28dbbd2ca2cb0c926f6b348a12a0453f39f7af273cb3f7`,
  and extract it into `toolchains/`.
- **Microsoft Visual C++ runtime** (x64): extract the twelve DLLs from
  Microsoft's `vc_redist.x64.exe` into `app/Madeira/x86_64-vcruntime/`
  (see `tools/fetch-vcruntime.md`). Microsoft's licence does not allow them in
  this repository.

### 4. Build the native libraries (once; about an hour)

```sh
bash build/gnutls-ios/build.sh
bash build/ffmpeg/build.sh
bash build/fex-ios/build.sh && cmake --build FEX/build-ios --target fmt cephes_128bit xxhash softfloat_3e JemallocLibs
bash build/fex-arm64ec/build.sh
bash build/winvoy/configure-wine-macos.sh
bash build/ntdll-unix/build.sh
bash build/win32u-unix/build.sh
bash build/freetype-ios/build.sh
bash build/winvoy/seed-wineserver-base.sh && bash build/wineserver/build.sh
bash build/winvoy/build-llvm-ios.sh                 # LLVM 15 for iOS, the long step
bash build/winvoy/gen-airconv-shaders.sh
bash build/dxmt-ios/build.sh && bash build/winvoy/combine-dxmt.sh
bash build/winvoy/configure-wine-arm64ec.sh         # only to rebuild DXMT's d3d11.dll
bash build/rppairing-ios/build.sh
bash build/stage-licenses.sh
# 32-bit games (WoW64): the i386 Windows libraries and FEX's 32-bit module
PATH=/opt/homebrew/opt/bison/bin:$PATH bash build/wine-i386/build.sh   # needs bison >= 3 (brew install bison)
bash build/fex-wow64/build.sh
```

[`docs/BUILDING.md`](docs/BUILDING.md) explains each step.

### 5. Install it on the iPhone

1. Open `app/Madeira.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, choose your team and give the app a bundle ID
   of your own (for example `com.yourname.winvoy`).
3. Connect the iPhone, select it, choose the **Debug** configuration and press
   **Run**. (Debug is the configuration that runs games.)
4. On the iPhone, trust your developer certificate in Settings › General ›
   VPN & Device Management.

### 6. First launch

1. Enable **JIT**: Winvoy uses StikDebug or its built-in StikJIT helper (with
   LocalDevVPN); see [JIT setup](docs/JIT.md). In **Settings**, **JIT** and
   **Memory+** should both show a green check.
2. Add a game: copy the game's folder to the iPhone (Files app or Finder) and add
   its `.exe` to the library.

### Settings for big games on an 8 GB iPhone

Put these in `Documents/madeira.cfg` (Files app › On My iPhone › Winvoy). They
are the settings God of War ran with on an iPhone 15 Pro:

```ini
pool = 640
vram-mb = 1024
dxmt = dxgi.forceSDR=True;d3d11.preferredMaxFrameRate=30
env.DXMT_CENSUS_THROTTLE = 1
env.DXMT_IOS_CACHE_DIR = 1
env.FEX_EXTENDEDVOLATILEMETADATA = oo2core_5_win64.dll:bink2w64.dll
swap-mb = 6144
env.MADEIRA_SWAP_COVERAGE = broad
env.MADEIRA_SWAP_MIN_KB = 64
swap-advise = 1
totalphys = 4096
vram-trim-mb = 1024
env.MADEIRA_PAD_MODE = hid
```

- `swap-*` move game memory into a file iOS does not count against its limit
  (64 KB is the most crash-resistant floor; 256 KB stutters less but crashes
  sooner).
- `vram-mb`, `totalphys` and `vram-trim-mb` make the game budget for a phone, not
  a PC.
- `env.DXMT_IOS_CACHE_DIR = 1` keeps compiled shaders between sessions.
- `dxgi.forceSDR=True` avoids a near-black picture when a game turns on HDR.
- `env.MADEIRA_PAD_MODE = hid` presents a PlayStation controller as a real
  DualSense (needed by Sony PC ports such as God of War).
- Use the lowest graphics settings in the game itself and keep the phone cool.

### Settings for a 4 GB iPad (iPad Air 4)

The settings Wolverine ran with:

```ini
pool = 768
vram-mb = 1024
swap-mb = 4096
env.MADEIRA_SWAP_COVERAGE = broad
env.MADEIRA_SWAP_MIN_KB = 64
env.MADEIRA_WOW_MIN_FREE_GB = 1
env.FEX_DISABLEL2CACHE = 1
```

- `vram-mb = 1024`: a 32-bit Direct3D 9 game reads 4096 MB as 0.
- `MADEIRA_WOW_MIN_FREE_GB = 1`: the default asks for 8 GB of address space
  left over after the 32-bit window, which this map does not have.
- `FEX_DISABLEL2CACHE = 1`: about 40 MB less address space per game thread.
- `pool` is an upper bound; on this map the app sizes the pool so both of its
  views fit in low memory.

### 32-bit games and PhysX

Many 2007-2012 games use NVIDIA PhysX 2.x and crash at start without it
(`PhysXLoader.dll` missing in the log). Its files are not in this repository.
Download NVIDIA's *PhysX System Software* from nvidia.com, unpack it on the Mac
(`7zz x PhysX_*_SystemSoftware.exe`), and copy the 32-bit files into the app's
Wine drive (`Documents/wine/drive_c`):

- `Engine/v2.8.1/PhysXCore.dll` and `Engine/v2.8.1/NxCooking.dll` (as
  `PhysXCooking.dll`) → `Program Files (x86)/NVIDIA Corporation/PhysX/Engine/v2.8.1/`
  (use the engine version the game ships, see its `NxCooking.dll` version)
- `Common/PhysXLoader.dll`, `PhysXDevice.dll`, `PhysXUpdateLoader.dll`,
  `cudart32_65.dll` → `Program Files (x86)/NVIDIA Corporation/PhysX/Common/`,
  and `cudart32_65.dll` + `PhysXDevice.dll` also next to the game's `.exe`

and add to `Documents/wine/system.reg` (with Winvoy closed):

```
[Software\\Wow6432Node\\AGEIA Technologies]
"HwSelection"="CPU"
"PhysX Version"=dword:008cdaab
"PhysXCore Path"="C:\\Program Files (x86)\\NVIDIA Corporation\\PhysX\\Engine"

[Software\\Wow6432Node\\AGEIA Technologies\\PhysX_A32_Engines]
"2.8.1"=dword:00000036
```

The game runs from its copy under `Documents/wine/drive_c`, so put game-side
files there, not in the folder you first copied to the device.

### Repository layout

| Path | Contents |
|---|---|
| [`app/`](app) | The iOS app: SwiftUI front end, Wine bridge and bundled resources |
| [`wine/`](https://github.com/willfaust/wine), [`FEX/`](https://github.com/willfaust/FEX), [`dxmt/`](https://github.com/willfaust/dxmt), [`madeira-dock/`](https://github.com/willfaust/madeira-dock) | Madeira's forks and the Steam client launcher (submodules) |
| [`madeira-d3d12/`](madeira-d3d12) | The native Direct3D 12 runtime |
| [`build/`](build) | Build scripts and iOS-side sources, one folder per component |
| [`tests/`](tests) | Host checks and x86, x86-64 and DXMT test programs |
| [`tools/`](tools) | Helper scripts |
| [`docs/`](docs) | Documentation |
| [`research/`](research) | Experiments that are not part of the app |

## Documentation

| Topic | Document |
|---|---|
| Building from a clean checkout | [`docs/BUILDING.md`](docs/BUILDING.md) |
| StikDebug and built-in JIT setup | [`docs/JIT.md`](docs/JIT.md) |
| The game library | [`docs/LIBRARY.md`](docs/LIBRARY.md) |
| Steam sign-in, library and downloads | [`docs/STEAM_SIGNIN.md`](docs/STEAM_SIGNIN.md), [`docs/STEAM_LIBRARY.md`](docs/STEAM_LIBRARY.md) |
| Steam Cloud saves | [`docs/STEAM_CLOUD.md`](docs/STEAM_CLOUD.md) |
| Madeira Dock (the Steam client) | [`docs/MADEIRA_DOCK.md`](docs/MADEIRA_DOCK.md) |
| 32-bit games (WoW64) | [`docs/WOW64.md`](docs/WOW64.md) |
| Controllers and touch controls | [`docs/CONTROLLERS.md`](docs/CONTROLLERS.md) |
| Keyboard, mouse and trackpad | [`docs/KEYBOARD_MOUSE.md`](docs/KEYBOARD_MOUSE.md) |
| Audio and video | [`docs/MEDIA.md`](docs/MEDIA.md) |
| Licensing in detail | [`docs/LICENSING.md`](docs/LICENSING.md) |

## Licensing

Madeira is licensed under **GPL-3.0-or-later** ([`LICENSE`](LICENSE)) with
the **Madeira Converter Exception** ([`LICENSE-EXCEPTION.md`](LICENSE-EXCEPTION.md)),
an additional permission that allows it to work with Apple's Metal Shader
Converter.

The projects it builds on keep their own licenses upstream, but Madeira's forks
are not all licensed the same way as their upstreams:

| Component | License |
|---|---|
| [Wine fork](https://github.com/willfaust/wine) | LGPL-2.1-or-later, like upstream Wine |
| [FEX-Emu fork](https://github.com/willfaust/FEX), [DXMT fork](https://github.com/willfaust/dxmt) | Upstream code stays MIT; Madeira's changes are GPL-3.0-or-later with the exception |
| [rpmalloc fork](https://github.com/willfaust/rpmalloc) | Upstream code stays 0BSD; Madeira's changes are GPL-3.0-or-later with the exception |
| [Madeira Dock](https://github.com/willfaust/madeira-dock) | GPL-3.0-or-later with the exception |

Anything obtained earlier under a permissive license stays available under it.
Per-component details, including GnuTLS, Nettle, GMP, FFmpeg and LLVM, are in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md); the license texts are in
[`LICENSES/`](LICENSES).

Microsoft's Visual C++ runtime DLLs are **not** distributed with Madeira. To
build with them, supply them yourself as described in
[`tools/fetch-vcruntime.md`](tools/fetch-vcruntime.md).

## Contributing

Contributions are welcome under GPL-3.0-or-later; see
[`CONTRIBUTING.md`](CONTRIBUTING.md).

Madeira's forks contain a lot of AI-assisted work. FEX-Emu does not accept
AI-generated code, so please **do not send changes from these forks upstream**
to FEX-Emu, and check each upstream project's contribution policy before
proposing anything to it.

## Credits

- **Will Faust** ([@willfaust](https://github.com/willfaust)): created Madeira
- **Nick** ([@125hz](https://github.com/125hz)): 32-bit game support, the game library and Madeira Dock
- **Jfishin** ([@Jfishin](https://github.com/Jfishin)): the original native Steam sign-in, library and downloads
- **Jesse** ([@JesseLovelace](https://github.com/JesseLovelace)): Steam Cloud saves, faster game launches, and fixes that let more games run
- **Dan Perks** ([@danperks](https://github.com/danperks)): in-app JIT without StikDebug, and pairing without a computer
- **bahacan16** ([@bahacan16](https://github.com/bahacan16)): Direct3D 12 and DXMT fixes, game launcher windows, per-game settings, PlayStation controllers, and save backups
- **spitefulowl** ([@spitefulowl](https://github.com/spitefulowl)): Wine and FEX runtime fixes, DXMT texture and memory fixes, audio, the swap tier, and library launch options
- **meshoklv** ([@meshoklv](https://github.com/meshoklv)): controller fixes for games that ship their own XInput or need focus, touch taps that stay off the mouse, and a crash-guard fix
- **TheHadesc** ([@TheHadesc](https://github.com/TheHadesc)): Madeira Dock starts for games whose Steam launch entries do not start at zero, and a touch gamepad that survives the in-game keyboard

Madeira is built on [Wine](https://www.winehq.org/), [FEX-Emu](https://github.com/FEX-Emu/FEX),
[DXMT](https://github.com/3Shain/DXMT) by Feifan He (3Shain) with the Direct3D 9
frontend by David Acevedo (dacevedo12), [rpmalloc](https://github.com/mjansson/rpmalloc)
by Mattias Jansson, [StikDebug](https://github.com/StikDebug/StikDebug),
[StikJIT](https://github.com/StikDebug/StikJIT) and
[idevice](https://github.com/jkcoxson/idevice) for enabling JIT. Thank you to everyone who contributes to them.

<p align="center">
  <a href="https://discord.gg/4t5mNjwCn7"><b>Join the community on Discord</b></a>
</p>
