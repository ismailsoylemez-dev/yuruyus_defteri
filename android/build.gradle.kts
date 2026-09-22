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

// Bazi eklentiler (file_picker vb.) eski compileSdk ile geliyor.
// Hepsini 36'ya cekmezsek "AAR metadata" hatasi aliniyor.
// Bu blok evaluationDependsOn'dan ONCE gelmeli; sonra yazilirsa
// projeler zaten degerlendirilmis olur ve afterEvaluate hata verir.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            androidExt.javaClass
                .getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(androidExt, 36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
