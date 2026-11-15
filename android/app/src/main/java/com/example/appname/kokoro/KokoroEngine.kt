package com.example.appname.kokoro

/** Renders one piece of tokens in one voice: 24 kHz mono samples, in memory. */
interface KokoroRenderer : AutoCloseable {
    fun render(tokens: LongArray, voiceIndex: Int, speed: Float): FloatArray
}

/**
 * The engine's way in, implemented in the on-demand `:kokoro` module (ONNX Runtime). Empty [settings] is the shipped
 * session; the S6a bench passes others.
 */
interface KokoroEngineFactory {
    val runtime: String
    fun load(modelPath: String, table: FloatArray, settings: Map<String, String> = emptyMap()): KokoroRenderer
    fun describe(settings: Map<String, String> = emptyMap()): String
}

/**
 * Where the engine is: the `:kokoro` module once Play has installed it (owner 2026-11-15: the base install carries no
 * ONNX Runtime). Until then [factory] is null and no line is read by Kokoro.
 */
object KokoroEngines {
    const val MODULE = "kokoro"
    private const val FACTORY = "com.example.appname.kokoroengine.OrtEngineFactory"

    @Volatile private var found: KokoroEngineFactory? = null

    /** Whether the module's classes are here, without loading the runtime (cheap enough for the main thread). */
    fun present(): Boolean = found != null || try {
        Class.forName(FACTORY, false, KokoroEngines::class.java.classLoader)
        true
    } catch (_: ClassNotFoundException) {
        false
    } catch (_: LinkageError) {
        false
    }

    /** The engine, loading ONNX Runtime the first time (off the main thread: the reader's worker). */
    fun factory(): KokoroEngineFactory? {
        found?.let { return it }
        return try {
            (Class.forName(FACTORY).getDeclaredConstructor().newInstance() as KokoroEngineFactory).also { found = it }
        } catch (_: ReflectiveOperationException) {
            null
        } catch (_: LinkageError) {
            null
        }
    }

    fun load(paths: KokoroModelStore.Paths, table: FloatArray): KokoroRenderer =
        (factory() ?: throw IllegalStateException("the voice engine is not installed")).load(paths.model.path, table)
}
