package com.example.appname.kokoro

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.nio.FloatBuffer
import java.nio.LongBuffer

/**
 * The engine in builds that carry ONNX Runtime (the `ort` source set: debug always; release once
 * `kokoroInRelease` in build.gradle.kts is on, after the S6a gate).
 */
object KokoroEngines {
    const val AVAILABLE = true

    /** The settings that passed S6a on the Pixel 8a (R2-kokoro-feasibility, S6a). */
    val SHIPPED = OrtKokoroRenderer.Options(arena = true, shrink = true)

    fun load(paths: KokoroModelStore.Paths, table: FloatArray): KokoroRenderer = OrtKokoroRenderer.load(paths.model.path, table, SHIPPED)
}

/**
 * Kokoro-82M on ONNX Runtime's CPU provider (MIT; Decision 078). Built from the model's path and the voice table
 * and vocabulary already read into memory by [KokoroReader]; it opens nothing else and writes nothing. Not thread-safe:
 * [KokoroReader] calls it from one thread, never the main one.
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

    /** Session settings (the S6a bench sweeps these). */
    data class Options(
        val threads: Int = 4,
        val level: OrtSession.SessionOptions.OptLevel = OrtSession.SessionOptions.OptLevel.ALL_OPT,
        val xnnpack: Boolean = false,
        val nnapi: Boolean = false,
        val arena: Boolean = true,
        val memPattern: Boolean = arena,
        /** Arena on, but every render hands its chunks back afterwards: the arena's speed without keeping its peak. */
        val shrink: Boolean = false,
        val spin: Boolean = true,
        /** session.intra_op_thread_affinities: one entry per intra-op thread after the first, 1-based CPU ids. */
        val affinity: String? = null,
        val prepack: Boolean = true,
        val initializersOutsideArena: Boolean = false,
    )

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
