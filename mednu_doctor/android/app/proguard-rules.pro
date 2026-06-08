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

# ── Agora RTC ────────────────────────────────────────────────────────────────
-keep class io.agora.** { *; }
-dontwarn io.agora.**

# ── Geolocator ──────────────────────────────────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }

# ── Image Picker / File Picker ───────────────────────────────────────────────
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# ── Foreground Task ──────────────────────────────────────────────────────────
-keep class com.pravera.flutter_foreground_task.** { *; }

# ── Local Notifications ───────────────────────────────────────────────────────
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# ── Permission handler ───────────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }

# ── Local Auth (biometrics) ──────────────────────────────────────────────────
-keep class io.flutter.plugins.localauth.** { *; }

# ── Kotlin coroutines ────────────────────────────────────────────────────────
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# ── OkHttp / Retrofit (used by Firebase internally) ─────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**

# ── JSON serialization ────────────────────────────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

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
    java.lang.Object readReplace();
    java.lang.Object readResolve();
}

# ── Play Core ────────────────────────────────────────────────────────────────
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
