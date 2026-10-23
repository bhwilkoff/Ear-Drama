package com.example.appname.together

import com.example.appname.data.CatalogRepository
import com.example.appname.data.EpisodeRow
import com.example.appname.playback.LoudnessLevel
import com.example.appname.playback.PlaybackEngine

/**
 * The room's player is the app's one [PlaybackEngine] (ANDROID-DESIGN §5.1):
 * the host's state is read from it, and a guest's corrections go through it,
 * so the notification, the lock screen, and Bluetooth show what the room plays.
 * Every call is on the main thread, as the engine's are.
 */
class EngineRoomPlayer(private val engine: PlaybackEngine, private val catalog: CatalogRepository) : RoomPlayer {
    override fun hostState(): RoomState? {
        val view = engine.roomView() ?: return null
        val (archiveId, file) = RoomProtocol.copyOf(view.copyUrl) ?: return null
        return RoomState(
            episodeId = view.episodeId,
            archiveId = archiveId,
            file = file,
            position = view.positionMs / 1000.0,
            playing = view.playing,
            rate = RoomProtocol.roomRate(view.speed.toDouble()),
            updatedAt = 0,
        )
    }

    override fun sample(): PlayerSample? = engine.roomView()?.let { PlayerSample(it.positionMs / 1000.0, it.playing) }

    override fun episodeId(): String? = engine.roomView()?.episodeId

    override suspend fun load(state: RoomState, position: Double) {
        val url = RoomProtocol.copyUrl(state.archiveId, state.file)
        val detail = catalog.awaitDb()?.episodeDetail(state.episodeId)
        // An episode this device's catalog lacks still plays: archive.org's own names stand in.
        val row = detail?.episode ?: EpisodeRow(
            id = state.episodeId,
            seriesKey = "",
            seriesName = state.archiveId,
            airDate = null,
            season = null,
            num = null,
            title = state.file.substringAfterLast('/').substringBeforeLast('.'),
            lengthSeconds = null,
        )
        val level = detail?.let { LoudnessLevel.volume(it, url) } ?: 1f
        engine.playRoomCopy(row, url, (position * 1000).toLong(), state.playing, state.rate.toFloat(), level)
    }

    override fun apply(correction: Correction) {
        when (correction) {
            Correction.None -> Unit
            is Correction.Pause -> {
                engine.pause()
                engine.seekTo(ms(correction.position))
            }
            is Correction.Seek -> {
                engine.seekTo(ms(correction.position))
                if (correction.play) engine.resume() else engine.pause()
            }
            is Correction.Play -> {
                engine.seekTo(ms(correction.position))
                engine.setSpeed(correction.rate.toFloat())
                engine.resume()
            }
            is Correction.Rate -> {
                val speed = correction.rate.toFloat()
                if (kotlin.math.abs(engine.state.value.speed - speed) > 0.0005f) engine.setSpeed(speed)
            }
        }
    }

    override fun onChange(listener: (() -> Unit)?) {
        engine.onRoomChange = listener
    }

    private fun ms(seconds: Double): Long = (seconds * 1000).toLong()
}
