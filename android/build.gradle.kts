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

// -----------------------------------------------------------------
// Force every Android library plugin to compile against the same
// compileSdk our app uses (36+). Some plugins ship with compileSdk=34
// but their transitive deps require 36. We register the override in
// the SAME subprojects block that relocates the build directory, and
// BEFORE the evaluationDependsOn block below — otherwise Gradle refuses
// the afterEvaluate callback because the subproject has already been
// evaluated.
// -----------------------------------------------------------------
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
