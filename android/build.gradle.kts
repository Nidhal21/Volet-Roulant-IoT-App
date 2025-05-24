// Top-level build file
plugins {
    // Apply the Google Services plugin globally if needed
    id("com.android.application") version "8.6.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.20" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

// Set up repositories used by all subprojects
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Custom build directory setup (for Flutter compatibility)
val newBuildDir: java.io.File = rootProject.layout.buildDirectory.dir("../../build").get().asFile
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir = File(newBuildDir, project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
}

// Ensure subprojects can reference :app
subprojects {
    project.evaluationDependsOn(":app")
}

// Register clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}