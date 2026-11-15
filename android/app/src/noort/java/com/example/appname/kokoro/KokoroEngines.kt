package com.example.appname.kokoro

/** Release builds without ONNX Runtime (`kokoroInRelease` off in build.gradle.kts): no engine, so no Kokoro voice. */
object KokoroEngines {
    const val AVAILABLE = false

    fun load(paths: KokoroModelStore.Paths, table: FloatArray): KokoroRenderer =
        throw UnsupportedOperationException("this build carries no Kokoro engine (${paths.model.name}, ${table.size})")
}
