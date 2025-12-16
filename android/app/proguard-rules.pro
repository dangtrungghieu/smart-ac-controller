# ===== VOSK JNA ProGuard Rules =====
# Keep JNA classes from being obfuscated/removed
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }

# Keep VOSK native library classes
-keep class org.vosk.** { *; }
-keepclassmembers class org.vosk.** { *; }

# Don't warn about JNA references
-dontwarn com.sun.jna.**
-dontwarn org.vosk.**
