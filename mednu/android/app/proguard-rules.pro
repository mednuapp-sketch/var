# ── Flutter engine ──────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# ── Firebase Core & Auth ────────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.firebase.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ── Firestore ───────────────────────────────────────────────────────────────
-keep class com.google.firestore.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# ── Firebase Cloud Messaging ────────────────────────────────────────────────
-keep class com.google.firebase.messaging.** { *; }

# ── Firebase Analytics ──────────────────────────────────────────────────────
-keep class com.google.android.datatransport.** { *; }

# ── Razorpay ────────────────────────────────────────────────────────────────
-keepattributes *Annotation*
-keep class com.razorpay.** { *; }
-keep interface com.razorpay.** { *; }
-dontwarn com.razorpay.**
-optimizations !method/inlining/*

# ── Agora RTC ────────────────────────────────────────────────────────────────
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# ── Google Maps ─────────────────────────────────────────────────────────────
-keep class com.google.maps.** { *; }
-keep class com.google.android.libraries.maps.** { *; }

# ── Geolocator ──────────────────────────────────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }

# ── Image Picker / File Picker ───────────────────────────────────────────────
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# ── WorkManager (background tasks) ──────────────────────────────────────────
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# ── Local Auth (biometrics) ──────────────────────────────────────────────────
-keep class io.flutter.plugins.localauth.** { *; }

# ── Secure Storage ───────────────────────────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# ── Health plugin ────────────────────────────────────────────────────────────
-keep class cachet.flutter.health.** { *; }

# ── Permission handler ───────────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }

# ── Notification plugins ─────────────────────────────────────────────────────
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# ── Kotlin coroutines ────────────────────────────────────────────────────────
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# ── JSON serialization (Dart/Flutter bridge) ─────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# ── OkHttp / Retrofit (used by Firebase internally) ─────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**

# ── Smart Auth (deprecated Google Smart Lock — keep to avoid build warnings) ─
-dontwarn com.google.android.gms.auth.api.credentials.**

# ── Play Core (deferred components — app doesn't use them) ──────────────────
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ── Enum names (required for reflection-based libraries) ────────────────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ── Parcelable ───────────────────────────────────────────────────────────────
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# ── Serializable ─────────────────────────────────────────────────────────────
-keepclassmembers class * implements java.io.Serializable {
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
