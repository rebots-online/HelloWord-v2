buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.11.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.25")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // All Gradle output lives under the repo's dist/android/ (gitignored),
    // never beside the sources.
    layout.buildDirectory.set(file("${rootDir}/../../../dist/android/${project.name}"))
}

tasks.register("clean").configure {
    delete(layout.buildDirectory)
}
