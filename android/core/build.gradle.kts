plugins {
    id("com.android.library")
}

val targetPlatform = (project.findProperty("target-platform") as String?)
    ?.lowercase()
    .orEmpty()
val targetAbi = when {
    targetPlatform.contains("android-arm64") -> "arm64-v8a"
    targetPlatform.contains("android-x64") -> "x86_64"
    targetPlatform.contains("android-arm") -> "armeabi-v7a"
    else -> "arm64-v8a"
}

android {
    namespace = "com.appshub.bettbox.core"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    defaultConfig {
        minSdk = 24
        ndk {
            abiFilters += targetAbi
        }
    }

    buildTypes {
        release {
            isJniDebuggable = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    externalNativeBuild {
        cmake {
            path("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.annotation:annotation-jvm:1.9.1")
}

val cleanNativeLibs by tasks.register<Delete>("cleanNativeLibs") {
    delete(layout.projectDirectory.dir("src/main/jniLibs"))
}

val copyNativeLibs by tasks.register<Copy>("copyNativeLibs") {
    dependsOn(cleanNativeLibs)
    from("../../libclash/android") {
        include("$targetAbi/**")
    }
    into("src/main/jniLibs")
}

afterEvaluate {
    tasks.named("preBuild") {
        dependsOn(copyNativeLibs)
    }
}