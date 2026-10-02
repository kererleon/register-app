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
}
// Some older plugins do not declare a namespace, which newer Android Gradle
// plugins require. Use their manifest package instead, as soon as the
// Android library plugin is applied to them.
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.getByName("android") as com.android.build.gradle.BaseExtension
        if (android.namespace == null) {
            val manifest = file("src/main/AndroidManifest.xml")
            if (manifest.exists()) {
                Regex("package=\"([^\"]+)\"").find(manifest.readText())?.let {
                    android.namespace = it.groupValues[1]
                }
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
