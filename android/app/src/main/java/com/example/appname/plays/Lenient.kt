package com.example.appname.plays

import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.nullable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonNull

/**
 * An additive field of the play library read on its own (contract §4.1, B31): one the client does not understand, or a
 * library built before it, never loses the row or the index. A malformed value reads as [fallback].
 */
abstract class LenientSerializer<T>(private val inner: KSerializer<T>, private val fallback: T) : KSerializer<T> {
    override val descriptor: SerialDescriptor get() = inner.descriptor
    override fun serialize(encoder: Encoder, value: T) = inner.serialize(encoder, value)
    override fun deserialize(decoder: Decoder): T {
        val json = decoder as? JsonDecoder ?: return inner.deserialize(decoder)
        val element = json.decodeJsonElement()
        if (element is JsonNull) return fallback
        return try { json.json.decodeFromJsonElement(inner, element) } catch (e: Exception) { fallback }
    }
}

object LenientString : LenientSerializer<String?>(String.serializer().nullable, null)
object LenientInt : LenientSerializer<Int?>(Int.serializer().nullable, null)
object LenientBool : LenientSerializer<Boolean>(Boolean.serializer(), false)
object LenientStrings : LenientSerializer<List<String>>(ListSerializer(String.serializer()), emptyList())
object LenientArt : LenientSerializer<PlayArt?>(PlayArt.serializer().nullable, null)
object LenientLife : LenientSerializer<PlayRow.Life?>(PlayRow.Life.serializer().nullable, null)

/** A list whose elements are each read on their own: a malformed one is dropped, the rest kept. */
object LenientScenes : KSerializer<List<PlayRow.Scene>> {
    private val inner = ListSerializer(PlayRow.Scene.serializer())
    override val descriptor: SerialDescriptor get() = inner.descriptor
    override fun serialize(encoder: Encoder, value: List<PlayRow.Scene>) = inner.serialize(encoder, value)
    override fun deserialize(decoder: Decoder): List<PlayRow.Scene> {
        val json = decoder as? JsonDecoder ?: return inner.deserialize(decoder)
        val element = json.decodeJsonElement() as? JsonArray ?: return emptyList()
        return element.mapNotNull { e -> try { json.json.decodeFromJsonElement(PlayRow.Scene.serializer(), e) } catch (x: Exception) { null } }
    }
}

object LenientFacetValues : KSerializer<List<PlayFacetsIndex.Value>?> {
    private val inner = ListSerializer(PlayFacetsIndex.Value.serializer())
    override val descriptor: SerialDescriptor get() = inner.descriptor
    override fun serialize(encoder: Encoder, value: List<PlayFacetsIndex.Value>?) { if (value != null) inner.serialize(encoder, value) }
    override fun deserialize(decoder: Decoder): List<PlayFacetsIndex.Value>? {
        val json = decoder as? JsonDecoder ?: return inner.deserialize(decoder)
        val element = json.decodeJsonElement() as? JsonArray ?: return null
        return element.mapNotNull { e -> try { json.json.decodeFromJsonElement(PlayFacetsIndex.Value.serializer(), e) } catch (x: Exception) { null } }
    }
}

object LenientBins : KSerializer<List<PlayFacetsIndex.Bin>?> {
    private val inner = ListSerializer(PlayFacetsIndex.Bin.serializer())
    override val descriptor: SerialDescriptor get() = inner.descriptor
    override fun serialize(encoder: Encoder, value: List<PlayFacetsIndex.Bin>?) { if (value != null) inner.serialize(encoder, value) }
    override fun deserialize(decoder: Decoder): List<PlayFacetsIndex.Bin>? {
        val json = decoder as? JsonDecoder ?: return inner.deserialize(decoder)
        val element = json.decodeJsonElement() as? JsonArray ?: return null
        return element.mapNotNull { e -> try { json.json.decodeFromJsonElement(PlayFacetsIndex.Bin.serializer(), e) } catch (x: Exception) { null } }
    }
}

object LenientFacets : LenientSerializer<PlayFacetsIndex?>(PlayFacetsIndex.serializer().nullable, null)
