package com.example.appname.plays

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The recorder opens in Run through, then remembers the last mode on this device (the web's `ed.recmode`, Apple's `recorder.mode`). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RecorderModeMemoryTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test fun `Run through the first time, then the last mode picked`() {
        context.getSharedPreferences("recorder", Context.MODE_PRIVATE).edit().clear().commit()
        assertEquals(RecordingSession.Mode.Run, RecordingSession.Mode.remembered(context))
        RecordingSession.Mode.Lines.remember(context)
        assertEquals(RecordingSession.Mode.Lines, RecordingSession.Mode.remembered(context))
        RecordingSession.Mode.Step.remember(context)
        assertEquals(RecordingSession.Mode.Step, RecordingSession.Mode.remembered(context))
    }

    @Test fun `a stored word that is no mode falls back to Run through`() {
        context.getSharedPreferences("recorder", Context.MODE_PRIVATE).edit().putString("mode", "nonsense").commit()
        assertEquals(RecordingSession.Mode.Run, RecordingSession.Mode.remembered(context))
    }
}
