allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    if (project.name == "jni") {
        val flutterConfig = groovy.util.Expando()
        flutterConfig.setProperty("ndkVersion", "29.0.14206865")
        extensions.extraProperties["flutter"] = flutterConfig
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.gradle.AppExtension>("android") {
            ndkVersion = "29.0.14206865"
        }
    }
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            ndkVersion = "29.0.14206865"
            if (namespace == null) {
                namespace = (project.group as? String) ?: "unknown.${project.name}"
            }
        }
    }
}

// Fix JVM target mismatch for Android library subprojects that use old Java 1.8
// but inherit Kotlin JVM target 17 from the project's Kotlin plugin version.
gradle.projectsEvaluated {
    subprojects {
        if (plugins.hasPlugin("com.android.library")) {
            try {
                val androidExt = project.extensions.findByType<com.android.build.gradle.LibraryExtension>()
                val javaTarget = androidExt?.compileOptions?.targetCompatibility ?: JavaVersion.VERSION_17
                project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                    compilerOptions {
                        jvmTarget.set(
                            when (javaTarget) {
                                JavaVersion.VERSION_1_8 -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                                JavaVersion.VERSION_11 -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                                JavaVersion.VERSION_17 -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                                else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                            }
                        )
                    }
                }
            } catch (_: Exception) {
                // Silently skip — safer fallback
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
