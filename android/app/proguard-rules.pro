# ProGuard / R8 rules for VedAstro AI release builds.
#
# Without these, R8's aggressive obfuscation strips classes that
# Razorpay / Firebase / native plugins access via reflection at
# runtime — causing release-only crashes that don't happen in debug.

# ═══ Razorpay (subscription checkout) ═════════════════════════════
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes JavascriptInterface
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}
-keep class proguard.annotation.** {*;}
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
  public void onPayment*(...);
}

# Razorpay's analytics + RZP turbo SDK
-dontwarn proguard.annotation.Keep
-dontwarn proguard.annotation.KeepClassMembers

# ═══ Firebase (Auth, Firestore, Crashlytics, Core) ════════════════
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Crashlytics specifically — needs to keep stack-trace info clean for
# de-obfuscation to work on the dashboard.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep class com.google.firebase.crashlytics.** { *; }
-dontwarn com.google.firebase.crashlytics.**

# ═══ Google Sign-In ═══════════════════════════════════════════════
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ═══ Gemini / Generative AI SDK ═══════════════════════════════════
-keep class com.google.ai.client.generativeai.** { *; }
-dontwarn com.google.ai.client.generativeai.**

# ═══ Flutter / Dart core ══════════════════════════════════════════
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ═══ OkHttp / Retrofit (used by Razorpay + Firebase under the hood) ═
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**

# ═══ Kotlin coroutines ════════════════════════════════════════════
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# Suppress warnings about Java 8 features that are stubbed by R8
-dontwarn java.lang.invoke.**
