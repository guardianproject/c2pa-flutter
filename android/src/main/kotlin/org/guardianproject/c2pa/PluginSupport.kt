/*
This file is licensed to you under the Apache License, Version 2.0
(http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
(http://opensource.org/licenses/MIT), at your option.

Unless required by applicable law or agreed to in writing, this software is
distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
files for the specific language governing permissions and limitations under
each license.
*/

package org.guardianproject.c2pa

import org.contentauth.c2pa.BuilderIntent
import org.contentauth.c2pa.DigitalSourceType
import org.contentauth.c2pa.FileStream
import org.contentauth.c2pa.HashType
import org.contentauth.c2pa.ProgressPhase
import org.contentauth.c2pa.SigningAlgorithm
import java.io.File
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** An error reported to Dart with an explicit code (anything but C2PA_ERROR). */
class PluginError(val code: String, message: String) : Exception(message)

fun invalidArgument(message: String) = PluginError("INVALID_ARGUMENT", message)

fun invalidHandle(kind: String) = PluginError("INVALID_HANDLE", "Invalid $kind handle")

/** Thread-safe map from Dart-visible integer handles to native objects. */
class HandleRegistry<T> {
    private val items = HashMap<Int, T>()
    private var next = 1
    private val lock = ReentrantLock()

    fun reserve(): Int = lock.withLock { next++ }

    fun put(handle: Int, item: T) = lock.withLock { items[handle] = item }

    fun store(item: T): Int = lock.withLock {
        val handle = next++
        items[handle] = item
        handle
    }

    fun get(handle: Int): T? = lock.withLock { items[handle] }

    fun remove(handle: Int): T? = lock.withLock { items.remove(handle) }

    fun drain(): List<T> = lock.withLock {
        val all = items.values.toList()
        items.clear()
        all
    }
}

/**
 * Opens an existing file for reading. Unlike the FileStream default, a missing
 * file is an error rather than a silently created empty file.
 */
fun openForRead(path: String): FileStream {
    val file = File(path)
    if (!file.exists()) throw invalidArgument("File not found: $path")
    return FileStream(file, FileStream.Mode.READ, createIfNeeded = false)
}

/** Opens a destination file for writing, truncating anything already there. */
fun openForWrite(path: String): FileStream {
    val file = File(path)
    file.parentFile?.mkdirs()
    if (file.exists()) file.delete()
    return FileStream(file, FileStream.Mode.WRITE, createIfNeeded = true)
}

fun mimeTypeForPath(path: String): String =
    when (path.substringAfterLast('.', "").lowercase()) {
        "jpg", "jpeg" -> "image/jpeg"
        "png" -> "image/png"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "tiff", "tif" -> "image/tiff"
        "heic" -> "image/heic"
        "heif" -> "image/heif"
        "avif" -> "image/avif"
        "dng" -> "image/x-adobe-dng"
        "mp4", "m4v" -> "video/mp4"
        "mov" -> "video/quicktime"
        "m4a" -> "audio/mp4"
        "mp3" -> "audio/mpeg"
        "wav" -> "audio/wav"
        "pdf" -> "application/pdf"
        "svg" -> "image/svg+xml"
        else -> "application/octet-stream"
    }

fun SigningAlgorithmMessage.toSdk(): SigningAlgorithm =
    when (this) {
        SigningAlgorithmMessage.ES256 -> SigningAlgorithm.ES256
        SigningAlgorithmMessage.ES384 -> SigningAlgorithm.ES384
        SigningAlgorithmMessage.ES512 -> SigningAlgorithm.ES512
        SigningAlgorithmMessage.PS256 -> SigningAlgorithm.PS256
        SigningAlgorithmMessage.PS384 -> SigningAlgorithm.PS384
        SigningAlgorithmMessage.PS512 -> SigningAlgorithm.PS512
        SigningAlgorithmMessage.ED25519 -> SigningAlgorithm.ED25519
    }

/** The algorithm's name as Dart spells it, for messages. */
val SigningAlgorithmMessage.dartName: String
    get() = name.lowercase()

fun ManifestIntentMessage.toSdk(digitalSourceType: String?): BuilderIntent =
    when (this) {
        ManifestIntentMessage.CREATE -> BuilderIntent.Create(
            digitalSourceType?.let { parseDigitalSourceType(it) } ?: DigitalSourceType.DIGITAL_CAPTURE,
        )
        ManifestIntentMessage.EDIT -> BuilderIntent.Edit
        ManifestIntentMessage.UPDATE -> BuilderIntent.Update
    }

fun parseDigitalSourceType(type: String): DigitalSourceType =
    when (type) {
        "empty" -> DigitalSourceType.EMPTY
        "trainedAlgorithmicMedia" -> DigitalSourceType.TRAINED_ALGORITHMIC_MEDIA
        "compositeWithTrainedAlgorithmicMedia" -> DigitalSourceType.COMPOSITE_WITH_TRAINED_ALGORITHMIC_MEDIA
        "algorithmicMedia" -> DigitalSourceType.ALGORITHMIC_MEDIA
        "compositeCapture" -> DigitalSourceType.COMPOSITE_CAPTURE
        "compositeSynthetic" -> DigitalSourceType.COMPOSITE_SYNTHETIC
        "dataDrivenMedia" -> DigitalSourceType.DATA_DRIVEN_MEDIA
        "digitalCapture" -> DigitalSourceType.DIGITAL_CAPTURE
        "virtualRecording" -> DigitalSourceType.VIRTUAL_RECORDING
        "humanEdits" -> DigitalSourceType.HUMAN_EDITS
        "computationalCapture" -> DigitalSourceType.COMPUTATIONAL_CAPTURE
        "digitalCreation" -> DigitalSourceType.DIGITAL_CREATION
        "trainedAlgorithmicData" -> DigitalSourceType.TRAINED_ALGORITHMIC_DATA
        "screenCapture" -> DigitalSourceType.SCREEN_CAPTURE
        "composite" -> DigitalSourceType.COMPOSITE
        "algorithmicallyEnhanced" -> DigitalSourceType.ALGORITHMICALLY_ENHANCED
        "negativeFilm" -> DigitalSourceType.NEGATIVE_FILM
        "positiveFilm" -> DigitalSourceType.POSITIVE_FILM
        "print" -> DigitalSourceType.PRINT
        else -> throw invalidArgument("Unknown digital source type: $type")
    }

fun HashType.toMessage(): HashTypeMessage =
    when (this) {
        HashType.DATA_HASH -> HashTypeMessage.DATA_HASH
        HashType.BMFF_HASH -> HashTypeMessage.BMFF_HASH
        HashType.BOX_HASH -> HashTypeMessage.BOX_HASH
    }

fun progressPhaseName(phase: ProgressPhase): String =
    when (phase) {
        ProgressPhase.READING -> "reading"
        ProgressPhase.VERIFYING_MANIFEST -> "verifyingManifest"
        ProgressPhase.VERIFYING_SIGNATURE -> "verifyingSignature"
        ProgressPhase.VERIFYING_INGREDIENT -> "verifyingIngredient"
        ProgressPhase.VERIFYING_ASSET_HASH -> "verifyingAssetHash"
        ProgressPhase.ADDING_INGREDIENT -> "addingIngredient"
        ProgressPhase.THUMBNAIL -> "thumbnail"
        ProgressPhase.HASHING -> "hashing"
        ProgressPhase.SIGNING -> "signing"
        ProgressPhase.EMBEDDING -> "embedding"
        ProgressPhase.FETCHING_REMOTE_MANIFEST -> "fetchingRemoteManifest"
        ProgressPhase.WRITING -> "writing"
        ProgressPhase.FETCHING_OCSP -> "fetchingOcsp"
        ProgressPhase.FETCHING_TIMESTAMP -> "fetchingTimestamp"
        ProgressPhase.UNKNOWN -> "unknown"
    }
