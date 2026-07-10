# ─── Flutter ───────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.engine.** { *; }

# Plugin registrant generado (contiene registerWith de todos los plugins)
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# ─── NFC Manager plugin ───────────────────────────────────────
-keep class im.nfc.nfc_manager.** { *; }
-keep class im.nfc.** { *; }
-keep class com.nfc.manager.** { *; }
-dontwarn im.nfc.**
-dontwarn com.nfc.manager.**

# ─── Android NFC ──────────────────────────────────────────────
-keep class android.nfc.** { *; }
-keep class android.nfc.cardemulation.** { *; }
-dontwarn android.nfc.**

# ─── Android BLE ──────────────────────────────────────────────
-keep class android.bluetooth.** { *; }
-keep class android.bluetooth.le.** { *; }
-dontwarn android.bluetooth.**

# ─── Nuestra app ──────────────────────────────────────────────
-keep class com.monopoly.monopoly_banking.** { *; }

# ─── Reemplazar strings codec y charset (HceService) ─────────
-keep class java.nio.charset.** { *; }
-keep class kotlin.text.Charsets { *; }
-keep class kotlin.text.CharsetsKt { *; }

# ─── Kotlin coroutines (usadas por BleServer) ─────────────────
-keepnames class kotlinx.coroutines.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# ─── Kotlin reflection / MethodChannel ────────────────────────
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes Signature
-keepattributes Exceptions
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeInvisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations
-keepattributes RuntimeInvisibleParameterAnnotations

-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

-keepclassmembers class com.monopoly.monopoly_banking.MainActivity {
    native <methods>;
}

# Mantener todos los handlers de MethodChannel
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keep class * implements io.flutter.plugin.common.MethodChannel$Result { *; }

# Reactive BLE plugin
-keep class com.signify.hue.** { *; }
-keep class com.polidea.** { *; }
-dontwarn com.signify.**
-dontwarn com.polidea.**

# ─── Evitar eliminar campos accedidos por reflection ─────────
-keepclassmembers class * {
    *** *Field*;
}
