plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.compose.multiplatform)
    alias(libs.plugins.compose.compiler)
    application
}

kotlin {
    jvmToolchain(11)
}

application {
    mainClass.set("com.storemanager.desktop.MainKt")
}

dependencies {
    implementation(project(":shared:domain"))
    implementation(project(":shared:design-system"))
    implementation(compose.desktop.currentOs)
    implementation(compose.material3)
    implementation(libs.kotlinx.coroutines.core)
    testImplementation(libs.junit)
}
