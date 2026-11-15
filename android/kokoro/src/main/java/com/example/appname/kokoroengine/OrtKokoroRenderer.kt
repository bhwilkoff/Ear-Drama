package com.example.appname.kokoroengine

import com.example.appname.kokoro.Kokoro
import com.example.appname.kokoro.KokoroEngineFactory
import com.example.appname.kokoro.KokoroRenderer

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.nio.FloatBuffer
import java.nio.LongBuffer

/**
 * The base app's way in (KokoroEngines, by reflection once Play has installed this module): builds the renderer
 * from the model's path, the voice table and the session settings. An empty [settings] is the shipped session.
 */
class OrtEngineFactory : KokoroEngineFactory {
    init {
        // ONNX Runtime on Android loads only its JNI library and lets the linker find libonnxruntime.so beside it. A
        // module installed while the app runs has its libraries in SplitCompat's own folder, which the linker does not
        // search, so the runtime is loaded first by name through this class loader (seen on the Pixel 8a 2026-11-15).
        System.loadLibrary("onnxruntime")
    }

    override val runtime: String get() = "onnxruntime " + OrtEnvironment.getEnvironment().version

    override fun load(modelPath: String, table: FloatArray, settings: Map<String, String>): KokoroRenderer =
        OrtKokoroRenderer.load(modelPath, table, OrtKokoroRenderer.Options.from(settings))

    override fun describe(settings: Map<String, String>): String = OrtKokoroRenderer.Options.from(settings).toString()
}

/**
 * Kokoro-82M on ONNX Runtime's CPU provider (MIT; Decision 078). Built from the model's path and the voice table
 * and vocabulary already read into memory by KokoroReader; it opens nothing else and writes nothing. Not thread-safe:
 * KokoroReader calls it from one thread, never the main one.
 */
class OrtKokoroRenderer private constructor(
    private val env: OrtEnvironment,
    private val session: OrtSession,
    private val table: FloatArray,
    private val runOptions: OrtSession.RunOptions?,
) : KokoroRenderer {
    override fun render(tokens: LongArray, voiceIndex: Int, speed: Float): FloatArray {
        val style = Kokoro.style(table, voiceIndex, tokens.size)
        OnnxTensor.createTensor(env, LongBuffer.wrap(tokens), longArrayOf(1, tokens.size.toLong())).use { ids ->
            OnnxTensor.createTensor(env, FloatBuffer.wrap(style), longArrayOf(1, Kokoro.STYLE.toLong())).use { s ->
                OnnxTensor.createTensor(env, FloatBuffer.wrap(floatArrayOf(speed)), longArrayOf(1)).use { sp ->
                    val inputs = mapOf("input_ids" to ids, "style" to s, "speed" to sp)
                    (if (runOptions != null) session.run(inputs, runOptions) else session.run(inputs)).use { out ->
                        val buf = (out.get(0) as OnnxTensor).floatBuffer
                        return FloatArray(buf.remaining()).also { buf.get(it) }
                    }
                }
            }
        }
    }

    override fun close() {
        runCatching { session.close() }
        runCatching { runOptions?.close() }
    }

    /** Session settings; the defaults are the ones that passed S6a on the Pixel 8a (the bench sweeps the rest). */
    data class Options(
        val threads: Int = 4,
        val level: OrtSession.SessionOptions.OptLevel = OrtSession.SessionOptions.OptLevel.ALL_OPT,
        val xnnpack: Boolean = false,
        val nnapi: Boolean = false,
        val arena: Boolean = true,
        val memPattern: Boolean = arena,
        /** Arena on, but every render hands its chunks back afterwards: the arena's speed without keeping its peak. */
        val shrink: Boolean = true,
        val spin: Boolean = true,
        /** session.intra_op_thread_affinities: one entry per intra-op thread after the first, 1-based CPU ids. */
        val affinity: String? = null,
        val prepack: Boolean = true,
        val initializersOutsideArena: Boolean = false,
    ) {
        companion object {
            /** The bench's intent extras as text (threads, opt, xnnpack, nnapi, arena, mempattern, shrink, ...). */
            fun from(m: Map<String, String>): Options {
                val d = Options()
                fun b(k: String, v: Boolean) = m[k]?.toBooleanStrictOrNull() ?: v
                val arena = b("arena", d.arena)
                return Options(
                    threads = m["threads"]?.toIntOrNull() ?: d.threads,
                    level = when (m["opt"]) {
                        "none" -> OrtSession.SessionOptions.OptLevel.NO_OPT
                        "basic" -> OrtSession.SessionOptions.OptLevel.BASIC_OPT
                        "extended" -> OrtSession.SessionOptions.OptLevel.EXTENDED_OPT
                        else -> d.level
                    },
                    xnnpack = b("xnnpack", d.xnnpack),
                    nnapi = b("nnapi", d.nnapi),
                    arena = arena,
                    memPattern = b("mempattern", arena),
                    shrink = b("shrink", d.shrink),
                    spin = b("spin", d.spin),
                    affinity = m["affinity"] ?: d.affinity,
                    prepack = b("prepack", d.prepack),
                    initializersOutsideArena = b("initdev", d.initializersOutsideArena),
                )
            }
        }
    }

    companion object {
        fun load(modelPath: String, table: FloatArray, o: Options = Options()): OrtKokoroRenderer {
            val env = OrtEnvironment.getEnvironment()
            val options = OrtSession.SessionOptions().apply {
                setIntraOpNumThreads(o.threads)
                setInterOpNumThreads(1)
                setExecutionMode(OrtSession.SessionOptions.ExecutionMode.SEQUENTIAL)
                setOptimizationLevel(o.level)
                setCPUArenaAllocator(o.arena)
                setMemoryPatternOptimization(o.memPattern)
                addConfigEntry("session.intra_op.allow_spinning", if (o.spin) "1" else "0")
                o.affinity?.let { addConfigEntry("session.intra_op_thread_affinities", it) }
                if (!o.prepack) addConfigEntry("session.disable_prepacking", "1")
                if (o.initializersOutsideArena) addConfigEntry("session.use_device_allocator_for_initializers", "1")
                if (o.nnapi) addNnapi()
                if (o.xnnpack) addXnnpack(mapOf("intra_op_num_threads" to o.threads.toString()))
            }
            val run = if (o.arena && o.shrink) OrtSession.RunOptions().apply { addRunConfigEntry("memory.enable_memory_arena_shrinkage", "cpu:0") } else null
            return OrtKokoroRenderer(env, env.createSession(modelPath, options), table, run)
        }
    }
}
