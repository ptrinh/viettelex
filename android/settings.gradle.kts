pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "VietTelex"
include(":telexcore", ":keyboard", ":app", ":translate")
// Đo hiệu năng hiện bàn phím (docs/PERF-IME-SHOW.md): app chủ tối giản + Macrobenchmark — không phát hành.
include(":perfhost", ":benchmark")
