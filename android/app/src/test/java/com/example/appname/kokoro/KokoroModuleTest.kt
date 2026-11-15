package com.example.appname.kokoro

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The engine is the on-demand `:kokoro` module (owner 2026-11-15): the base never names ONNX Runtime, and every
 * component a module dependency declares is removed, because module components merge into the base manifest and a
 * base that starts a class it does not carry crashes at launch (seen on the Pixel 8a with ORT's TelemetryInitializer).
 */
class KokoroModuleTest {
    private val base = File("src/main/java").walkTopDown().filter { it.extension == "kt" }.toList()
    private val module = File("../kokoro/src/main/AndroidManifest.xml")

    @Test fun `the base reaches ONNX Runtime only through the module`() {
        assertTrue("no sources found", base.size > 10)
        assertEquals(emptyList<String>(), base.filter { it.readText().contains("ai.onnxruntime") }.map { it.name })
        assertTrue(File("build.gradle.kts").readText().contains("dynamicFeatures += setOf(\":kokoro\")"))
        assertFalse("the base must not depend on ONNX Runtime", File("build.gradle.kts").readText().contains("libs.onnxruntime"))
    }

    @Test fun `the module removes ONNX Runtime's startup provider`() {
        assertTrue(providerRemoved(module.readText()))
        // Control: a manifest that keeps the provider is caught.
        assertFalse(providerRemoved("<application><provider android:name=\"ai.onnxruntime.TelemetryInitializer\" /></application>"))
    }

    @Test fun `the module is on demand, never installed with the app`() {
        val text = module.readText()
        assertTrue(text.contains("<dist:on-demand />"))
        assertFalse(text.contains("install-time"))
    }

    private fun providerRemoved(manifest: String): Boolean =
        Regex("""<provider[^>]*ai\.onnxruntime\.TelemetryInitializer[^>]*tools:node="remove"""").containsMatchIn(manifest)
}
