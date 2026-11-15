package com.example.appname.kokoro

/** Renders one piece of tokens in one voice: 24 kHz mono samples, in memory. */
interface KokoroRenderer : AutoCloseable {
    fun render(tokens: LongArray, voiceIndex: Int, speed: Float): FloatArray
}
