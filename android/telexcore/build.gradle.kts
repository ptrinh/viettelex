plugins { id("org.jetbrains.kotlin.jvm") }
kotlin { jvmToolchain(21) }

dependencies { testImplementation(kotlin("test")); testImplementation("junit:junit:4.13.2") }
tasks.test { useJUnit() }
