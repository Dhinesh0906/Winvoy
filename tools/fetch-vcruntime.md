# Obtaining the Microsoft Visual C++ runtime DLLs

Games built with MSVC need the Visual C++ runtime. Those DLLs are authored by
Microsoft and are **not** redistributable under this project's license, so they
are not committed here. You supply them yourself.

Twelve files are expected in `app/Madeira/x86_64-vcruntime/`:

```
concrt140.dll              msvcp140_codecvt_ids.dll   vcruntime140.dll
msvcp140.dll               vcamp140.dll               vcruntime140_1.dll
msvcp140_1.dll             vccorlib140.dll            vcruntime140_threads.dll
msvcp140_2.dll             vcomp140.dll
msvcp140_atomic_wait.dll
```

## How to get them

Download the official x64 redistributable from Microsoft
(`VC_redist.x64.exe`, https://aka.ms/vs/17/release/vc_redist.x64.exe).

On Windows, install it and copy the twelve files above from
`C:\Windows\System32`.

On macOS, the x64 DLLs are in one of the installer's embedded cabinets, named
`<file>_amd64`:

```sh
brew install cabextract
cabextract -q -d /tmp/vcredist VC_redist.x64.exe
for cab in /tmp/vcredist/a*; do
  cabextract -l "$cab" 2>/dev/null | grep -q 'vcruntime140.dll_amd64' && \
    cabextract -q -d app/Madeira/x86_64-vcruntime "$cab"
done
(cd app/Madeira/x86_64-vcruntime && for f in *_amd64; do mv "$f" "${f%_amd64}"; done)
```

Checked against the 2025 redistributable (14.44). For an installed IPA, copy
the files into Files › Winvoy › `x86_64-vcruntime` instead; the app uses that
folder when its bundle has none.

## Do not modify them

Microsoft's redistribution permission covers the eligible files *unmodified*.
In particular, do not strip Authenticode signatures. You can check that a file
still carries its signature payload:

```sh
python3 - app/Madeira/x86_64-vcruntime/*.dll <<'EOF'
import struct, sys
for path in sys.argv[1:]:
    d = open(path, 'rb').read()
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    off, size = struct.unpack_from('<II', d, pe + 24 + 112 + 4*8)
    ok = size and off + size <= len(d)
    print(('signed  ' if ok else 'UNSIGNED'), path)
EOF
```

A file whose certificate offset equals its own length has had the signature
truncated off and is no longer an unmodified Microsoft binary.
