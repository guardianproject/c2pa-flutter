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

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import org.contentauth.c2pa.Action
import org.contentauth.c2pa.Builder
import org.contentauth.c2pa.ByteArrayStream
import org.contentauth.c2pa.C2PA
import org.contentauth.c2pa.C2PAContext
import org.contentauth.c2pa.C2PAContextBuilder
import org.contentauth.c2pa.C2PAError
import org.contentauth.c2pa.C2PASettings
import org.contentauth.c2pa.HttpResolver
import org.contentauth.c2pa.HttpResponse
import org.contentauth.c2pa.ProgressObserver
import org.contentauth.c2pa.Reader
import org.contentauth.c2pa.Stream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Flutter plugin bridging the Dart C2PA API to c2pa-android through the
 * Pigeon-generated [C2paHostApi] and [C2paFlutterApi].
 *
 * Threading model: every call that touches a builder, reader, settings or
 * context runs on one serial worker thread, in the order Dart sent it. That
 * keeps the main thread free while signing (callback signers, progress and
 * HTTP resolvers call back into Dart on the main thread and block the worker
 * until Dart answers), and it means `builderDispose` can never free a builder
 * that an earlier call is still using. Key management runs on a separate pool
 * so a Dart signing callback can use it while the worker is blocked.
 * `contextCancel` runs immediately, since it must reach an operation that is
 * occupying the worker.
 */
class C2paPlugin : FlutterPlugin, C2paHostApi {
    private var flutterApi: C2paFlutterApi? = null
    private var appContext: android.content.Context? = null
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private var worker: ExecutorService = newWorker()
    private val auxPool: ExecutorService = Executors.newCachedThreadPool { r -> Thread(r, "c2pa-flutter-aux") }

    private val builders = HandleRegistry<Builder>()
    private val settingsHandles = HandleRegistry<C2PASettings>()
    private val contexts = HandleRegistry<C2PAContext>()

    /** Settings applied by `loadSettings` to readers and builders created without a context. Worker thread only. */
    private var defaultSettings: C2PASettings? = null

    private val signers = SignerFactory { callbackId, data ->
        callDart("sign") { api, reply -> api.sign(callbackId, data, reply) }
    }
    private val keys = KeyManagement { appContext }

    private fun newWorker(): ExecutorService =
        Executors.newSingleThreadExecutor { r -> Thread(r, "c2pa-flutter-worker") }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        C2paHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = C2paFlutterApi(binding.binaryMessenger)
        appContext = binding.applicationContext
        if (worker.isShutdown) worker = newWorker()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        C2paHostApi.setUp(binding.binaryMessenger, null)
        flutterApi = null
        appContext = null
        worker.execute {
            builders.drain().forEach { runCatching { it.close() } }
            settingsHandles.drain().forEach { runCatching { it.close() } }
            contexts.drain().forEach { runCatching { it.close() } }
            defaultSettings?.let { runCatching { it.close() } }
            defaultSettings = null
        }
        worker.shutdown()
    }

    // =========================================================================
    // Lanes and result plumbing
    // =========================================================================

    /** Runs [block] on the serial worker and replies on the main thread. */
    private fun <T> onWorker(callback: (Result<T>) -> Unit, block: () -> T) =
        worker.execute { deliver(callback, block) }

    /** Runs [block] on the key-management pool and replies on the main thread. */
    private fun <T> onAux(callback: (Result<T>) -> Unit, block: () -> T) =
        auxPool.execute { deliver(callback, block) }

    private fun <T> deliver(callback: (Result<T>) -> Unit, block: () -> T) {
        val result = try {
            Result.success(block())
        } catch (e: Exception) {
            Result.failure(toFlutterError(e))
        }
        mainHandler.post { callback(result) }
    }

    /** Maps a failure to the error codes Dart's C2paException understands. */
    private fun toFlutterError(e: Throwable): FlutterError =
        when (e) {
            is FlutterError -> e
            is PluginError -> FlutterError(e.code, e.message)
            is C2PAError -> FlutterError("C2PA_ERROR", e.message ?: e.toString())
            else -> FlutterError("ERROR", e.message ?: e.toString())
        }

    /**
     * Calls Dart on the main thread through [invoke] and blocks the calling
     * thread until it answers. Must never be called on the main thread.
     */
    private fun <T> callDart(name: String, invoke: (C2paFlutterApi, (Result<T>) -> Unit) -> Unit): T {
        check(Looper.myLooper() != Looper.getMainLooper()) { "$name must not be called on the main thread" }
        val api = flutterApi ?: throw C2PAError.Api("$name: the Flutter engine is detached")
        val latch = CountDownLatch(1)
        var outcome: Result<T>? = null
        mainHandler.post {
            try {
                invoke(api) { result ->
                    outcome = result
                    latch.countDown()
                }
            } catch (e: Exception) {
                outcome = Result.failure(e)
                latch.countDown()
            }
        }
        latch.await()
        return outcome!!.getOrElse { error ->
            val message = (error as? FlutterError)?.let { it.message ?: it.code } ?: error.message
            throw C2PAError.Api("$name failed in Dart: $message")
        }
    }

    // =========================================================================
    // Version and MIME types
    // =========================================================================

    override fun getPlatformVersion(): String = "Android ${android.os.Build.VERSION.RELEASE}"

    override fun getVersion(callback: (Result<String>) -> Unit) = onWorker(callback) { C2PA.version() }

    override fun getSupportedReadMimeTypes(callback: (Result<List<String>>) -> Unit) =
        onWorker(callback) { Reader.supportedMimeTypes() }

    override fun getSupportedSignMimeTypes(callback: (Result<List<String>>) -> Unit) =
        onWorker(callback) { Builder.supportedMimeTypes() }

    // =========================================================================
    // Reading
    // =========================================================================

    override fun readFile(
        path: String,
        mimeType: String?,
        format: ReadFormatMessage,
        contextHandle: Long?,
        callback: (Result<String>) -> Unit,
    ) = onWorker(callback) {
        withPathReader(path, mimeType, contextHandle) { readerOutput(it, format) }
    }

    override fun readBytes(
        data: ByteArray,
        mimeType: String,
        format: ReadFormatMessage,
        contextHandle: Long?,
        callback: (Result<String>) -> Unit,
    ) = onWorker(callback) {
        ByteArrayStream(data).use { stream ->
            newReader(contextHandle, mimeType, stream).use { readerOutput(it, format) }
        }
    }

    override fun readWithManifest(
        path: String?,
        data: ByteArray?,
        mimeType: String?,
        manifestData: ByteArray,
        format: ReadFormatMessage,
        contextHandle: Long?,
        callback: (Result<String>) -> Unit,
    ) = onWorker(callback) {
        // c2pa-android has no context-aware form of this reader; contextHandle is ignored.
        if ((path == null) == (data == null)) throw invalidArgument("Provide exactly one of path or data")
        val resolvedMimeType = mimeType
            ?: if (path != null) mimeTypeForPath(path) else throw invalidArgument("mimeType is required")
        val stream: Stream = if (data != null) ByteArrayStream(data) else openForRead(path!!)
        stream.use { s ->
            Reader.fromManifestAndStream(resolvedMimeType, s, manifestData).use { readerOutput(it, format) }
        }
    }

    override fun readFragment(
        initPath: String,
        fragmentPath: String,
        mimeType: String?,
        format: ReadFormatMessage,
        contextHandle: Long?,
        callback: (Result<String>) -> Unit,
    ) = onWorker(callback) {
        val resolvedMimeType = mimeType ?: mimeTypeForPath(initPath)
        openForRead(initPath).use { initStream ->
            openForRead(fragmentPath).use { fragment ->
                withContext(contextHandle) { ctx ->
                    val owned = if (ctx == null) C2PAContext.create() else null
                    try {
                        Reader.fromContext(ctx ?: owned!!).withFragment(resolvedMimeType, initStream, fragment)
                            .use { readerOutput(it, format) }
                    } finally {
                        owned?.close()
                    }
                }
            }
        }
    }

    override fun extractResource(
        data: ByteArray,
        mimeType: String,
        uri: String,
        contextHandle: Long?,
        callback: (Result<ByteArray>) -> Unit,
    ) = onWorker(callback) {
        ByteArrayStream(data).use { stream ->
            newReader(contextHandle, mimeType, stream).use { reader ->
                ByteArrayStream().use { out ->
                    reader.resource(uri, out)
                    out.getData()
                }
            }
        }
    }

    override fun getRemoteUrl(path: String, mimeType: String?, callback: (Result<String?>) -> Unit) =
        onWorker(callback) { withPathReader(path, mimeType, null) { it.remoteUrl() } }

    override fun isManifestEmbedded(path: String, mimeType: String?, callback: (Result<Boolean>) -> Unit) =
        onWorker(callback) { withPathReader(path, mimeType, null) { it.isEmbedded() } }

    private fun readerOutput(reader: Reader, format: ReadFormatMessage): String =
        when (format) {
            ReadFormatMessage.JSON -> reader.json()
            ReadFormatMessage.DETAILED -> reader.detailedJson()
            ReadFormatMessage.CR_JSON -> reader.crJSON()
        }

    private fun <R> withPathReader(path: String, mimeType: String?, contextHandle: Long?, block: (Reader) -> R): R =
        openForRead(path).use { stream ->
            newReader(contextHandle, mimeType ?: mimeTypeForPath(path), stream).use(block)
        }

    // =========================================================================
    // One-shot signing
    // =========================================================================

    override fun signBytes(
        sourceData: ByteArray,
        mimeType: String,
        manifestJson: String,
        signer: SignerMessage,
        callback: (Result<SignResultMessage>) -> Unit,
    ) = onWorker(callback) {
        ByteArrayStream(sourceData).use { source ->
            ByteArrayStream().use { dest ->
                val result = oneShotSign(manifestJson, signer, mimeType, source, dest)
                signResult(result, dest.getData())
            }
        }
    }

    override fun signFile(
        sourcePath: String,
        destPath: String,
        manifestJson: String,
        signer: SignerMessage,
        callback: (Result<Unit>) -> Unit,
    ) = onWorker(callback) {
        openForRead(sourcePath).use { source ->
            openForWrite(destPath).use { dest ->
                oneShotSign(manifestJson, signer, mimeTypeForPath(sourcePath), source, dest)
            }
        }
        Unit
    }

    private fun oneShotSign(
        manifestJson: String,
        signer: SignerMessage,
        mimeType: String,
        source: Stream,
        dest: Stream,
    ): Builder.SignResult =
        if (signer is SettingsSignerMessage) {
            settingsFromSigner(signer).use { s ->
                Builder.fromJson(manifestJson, s).use { it.signWithContext(mimeType, source, dest) }
            }
        } else {
            newBuilder(null, manifestJson).use { signWith(it, signer, mimeType, source, dest) }
        }

    override fun getSignerReserveSize(signer: SignerMessage, callback: (Result<Long>) -> Unit) =
        onWorker(callback) { signers.create(signer).use { it.reserveSize().toLong() } }

    override fun composeManifest(manifestBytes: ByteArray, mimeType: String, callback: (Result<ByteArray>) -> Unit) =
        onWorker(callback) {
            C2PAContext.create().use { ctx ->
                Builder.fromContext(ctx).use { it.composeManifest(mimeType, manifestBytes) }
            }
        }

    // =========================================================================
    // Builder lifecycle and configuration
    // =========================================================================

    override fun createBuilder(manifestJson: String, contextHandle: Long?, callback: (Result<Long>) -> Unit) =
        onWorker(callback) { builders.store(newBuilder(contextHandle, manifestJson)).toLong() }

    override fun createBuilderWithSettings(
        manifestJson: String,
        settingsHandle: Long,
        callback: (Result<Long>) -> Unit,
    ) = onWorker(callback) {
        builders.store(Builder.fromJson(manifestJson, settingsFor(settingsHandle))).toLong()
    }

    override fun createBuilderFromArchive(
        archiveData: ByteArray,
        contextHandle: Long?,
        callback: (Result<Long>) -> Unit,
    ) = onWorker(callback) {
        val stream = ByteArrayStream(archiveData)
        val builder = withContext(contextHandle) { ctx ->
            if (ctx == null) Builder.fromArchive(stream) else Builder.fromContext(ctx).withArchive(stream)
        }
        builders.store(builder).toLong()
    }

    override fun builderDispose(handle: Long, callback: (Result<Unit>) -> Unit) =
        onWorker(callback) { builders.remove(handle.toInt())?.close() ?: Unit }

    override fun builderSetIntent(
        handle: Long,
        intent: ManifestIntentMessage,
        digitalSourceType: String?,
        callback: (Result<Unit>) -> Unit,
    ) = onWorker(callback) { builder(handle).setIntent(intent.toSdk(digitalSourceType)) }

    override fun builderSetNoEmbed(handle: Long, callback: (Result<Unit>) -> Unit) =
        onWorker(callback) { builder(handle).setNoEmbed() }

    override fun builderSetRemoteUrl(handle: Long, url: String, callback: (Result<Unit>) -> Unit) =
        onWorker(callback) { builder(handle).setRemoteURL(url) }

    override fun builderSetBasePath(handle: Long, path: String, callback: (Result<Unit>) -> Unit) =
        onWorker(callback) { builder(handle).setBasePath(path) }

    override fun builderAddResource(handle: Long, uri: String, data: ByteArray, callback: (Result<Unit>) -> Unit) =
        onWorker(callback) { ByteArrayStream(data).use { builder(handle).addResource(uri, it) } }

    override fun builderAddIngredient(
        handle: Long,
        data: ByteArray,
        mimeType: String,
        ingredientJson: String?,
        callback: (Result<Unit>) -> Unit,
    ) = onWorker(callback) {
        ByteArrayStream(data).use { builder(handle).addIngredient(ingredientJson ?: "{}", mimeType, it) }
    }

    override fun builderAddIngredientFromFile(
        handle: Long,
        path: String,
        mimeType: String?,
        ingredientJson: String?,
        callback: (Result<Unit>) -> Unit,
    ) = onWorker(callback) {
        openForRead(path).use {
            builder(handle).addIngredient(ingredientJson ?: "{}", mimeType ?: mimeTypeForPath(path), it)
        }
    }

    override fun builderAddIngredientFromArchive(
        handle: Long,
        archiveData: ByteArray,
        callback: (Result<Unit>) -> Unit,
    ) = onWorker(callback) { ByteArrayStream(archiveData).use { builder(handle).addIngredientFromArchive(it) } }

    override fun builderWriteIngredientArchive(
        handle: Long,
        ingredientId: String,
        callback: (Result<ByteArray>) -> Unit,
    ) = onWorker(callback) {
        ByteArrayStream().use {
            builder(handle).writeIngredientArchive(ingredientId, it)
            it.getData()
        }
    }

    override fun builderAddAction(handle: Long, actionJson: String, callback: (Result<Unit>) -> Unit) =
        onWorker(callback) { builder(handle).addAction(parseAction(actionJson)) }

    override fun builderToArchive(handle: Long, callback: (Result<ByteArray>) -> Unit) =
        onWorker(callback) {
            ByteArrayStream().use {
                builder(handle).toArchive(it)
                it.getData()
            }
        }

    // =========================================================================
    // Builder signing
    // =========================================================================

    override fun builderSign(
        handle: Long,
        sourceData: ByteArray,
        mimeType: String,
        signer: SignerMessage?,
        callback: (Result<SignResultMessage>) -> Unit,
    ) = onWorker(callback) {
        val builder = builder(handle)
        ByteArrayStream(sourceData).use { source ->
            ByteArrayStream().use { dest ->
                signResult(signWith(builder, signer, mimeType, source, dest), dest.getData())
            }
        }
    }

    override fun builderSignFile(
        handle: Long,
        sourcePath: String,
        destPath: String,
        mimeType: String?,
        signer: SignerMessage?,
        callback: (Result<SignResultMessage>) -> Unit,
    ) = onWorker(callback) {
        val builder = builder(handle)
        val result = openForRead(sourcePath).use { source ->
            openForWrite(destPath).use { dest ->
                signWith(builder, signer, mimeType ?: mimeTypeForPath(sourcePath), source, dest)
            }
        }
        signResult(result, null)
    }

    /** Signs with [signer], or with the builder's context signer when [signer] is null. */
    private fun signWith(
        builder: Builder,
        signer: SignerMessage?,
        mimeType: String,
        source: Stream,
        dest: Stream,
    ): Builder.SignResult {
        if (signer == null) return builder.signWithContext(mimeType, source, dest)
        return signers.create(signer).use { builder.sign(mimeType, source, dest, it) }
    }

    private fun signResult(result: Builder.SignResult, signedData: ByteArray?): SignResultMessage =
        SignResultMessage(
            signedData = signedData,
            manifestBytes = result.manifestBytes,
            manifestSize = (result.manifestBytes?.size?.toLong() ?: result.size),
        )

    // =========================================================================
    // Embeddable / data-hash / BMFF flows
    // =========================================================================

    override fun builderNeedsPlaceholder(handle: Long, mimeType: String, callback: (Result<Boolean>) -> Unit) =
        onWorker(callback) { builder(handle).needsPlaceholder(mimeType) }

    override fun builderPlaceholder(handle: Long, mimeType: String, callback: (Result<ByteArray>) -> Unit) =
        onWorker(callback) { builder(handle).placeholder(mimeType) }

    override fun builderSetDataHashExclusions(
        handle: Long,
        exclusions: List<DataHashExclusionMessage>,
        callback: (Result<Unit>) -> Unit,
    ) = onWorker(callback) {
        builder(handle).setDataHashExclusions(exclusions.map { it.start to it.length })
    }

    override fun builderUpdateHashFromBytes(
        handle: Long,
        mimeType: String,
        data: ByteArray,
        callback: (Result<Unit>) -> Unit,
    ) = onWorker(callback) { ByteArrayStream(data).use { builder(handle).updateHashFromStream(mimeType, it) } }

    override fun builderUpdateHashFromFile(
        handle: Long,
        path: String,
        mimeType: String?,
        callback: (Result<Unit>) -> Unit,
    ) = onWorker(callback) {
        openForRead(path).use { builder(handle).updateHashFromStream(mimeType ?: mimeTypeForPath(path), it) }
    }

    override fun builderSignEmbeddable(handle: Long, mimeType: String, callback: (Result<ByteArray>) -> Unit) =
        onWorker(callback) { builder(handle).signEmbeddable(mimeType) }

    override fun builderHashType(handle: Long, mimeType: String, callback: (Result<HashTypeMessage>) -> Unit) =
        onWorker(callback) { builder(handle).hashType(mimeType).toMessage() }

    override fun builderSetFixedSizeMerkle(handle: Long, fixedSizeKb: Long, callback: (Result<Unit>) -> Unit) =
        onWorker(callback) { builder(handle).setFixedSizeMerkle(fixedSizeKb) }

    override fun builderHashMdatBytes(
        handle: Long,
        mdatId: Long,
        data: ByteArray,
        largeSize: Boolean,
        callback: (Result<Unit>) -> Unit,
    ) = onWorker(callback) { builder(handle).hashMdatBytes(mdatId, data, largeSize) }

    // =========================================================================
    // Key management
    // =========================================================================

    override fun isHardwareSigningAvailable(callback: (Result<Boolean>) -> Unit) =
        onAux(callback) { keys.isHardwareSigningAvailable() }

    override fun createKey(
        keyAlias: String,
        algorithm: SigningAlgorithmMessage,
        useHardware: Boolean,
        callback: (Result<Unit>) -> Unit,
    ) = onAux(callback) { keys.createKey(keyAlias, algorithm, useHardware) }

    override fun deleteKey(keyAlias: String, callback: (Result<Boolean>) -> Unit) =
        onAux(callback) { keys.deleteKey(keyAlias) }

    override fun keyExists(keyAlias: String, callback: (Result<Boolean>) -> Unit) =
        onAux(callback) { keys.keyExists(keyAlias) }

    override fun exportPublicKey(keyAlias: String, callback: (Result<String>) -> Unit) =
        onAux(callback) { keys.exportPublicKey(keyAlias) }

    override fun importKey(
        keyAlias: String,
        privateKeyPem: String,
        certificateChainPem: String,
        callback: (Result<Unit>) -> Unit,
    ) = onAux(callback) { keys.importKey(keyAlias, privateKeyPem, certificateChainPem) }

    override fun createCSR(keyAlias: String, config: CertificateConfigMessage, callback: (Result<String>) -> Unit) =
        onAux(callback) { keys.createCSR(keyAlias, config) }

    override fun enrollHardwareKey(
        keyAlias: String,
        signingServerUrl: String,
        bearerToken: String?,
        commonName: String?,
        organization: String?,
        useStrongBox: Boolean,
        callback: (Result<HardwareKeyEnrollmentMessage>) -> Unit,
    ) = onAux(callback) {
        keys.enrollHardwareKey(keyAlias, signingServerUrl, bearerToken, commonName, organization, useStrongBox)
    }

    override fun createSelfSignedCertificateChain(
        keyAlias: String,
        config: CertificateConfigMessage?,
        callback: (Result<String>) -> Unit,
    ) = onAux(callback) {
        throw PluginError(
            "NOT_IMPLEMENTED_ANDROID",
            "createSelfSignedCertificateChain is not available in c2pa-android",
        )
    }

    // =========================================================================
    // Settings
    // =========================================================================

    override fun loadSettings(settings: String, format: String, callback: (Result<Unit>) -> Unit) =
        onWorker(callback) {
            val defaults = defaultSettings ?: C2PASettings.create().also {
                it.updateFromString(defaultLabelsJson(), "json")
                defaultSettings = it
            }
            defaults.updateFromString(settings, format.lowercase())
            Unit
        }

    override fun createSettings(callback: (Result<Long>) -> Unit) =
        onWorker(callback) { settingsHandles.store(C2PASettings.create()).toLong() }

    override fun settingsUpdateFromString(
        handle: Long,
        settings: String,
        format: String,
        callback: (Result<Unit>) -> Unit,
    ) = onWorker(callback) {
        settingsFor(handle).updateFromString(settings, format.lowercase())
        Unit
    }

    override fun settingsSetValue(handle: Long, path: String, jsonValue: String, callback: (Result<Unit>) -> Unit) =
        onWorker(callback) {
            settingsFor(handle).setValue(path, jsonValue)
            Unit
        }

    override fun settingsDispose(handle: Long, callback: (Result<Unit>) -> Unit) =
        onWorker(callback) { settingsHandles.remove(handle.toInt())?.close() ?: Unit }

    // =========================================================================
    // Contexts
    // =========================================================================

    override fun createContext(
        settingsHandle: Long?,
        signer: SignerMessage?,
        reportProgress: Boolean,
        httpResolver: HttpResolverModeMessage?,
        callback: (Result<Long>) -> Unit,
    ) = onWorker(callback) {
        val settings = settingsHandle?.let { settingsFor(it) }
        val handle = contexts.reserve()
        val context = if (signer == null && !reportProgress && httpResolver == null) {
            settings?.let { C2PAContext.fromSettings(it) } ?: C2PAContext.create()
        } else {
            val builder = C2PAContextBuilder.create()
            try {
                settings?.let { builder.setSettings(it) }
                signer?.let { builder.setSigner(signers.create(it)) }
                if (reportProgress) {
                    builder.setProgressCallback(ProgressObserver { update -> postProgress(handle, update) })
                }
                when (httpResolver) {
                    null -> Unit
                    HttpResolverModeMessage.NATIVE -> builder.setHttpResolver(OkHttpClient())
                    HttpResolverModeMessage.CALLBACK -> builder.setHttpResolver(
                        HttpResolver { request -> resolveInDart(handle, request) },
                    )
                }
                builder.build()
            } catch (e: Exception) {
                builder.close()
                throw e
            }
        }
        contexts.put(handle, context)
        handle.toLong()
    }

    override fun contextCancel(handle: Long) {
        try {
            contexts.get(handle.toInt())?.cancel() ?: throw invalidHandle("context")
        } catch (e: Exception) {
            throw toFlutterError(e)
        }
    }

    override fun contextDispose(handle: Long, callback: (Result<Unit>) -> Unit) =
        onWorker(callback) { contexts.remove(handle.toInt())?.close() ?: Unit }

    private fun postProgress(handle: Int, update: org.contentauth.c2pa.ProgressUpdate) {
        val phase = progressPhaseName(update.phase)
        mainHandler.post {
            flutterApi?.progress(handle.toLong(), phase, update.step.toLong(), update.total.toLong()) {}
        }
    }

    private fun resolveInDart(handle: Int, request: org.contentauth.c2pa.HttpRequest): HttpResponse {
        val response = callDart<HttpResponseMessage>("resolveHttp") { api, reply ->
            api.resolveHttp(
                handle.toLong(),
                HttpRequestMessage(
                    url = request.url,
                    method = request.method,
                    headers = request.headers,
                    body = request.body,
                ),
                reply,
            )
        }
        if (response.status !in 0L..999L) {
            throw C2PAError.Api("HTTP resolver status ${response.status} is out of range")
        }
        return HttpResponse(response.status.toInt(), response.body)
    }

    // =========================================================================
    // Handle lookup and factories
    // =========================================================================

    private fun builder(handle: Long): Builder =
        builders.get(handle.toInt()) ?: throw invalidHandle("builder")

    private fun settingsFor(handle: Long): C2PASettings =
        settingsHandles.get(handle.toInt()) ?: throw invalidHandle("settings")

    private fun contextFor(handle: Long): C2PAContext =
        contexts.get(handle.toInt()) ?: throw invalidHandle("context")

    /** Runs [block] with a context for [contextHandle], or a short-lived one built from the default settings. */
    private fun <R> withContext(contextHandle: Long?, block: (C2PAContext?) -> R): R {
        if (contextHandle != null) return block(contextFor(contextHandle))
        val defaults = defaultSettings ?: return block(null)
        // A context without callbacks may be closed once readers/builders exist.
        return C2PAContext.fromSettings(defaults).use { block(it) }
    }

    private fun newReader(contextHandle: Long?, mimeType: String, stream: Stream): Reader =
        withContext(contextHandle) { ctx ->
            if (ctx == null) Reader.fromStream(mimeType, stream) else Reader.fromContext(ctx).withStream(mimeType, stream)
        }

    private fun newBuilder(contextHandle: Long?, manifestJson: String): Builder {
        if (contextHandle != null) return Builder.fromContext(contextFor(contextHandle)).withDefinition(manifestJson)
        val defaults = defaultSettings ?: return Builder.fromJson(manifestJson)
        return Builder.fromJson(manifestJson, defaults)
    }

    /** Settings for a one-shot SettingsSigner, seeded the way Builder.fromJson(json) seeds its own. */
    private fun settingsFromSigner(signer: SettingsSignerMessage): C2PASettings {
        val settings = C2PASettings.create()
        try {
            settings.updateFromString(defaultLabelsJson(), "json")
            settings.updateFromString(signer.settings, signer.format.lowercase())
        } catch (e: Exception) {
            settings.close()
            throw e
        }
        return settings
    }

    private fun defaultLabelsJson(): String {
        val labels = Builder.DEFAULT_CREATED_ASSERTION_LABELS.joinToString(",") { "\"$it\"" }
        return """{"version":1,"builder":{"created_assertion_labels":[$labels]}}"""
    }

    private fun parseAction(actionJson: String): Action {
        val obj = Json.parseToJsonElement(actionJson).jsonObject
        val name = obj["action"]?.jsonPrimitive?.contentOrNull ?: throw invalidArgument("action is required")
        val digitalSourceType = obj["digitalSourceType"]?.jsonPrimitive?.contentOrNull
        val softwareAgent = obj["softwareAgent"]?.takeUnless { it is JsonNull }
        val parameters = obj["parameters"]?.takeUnless { it is JsonNull }?.jsonObject?.toMap()
        return Action(name, digitalSourceType, softwareAgent, parameters)
    }
}
