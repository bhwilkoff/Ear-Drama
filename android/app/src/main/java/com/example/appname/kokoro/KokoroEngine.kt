package com.example.appname.kokoro

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.nio.FloatBuffer
import java.nio.LongBuffer

/** Renders one piece of tokens in one voice: 24 kHz mono samples, in memory. */
interface KokoroRenderer : AutoCloseable {
    fun render(tokens: LongArray, voiceIndex: Int, speed: Float): FloatArray
}

/**
 * Kokoro-82M q8f16 on ONNX Runtime's CPU provider (MIT; Decision 078). Built from the model's path and the voice table
 * and vocabulary already read into memory by [KokoroReader]; it opens nothing else and writes nothing. Not thread-safe:
 * [KokoroReader] calls it from one thread, never the main one.
 */
class OrtKokoroRenderer private constructor(
    private val env: OrtEnvironment,
    private val session: OrtSession,
    private val table: FloatArray,
) : KokoroRenderer {
    override fun render(tokens: LongArray, voiceIndex: Int, speed: Float): FloatArray {
        val style = Kokoro.style(table, voiceIndex, tokens.size)
        OnnxTensor.createTensor(env, LongBuffer.wrap(tokens), longArrayOf(1, tokens.size.toLong())).use { ids ->
            OnnxTensor.createTensor(env, FloatBuffer.wrap(style), longArrayOf(1, Kokoro.STYLE.toLong())).use { s ->
                OnnxTensor.createTensor(env, FloatBuffer.wrap(floatArrayOf(speed)), longArrayOf(1)).use { sp ->
                    session.run(mapOf("input_ids" to ids, "style" to s, "speed" to sp)).use { out ->
                        val buf = (out.get(0) as OnnxTensor).floatBuffer
                        return FloatArray(buf.remaining()).also { buf.get(it) }
                    }
                }
            }
        }
    }

    override fun close() {
        runCatching { session.close() }
    }

    companion object {
        /** [threads] intra-op threads: the Pixel 8a's four middle cores by default. */
        fun load(
            modelPath: String,
            table: FloatArray,
            threads: Int = 4,
            level: OrtSession.SessionOptions.OptLevel = OrtSession.SessionOptions.OptLevel.ALL_OPT,
            xnnpack: Boolean = false,
            arena: Boolean = true,
        ): OrtKokoroRenderer {
            val env = OrtEnvironment.getEnvironment()
            val options = OrtSession.SessionOptions().apply {
                setIntraOpNumThreads(threads)
                setOptimizationLevel(level)
                // The CPU arena keeps the largest render's buffers for the session's life; off, each render frees its own.
                setCPUArenaAllocator(arena)
                setMemoryPatternOptimization(arena)
                if (xnnpack) addXnnpack(mapOf("intra_op_num_threads" to threads.toString()))
            }
            return OrtKokoroRenderer(env, env.createSession(modelPath, options), table)
        }
    }
}
