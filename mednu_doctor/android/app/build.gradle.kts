import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing properties from key.properties (never committed to git)
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.mednu.mednu_doctor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mednu.mednu_doctor"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keyPropertiesFile.exists()) {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
            isMinifyEnabled = false
        }
        release {
            signingConfig = if (keyPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Strip unused Agora RTC extension modules (beauty/segmentation/spatial
    // audio/lip-sync/content-inspect/AV1 encoder/face detection/screen
    // capture/AV1 decoder). None of these are invoked by AgoraCallService
    // (core video/audio calling only, no screen share or AI features), so
    // they're dead weight that otherwise adds well over 100MB to the APK
    // across all ABIs.
    // NOT excluded: libagora_ai_echo_cancellation*_extension.so,
    // libagora_ai_noise_suppression*_extension.so,
    // libagora_video_quality_analyzer_extension.so,
    // libagora_video_encoder_extension.so, libagora_video_decoder_extension.so
    // — despite the "_extension" name these plausibly back core audio/video
    // call quality (echo cancellation, noise suppression, adaptive bitrate,
    // codec path) and are not gated behind an explicit API call, so removing
    // them risks breaking or degrading live calls.
    // libagora-ffmpeg.so is NOT excluded either: despite the name, it's a
    // hard runtime dependency of libagora-rtc-sdk.so itself (dlopen'd on
    // engine init, not gated behind any feature), so stripping it crashes
    // the app with UnsatisfiedLinkError the moment a call is joined.
    packaging {
        jniLibs {
            excludes += setOf(
                "**/libagora_lip_sync_extension.so",
                "**/libagora_spatial_audio_extension.so",
                "**/libagora_clear_vision_extension.so",
                "**/libagora_face_capture_extension.so",
                "**/libagora_segmentation_extension.so",
                "**/libagora_content_inspect_extension.so",
                "**/libagora_audio_beauty_extension.so",
                "**/libagora_video_av1_encoder_extension.so",
                "**/libagora_video_av1_decoder_extension.so",
                "**/libagora_face_detection_extension.so",
                "**/libagora_screen_capture_extension.so"
            )
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.multidex:multidex:2.0.1")
}
