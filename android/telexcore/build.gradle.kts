plugins { id("org.jetbrains.kotlin.jvm") }
kotlin {
    jvmToolchain(21)
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}
java { targetCompatibility = JavaVersion.VERSION_17; sourceCompatibility = JavaVersion.VERSION_17 }

dependencies { testImplementation(kotlin("test")); testImplementation("junit:junit:4.13.2") }
tasks.test { useJUnit() }
