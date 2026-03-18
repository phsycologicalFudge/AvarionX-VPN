This project uses a custom-built version of Hysteria for Android. The binaries are rebuilt with specific linker flags to satisfy Google Play’s 16 KB page-size requirement.

This guide explains how to reproduce the exact binaries used.

### 1. Clone Hysteria

```powershell
git clone https://github.com/apernet/hysteria.git
cd hysteria
```

### 2. Install build requirements

```powershell
py -3 -m pip install -r requirements.txt
```

### 3. Modify build script

Open the build script within the root of the new folder:

hyperbole.py

Then replace lines 245 - 266 with:

```python
if not env.get("CC"):
    if arch == "arm64":
        env["CC"] = ndk_bin + "/aarch64-linux-android29-clang.cmd" if os.name == "nt" else ndk_bin + "/aarch64-linux-android29-clang"
    elif arch == "armv7":
        env["CC"] = ndk_bin + "/armv7a-linux-androideabi29-clang.cmd" if os.name == "nt" else ndk_bin + "/armv7a-linux-androideabi29-clang"
    elif arch == "386":
        env["CC"] = ndk_bin + "/i686-linux-android29-clang.cmd" if os.name == "nt" else ndk_bin + "/i686-linux-android29-clang"
    elif arch == "amd64":
        env["CC"] = ndk_bin + "/x86_64-linux-android29-clang.cmd" if os.name == "nt" else ndk_bin + "/x86_64-linux-android29-clang"
    else:
        print("Unsupported arch for android: %s" % arch)
        return
```

### 4. Build Android ARM64

```powershell
$env:HY_APP_PLATFORMS = "android/arm64"
$env:CGO_ENABLED = "1"
$env:CGO_LDFLAGS = "-Wl,-z,max-page-size=16384"
$env:CC = "$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android21-clang.cmd"
$env:CXX = "$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android21-clang++.cmd"

python .\hyperbole.py build -r
```

### 5. Build Android ARMv7

```powershell
$env:HY_APP_PLATFORMS = "android/armv7"
$env:CGO_ENABLED = "1"
$env:CGO_LDFLAGS = "-Wl,-z,max-page-size=16384"
$env:CC = "$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\bin\armv7a-linux-androideabi21-clang.cmd"
$env:CXX = "$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\bin\armv7a-linux-androideabi21-clang++.cmd"

python .\hyperbole.py build -r
```

### 6. Locate compiled binaries

After building, the outputs will be in:

/build

You should find platform-specific Android binaries.

### 7. Rename and place binaries

Rename each compiled binary to:

libhysteria.so

Then place them into:

android/app/src/main/jniLibs/arm64-v8a/libhysteria.so  
android/app/src/main/jniLibs/armeabi-v7a/libhysteria.so

---

### Troubleshooting

If builds fail, verify that the python dependencies are correctly installed.
