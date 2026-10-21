import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("rust")
}

val tauriProperties = Properties().apply {
    val propFile = file("tauri.properties")
    if (propFile.exists()) {
        propFile.inputStream().use { load(it) }
    }
}

// Signing credentials live ONLY in Admin-Manual (public repo). The gitignored
// root .env carries the pointer SAM_KEYSTORE_PROPERTIES; read it in place —
// never copy the properties file into this tree.
fun keystorePointer(): String? {
    System.getenv("SAM_KEYSTORE_PROPERTIES")?.takeIf { it.isNotBlank() }?.let { return it }
    val envFile = file("../../../../.env")
    if (!envFile.exists()) return null
    return envFile.readLines()
        .map { it.trim() }
        .firstOrNull { it.startsWith("SAM_KEYSTORE_PROPERTIES=") }
        ?.substringAfter("=")?.trim()?.trim('"', '\'')
}

val keystoreProperties = Properties().apply {
    val pointer = keystorePointer()?.replaceFirst(Regex("^~"), System.getProperty("user.home"))
    val propFile = if (pointer != null) file(pointer) else file("../keystore.properties")
    if (propFile.exists()) {
        propFile.inputStream().use { load(it) }
        // A relative storeFile resolves beside its properties file (Admin-Manual
        // layout), falling back to the bare filename in that directory.
        getProperty("storeFile")?.let { sf ->
            if (!File(sf).isAbsolute) {
                val dir = propFile.absoluteFile.parentFile
                val candidate = File(dir, sf).takeIf { it.exists() } ?: File(dir, File(sf).name)
                setProperty("storeFile", candidate.absolutePath)
            }
        }
    }
}

base {
    // Every artifact filename must be self-identifying: product + stamped version.
    // Never Gradle's default "app-universal-release.*". Drives APK and AAB output names.
    archivesName.set("standroidsmissal-v" + tauriProperties.getProperty("tauri.android.versionName", "0.0"))
}

android {
    compileSdk = 36
    namespace = "mba.robin.helloword"
    defaultConfig {
        manifestPlaceholders["usesCleartextTraffic"] = "false"
        applicationId = "mba.robin.helloword"
        minSdk = 24
        targetSdk = 36
        versionCode = tauriProperties.getProperty("tauri.android.versionCode", "1").toInt()
        versionName = tauriProperties.getProperty("tauri.android.versionName", "1.0")
    }
    signingConfigs {
        create("release") {
            storeFile = file(keystoreProperties.getProperty("storeFile", ""))
            storePassword = keystoreProperties.getProperty("storePassword", "")
            keyAlias = keystoreProperties.getProperty("keyAlias", "")
            keyPassword = keystoreProperties.getProperty("keyPassword", "")
        }
    }
    buildTypes {
        getByName("debug") {
            manifestPlaceholders["usesCleartextTraffic"] = "true"
            isDebuggable = true
            isJniDebuggable = true
            isMinifyEnabled = false
            packaging {                jniLibs.keepDebugSymbols.add("*/arm64-v8a/*.so")
                jniLibs.keepDebugSymbols.add("*/armeabi-v7a/*.so")
                jniLibs.keepDebugSymbols.add("*/x86/*.so")
                jniLibs.keepDebugSymbols.add("*/x86_64/*.so")
            }
        }
        getByName("release") {
            isMinifyEnabled = true
            ndk {
                // Play Console native-symbol archive; the release driver also
                // disables Cargo's pre-Gradle stripping for this build.
                debugSymbolLevel = "FULL"
            }
            proguardFiles(
                *fileTree(".") { include("**/*.pro") }
                    .plus(getDefaultProguardFile("proguard-android-optimize.txt"))
                    .toList().toTypedArray()
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures {
        buildConfig = true
    }
}

rust {
    rootDirRel = "../../../"
}

dependencies {
    implementation("androidx.webkit:webkit:1.14.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.lifecycle:lifecycle-process:2.10.0")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.4")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.0")
}

apply(from = "tauri.build.gradle.kts")
