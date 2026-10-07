"""flutter create ile üretilen Android projesini Arıza Takip için ayarlar.

- minSdk 23, applicationId com.arizatakip.app
- core library desugaring (flutter_local_notifications için)
- release derlemede küçültmeyi kapatır
- AndroidManifest.xml ve Kotlin dosyalarını tools/android içinden kopyalar
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "android", "app")
SRC = os.path.join(ROOT, "tools", "android")
DESUGAR = "com.android.tools:desugar_jdk_libs:2.0.4"


def fail(msg):
    print("HATA: " + msg)
    sys.exit(1)


def patch_groovy(path):
    s = open(path, encoding="utf-8").read()
    s, n = re.subn(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdk = 23", s)
    if n == 0 and "minSdk" not in s:
        s = s.replace("defaultConfig {", "defaultConfig {\n        minSdk = 23", 1)
    s = re.sub(r'applicationId\s*=?\s*"[^"]*"', 'applicationId = "com.arizatakip.app"', s)
    if "coreLibraryDesugaringEnabled" not in s:
        if "compileOptions {" not in s:
            fail("compileOptions bulunamadı")
        s = s.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
    s = re.sub(r"(buildTypes\s*\{\s*release\s*\{)", r"\1\n            minifyEnabled false\n            shrinkResources false", s, count=1)
    s += "\ndependencies {\n    coreLibraryDesugaring '" + DESUGAR + "'\n}\n"
    open(path, "w", encoding="utf-8").write(s)


def patch_kts(path):
    s = open(path, encoding="utf-8").read()
    s, n = re.subn(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", s)
    if n == 0 and "minSdk" not in s:
        s = s.replace("defaultConfig {", "defaultConfig {\n        minSdk = 23", 1)
    s = re.sub(r'applicationId\s*=\s*"[^"]*"', 'applicationId = "com.arizatakip.app"', s)
    if "isCoreLibraryDesugaringEnabled" not in s:
        if "compileOptions {" not in s:
            fail("compileOptions bulunamadı")
        s = s.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    s = re.sub(r"(buildTypes\s*\{\s*release\s*\{)", r"\1\n            isMinifyEnabled = false\n            isShrinkResources = false", s, count=1)
    s += '\ndependencies {\n    coreLibraryDesugaring("' + DESUGAR + '")\n}\n'
    open(path, "w", encoding="utf-8").write(s)


groovy = os.path.join(APP, "build.gradle")
kts = os.path.join(APP, "build.gradle.kts")
if os.path.exists(groovy):
    patch_groovy(groovy)
    print("build.gradle ayarlandı")
elif os.path.exists(kts):
    patch_kts(kts)
    print("build.gradle.kts ayarlandı")
else:
    fail("app/build.gradle bulunamadı")

# Manifest
manifest = open(os.path.join(SRC, "AndroidManifest.xml"), encoding="utf-8").read()
open(os.path.join(APP, "src", "main", "AndroidManifest.xml"), "w", encoding="utf-8").write(manifest)
print("AndroidManifest.xml kopyalandı")

# Kotlin dosyaları: üretilen MainActivity'nin paketine yazılır
found = glob.glob(os.path.join(APP, "src", "main", "**", "MainActivity.kt"), recursive=True)
if not found:
    fail("MainActivity.kt bulunamadı")
main_path = found[0]
pkg = None
for line in open(main_path, encoding="utf-8"):
    if line.startswith("package "):
        pkg = line.split()[1].strip()
        break
if not pkg:
    fail("paket adı okunamadı")
target_dir = os.path.dirname(main_path)
for name in ["MainActivity.kt", "KeepAliveService.kt", "BootReceiver.kt", "EngineHolder.kt"]:
    s = open(os.path.join(SRC, name + ".txt"), encoding="utf-8").read().replace("__PKG__", pkg)
    open(os.path.join(target_dir, name), "w", encoding="utf-8").write(s)
    print(name + " yazıldı (" + pkg + ")")
