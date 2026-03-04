package org.guardianproject.c2pa

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.contentauth.c2pa.C2PA
import org.contentauth.c2pa.C2PAContext
import org.contentauth.c2pa.C2PASettings
import org.contentauth.c2pa.Reader
import org.contentauth.c2pa.Builder
import org.contentauth.c2pa.Signer
import org.contentauth.c2pa.SignerInfo
import org.contentauth.c2pa.SigningAlgorithm
import org.contentauth.c2pa.ByteArrayStream
import org.contentauth.c2pa.C2PAError
import org.contentauth.c2pa.BuilderIntent
import org.contentauth.c2pa.DigitalSourceType
import org.contentauth.c2pa.Action
import org.contentauth.c2pa.KeyStoreSigner
import org.contentauth.c2pa.StrongBoxSigner
import org.contentauth.c2pa.WebServiceSigner
import org.contentauth.c2pa.CertificateManager
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.StringReader
import java.security.KeyFactory
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64
import java.util.concurrent.locks.ReentrantLock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

class C2paPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: android.content.Context? = null
    private val mainScope = CoroutineScope(Dispatchers.Main)

    // Builder handle management
    private val builders = HashMap<Int, Builder>()
    private var nextBuilderHandle = 1
    private val builderLock = ReentrantLock()

    // Settings handle management
    private val settings = HashMap<Int, C2PASettings>()
    private var nextSettingsHandle = 1
    private val settingsLock = ReentrantLock()

    // Context handle management
    private val contexts = HashMap<Int, C2PAContext>()
    private var nextContextHandle = 1
    private val contextLock = ReentrantLock()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "org.guardianproject.c2pa")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // Version and Platform Info
            "getPlatformVersion" -> handleGetPlatformVersion(result)
            "getVersion" -> handleGetVersion(result)

            // Reader API - Basic
            "readFile" -> handleReadFile(call, result)
            "readBytes" -> handleReadBytes(call, result)

            // Reader API - Enhanced
            "readFileDetailed" -> handleReadFileDetailed(call, result)
            "readBytesDetailed" -> handleReadBytesDetailed(call, result)
            "extractResource" -> handleExtractResource(call, result)
            "readIngredientFile" -> handleReadIngredientFile(call, result)
            "getSupportedReadMimeTypes" -> handleGetSupportedReadMimeTypes(result)
            "getSupportedSignMimeTypes" -> handleGetSupportedSignMimeTypes(result)

            // Signer API - Basic
            "signBytes" -> handleSignBytes(call, result)
            "signFile" -> handleSignFile(call, result)

            // Builder API
            "createBuilder" -> handleCreateBuilder(call, result)
            "createBuilderFromArchive" -> handleCreateBuilderFromArchive(call, result)
            "builderSetIntent" -> handleBuilderSetIntent(call, result)
            "builderSetNoEmbed" -> handleBuilderSetNoEmbed(call, result)
            "builderSetRemoteUrl" -> handleBuilderSetRemoteUrl(call, result)
            "builderAddResource" -> handleBuilderAddResource(call, result)
            "builderAddIngredient" -> handleBuilderAddIngredient(call, result)
            "builderAddIngredientFromFile" -> handleBuilderAddIngredientFromFile(call, result)
            "builderAddAction" -> handleBuilderAddAction(call, result)
            "builderToArchive" -> handleBuilderToArchive(call, result)
            "builderSign" -> handleBuilderSign(call, result)
            "builderSignFile" -> handleBuilderSignFile(call, result)
            "builderDispose" -> handleBuilderDispose(call, result)

            // Advanced Signing API
            "createHashedPlaceholder" -> handleCreateHashedPlaceholder(call, result)
            "signHashedEmbeddable" -> handleSignHashedEmbeddable(call, result)
            "formatEmbeddable" -> handleFormatEmbeddable(call, result)
            "getSignerReserveSize" -> handleGetSignerReserveSize(call, result)

            // Settings API
            "loadSettings" -> handleLoadSettings(call, result)

            // Settings Handle API
            "createSettings" -> handleCreateSettings(result)
            "settingsUpdateFromString" -> handleSettingsUpdateFromString(call, result)
            "settingsSetValue" -> handleSettingsSetValue(call, result)
            "settingsDispose" -> handleSettingsDispose(call, result)

            // Context Handle API
            "createContext" -> handleCreateContext(result)
            "createContextFromSettings" -> handleCreateContextFromSettings(call, result)
            "contextDispose" -> handleContextDispose(call, result)

            // Enhanced Reader with Context
            "readFileWithContext" -> handleReadFileWithContext(call, result)

            // Enhanced Builder with Context/Settings
            "createBuilderWithContext" -> handleCreateBuilderWithContext(call, result)
            "createBuilderWithSettings" -> handleCreateBuilderWithSettings(call, result)

            // Certificate Manager
            "createSelfSignedCertificateChain" -> handleCreateSelfSignedCertificateChain(call, result)

            // Key Management API
            "isHardwareSigningAvailable" -> handleIsHardwareSigningAvailable(result)
            "createKey" -> handleCreateKey(call, result)
            "deleteKey" -> handleDeleteKey(call, result)
            "keyExists" -> handleKeyExists(call, result)
            "exportPublicKey" -> handleExportPublicKey(call, result)
            "importKey" -> handleImportKey(call, result)
            "createCSR" -> handleCreateCSR(call, result)
            "enrollHardwareKey" -> handleEnrollHardwareKey(call, result)

            else -> result.notImplemented()
        }
    }

    // ===========================================================================
    // Version and Platform Info
    // ===========================================================================

    private fun handleGetPlatformVersion(result: Result) {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
    }

    private fun handleGetVersion(result: Result) {
        try {
            val version = C2PA.version()
            result.success(version)
        } catch (e: Exception) {
            result.success("unknown")
        }
    }

    // ===========================================================================
    // Reader API - Basic
    // ===========================================================================

    private fun handleReadFile(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("INVALID_ARGUMENT", "Path is required", null)
            return
        }
        try {
            val json = C2PA.readFile(path, null)
            result.success(json)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleReadBytes(call: MethodCall, result: Result) {
        val data = call.argument<ByteArray>("data")
        val mimeType = call.argument<String>("mimeType")
        if (data == null || mimeType == null) {
            result.error("INVALID_ARGUMENT", "Data and mimeType are required", null)
            return
        }
        try {
            val stream = ByteArrayStream(data)
            val reader = Reader.fromStream(mimeType, stream)
            val json = reader.json()
            reader.close()
            result.success(json)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Reader API - Enhanced
    // ===========================================================================

    private fun handleReadFileDetailed(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        val detailed = call.argument<Boolean>("detailed") ?: false
        val dataDir = call.argument<String>("dataDir")

        if (path == null) {
            result.error("INVALID_ARGUMENT", "Path is required", null)
            return
        }

        try {
            // Read the file using the static API with dataDir for resource extraction
            val json = C2PA.readFile(path, dataDir)
            result.success(json)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleReadBytesDetailed(call: MethodCall, result: Result) {
        val data = call.argument<ByteArray>("data")
        val mimeType = call.argument<String>("mimeType")
        val detailed = call.argument<Boolean>("detailed") ?: false

        if (data == null || mimeType == null) {
            result.error("INVALID_ARGUMENT", "Data and mimeType are required", null)
            return
        }

        try {
            val stream = ByteArrayStream(data)
            val reader = Reader.fromStream(mimeType, stream)
            val json = reader.json()
            reader.close()
            result.success(json)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleExtractResource(call: MethodCall, result: Result) {
        val data = call.argument<ByteArray>("data")
        val mimeType = call.argument<String>("mimeType")
        val uri = call.argument<String>("uri")

        if (data == null || mimeType == null || uri == null) {
            result.error("INVALID_ARGUMENT", "Data, mimeType, and uri are required", null)
            return
        }

        try {
            val stream = ByteArrayStream(data)
            val reader = Reader.fromStream(mimeType, stream)
            val resourceStream = ByteArrayStream()
            reader.resource(uri, resourceStream)
            val resourceData = resourceStream.getData()
            reader.close()
            result.success(resourceData)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleReadIngredientFile(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        val dataDir = call.argument<String>("dataDir")

        if (path == null) {
            result.error("INVALID_ARGUMENT", "Path is required", null)
            return
        }

        try {
            val json = C2PA.readIngredientFile(path, dataDir)
            result.success(json)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleGetSupportedReadMimeTypes(result: Result) {
        // Return common supported MIME types - the C2PA library supports these formats
        val mimeTypes = listOf(
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
            "image/tiff",
            "image/heic",
            "image/heif",
            "image/avif",
            "video/mp4",
            "video/quicktime",
            "audio/mp4",
            "application/mp4",
            "audio/mpeg",
            "application/pdf",
            "image/svg+xml"
        )
        result.success(mimeTypes)
    }

    private fun handleGetSupportedSignMimeTypes(result: Result) {
        // Return common supported MIME types for signing
        val mimeTypes = listOf(
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
            "image/tiff",
            "image/heic",
            "image/heif",
            "image/avif",
            "video/mp4",
            "video/quicktime",
            "audio/mp4",
            "application/mp4",
            "audio/mpeg",
            "application/pdf",
            "image/svg+xml"
        )
        result.success(mimeTypes)
    }

    // ===========================================================================
    // Signer API - Basic
    // ===========================================================================

    private fun handleSignBytes(call: MethodCall, result: Result) {
        val sourceData = call.argument<ByteArray>("sourceData")
        val mimeType = call.argument<String>("mimeType")
        val manifestJson = call.argument<String>("manifestJson")
        val signerMap = call.argument<Map<String, Any?>>("signer")

        if (sourceData == null || mimeType == null || manifestJson == null || signerMap == null) {
            result.error("INVALID_ARGUMENT", "sourceData, mimeType, manifestJson, and signer are required", null)
            return
        }

        val signerType = signerMap["type"] as? String ?: "pem"

        // Handle async signers (remote, callback) on background thread to avoid deadlock
        if (signerType == "remote" || signerType == "callback") {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val signer = createSignerAsync(signerMap)
                    val builder = Builder.fromJson(manifestJson)
                    val sourceStream = ByteArrayStream(sourceData)
                    val destStream = ByteArrayStream()

                    val signResult = builder.sign(mimeType, sourceStream, destStream, signer)
                    val signedData = destStream.getData()

                    builder.close()
                    signer.close()

                    val resultMap = HashMap<String, Any?>()
                    resultMap["signedData"] = signedData
                    resultMap["manifestBytes"] = signResult.manifestBytes

                    mainScope.launch {
                        result.success(resultMap)
                    }
                } catch (e: C2PAError) {
                    mainScope.launch {
                        result.error("C2PA_ERROR", e.message, null)
                    }
                } catch (e: Exception) {
                    mainScope.launch {
                        result.error("ERROR", e.message, null)
                    }
                }
            }
        } else {
            try {
                val signer = createSigner(signerMap, result) ?: return
                performSignBytes(sourceData, mimeType, manifestJson, signer, result)
                signer.close()
            } catch (e: C2PAError) {
                result.error("C2PA_ERROR", e.message, null)
            } catch (e: Exception) {
                result.error("ERROR", e.message, null)
            }
        }
    }

    private fun performSignBytes(
        sourceData: ByteArray,
        mimeType: String,
        manifestJson: String,
        signer: Signer,
        result: Result
    ) {
        val builder = Builder.fromJson(manifestJson)
        val sourceStream = ByteArrayStream(sourceData)
        val destStream = ByteArrayStream()

        val signResult = builder.sign(mimeType, sourceStream, destStream, signer)

        val signedData = destStream.getData()

        builder.close()

        val resultMap = HashMap<String, Any?>()
        resultMap["signedData"] = signedData
        resultMap["manifestBytes"] = signResult.manifestBytes

        result.success(resultMap)
    }

    private fun handleSignFile(call: MethodCall, result: Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val destPath = call.argument<String>("destPath")
        val manifestJson = call.argument<String>("manifestJson")
        val signerMap = call.argument<Map<String, Any?>>("signer")

        if (sourcePath == null || destPath == null || manifestJson == null || signerMap == null) {
            result.error("INVALID_ARGUMENT", "sourcePath, destPath, manifestJson, and signer are required", null)
            return
        }

        val signerType = signerMap["type"] as? String ?: "pem"

        // For PEM signers, use the static API
        if (signerType == "pem") {
            try {
                val algorithmStr = signerMap["algorithm"] as String
                val certificatePem = signerMap["certificatePem"] as String
                val privateKeyPem = signerMap["privateKeyPem"] as String
                val tsaUrl = signerMap["tsaUrl"] as String?
                val algorithm = parseAlgorithm(algorithmStr)
                val signerInfo = SignerInfo(algorithm, certificatePem, privateKeyPem, tsaUrl)
                C2PA.signFile(sourcePath, destPath, manifestJson, signerInfo, null)
                result.success(null)
            } catch (e: C2PAError) {
                result.error("C2PA_ERROR", e.message, null)
            } catch (e: Exception) {
                result.error("ERROR", e.message, null)
            }
        } else {
            // For other signer types (callback, remote, keystore, hardware),
            // run on IO thread to avoid deadlock with callback signers
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val signer = createSignerAsync(signerMap)
                    val sourceFile = File(sourcePath)
                    val sourceData = sourceFile.readBytes()
                    val mimeType = getMimeTypeFromPath(sourcePath)

                    val builder = Builder.fromJson(manifestJson)
                    val sourceStream = ByteArrayStream(sourceData)
                    val destStream = ByteArrayStream()

                    builder.sign(mimeType, sourceStream, destStream, signer)

                    val destFile = File(destPath)
                    destFile.writeBytes(destStream.getData())

                    builder.close()
                    signer.close()

                    mainScope.launch {
                        result.success(null)
                    }
                } catch (e: C2PAError) {
                    mainScope.launch {
                        result.error("C2PA_ERROR", e.message, null)
                    }
                } catch (e: Exception) {
                    mainScope.launch {
                        result.error("ERROR", e.message, null)
                    }
                }
            }
        }
    }

    // ===========================================================================
    // Builder API
    // ===========================================================================

    private fun handleCreateBuilder(call: MethodCall, result: Result) {
        val manifestJson = call.argument<String>("manifestJson")

        if (manifestJson == null) {
            result.error("INVALID_ARGUMENT", "manifestJson is required", null)
            return
        }

        try {
            val builder = Builder.fromJson(manifestJson)
            val handle = storeBuilder(builder)
            result.success(handle)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleCreateBuilderFromArchive(call: MethodCall, result: Result) {
        val archiveData = call.argument<ByteArray>("archiveData")

        if (archiveData == null) {
            result.error("INVALID_ARGUMENT", "archiveData is required", null)
            return
        }

        try {
            val stream = ByteArrayStream(archiveData)
            val builder = Builder.fromArchive(stream)
            val handle = storeBuilder(builder)
            result.success(handle)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderSetIntent(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val intentStr = call.argument<String>("intent")
        val digitalSourceTypeStr = call.argument<String>("digitalSourceType")

        if (handle == null || intentStr == null) {
            result.error("INVALID_ARGUMENT", "handle and intent are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            // Map the digital source type if provided, otherwise use default
            val digitalSourceType = if (digitalSourceTypeStr != null) {
                mapDigitalSourceType(digitalSourceTypeStr)
            } else {
                DigitalSourceType.DIGITAL_CAPTURE
            }

            val intent = mapIntent(intentStr, digitalSourceType)
            builder.setIntent(intent)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderSetNoEmbed(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")

        if (handle == null) {
            result.error("INVALID_ARGUMENT", "handle is required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            builder.setNoEmbed()
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderSetRemoteUrl(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val url = call.argument<String>("url")

        if (handle == null || url == null) {
            result.error("INVALID_ARGUMENT", "handle and url are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            builder.setRemoteURL(url)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderAddResource(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val uri = call.argument<String>("uri")
        val data = call.argument<ByteArray>("data")

        if (handle == null || uri == null || data == null) {
            result.error("INVALID_ARGUMENT", "handle, uri, and data are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            val stream = ByteArrayStream(data)
            builder.addResource(uri, stream)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderAddIngredient(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val data = call.argument<ByteArray>("data")
        val mimeType = call.argument<String>("mimeType")
        val ingredientJson = call.argument<String>("ingredientJson")

        if (handle == null || data == null || mimeType == null) {
            result.error("INVALID_ARGUMENT", "handle, data, and mimeType are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            val stream = ByteArrayStream(data)
            // API signature: addIngredient(ingredientJson, mimeType, stream)
            // Use empty JSON object if ingredientJson is null
            builder.addIngredient(ingredientJson ?: "{}", mimeType, stream)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderAddIngredientFromFile(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val path = call.argument<String>("path")
        val ingredientJson = call.argument<String>("ingredientJson")

        if (handle == null || path == null) {
            result.error("INVALID_ARGUMENT", "handle and path are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            // Builder doesn't have addIngredientFile - read file and use addIngredient
            val file = File(path)
            val data = file.readBytes()
            val mimeType = getMimeTypeFromPath(path)
            val stream = ByteArrayStream(data)

            builder.addIngredient(ingredientJson ?: "{}", mimeType, stream)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderAddAction(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val actionJson = call.argument<String>("actionJson")

        if (handle == null || actionJson == null) {
            result.error("INVALID_ARGUMENT", "handle and actionJson are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            // Parse JSON and create Action object
            val json = JSONObject(actionJson)
            val actionName = json.optString("action", "c2pa.unknown")
            val softwareAgent = json.optString("softwareAgent", null)
            val digitalSourceType = json.optString("digitalSourceType", null)

            // Parse parameters if present
            val parameters = mutableMapOf<String, String>()
            if (json.has("parameters")) {
                val paramsJson = json.getJSONObject("parameters")
                val keys = paramsJson.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    parameters[key] = paramsJson.optString(key, "")
                }
            }

            val action = Action(
                actionName,
                digitalSourceType,
                softwareAgent,
                if (parameters.isEmpty()) null else parameters
            )

            builder.addAction(action)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderToArchive(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")

        if (handle == null) {
            result.error("INVALID_ARGUMENT", "handle is required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            val stream = ByteArrayStream()
            builder.toArchive(stream)
            val archiveData = stream.getData()
            result.success(archiveData)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleBuilderSign(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val sourceData = call.argument<ByteArray>("sourceData")
        val mimeType = call.argument<String>("mimeType")
        val signerMap = call.argument<Map<String, Any?>>("signer")

        if (handle == null || sourceData == null || mimeType == null || signerMap == null) {
            result.error("INVALID_ARGUMENT", "handle, sourceData, mimeType, and signer are required", null)
            return
        }

        val builder = getBuilder(handle)
        if (builder == null) {
            result.error("INVALID_HANDLE", "Invalid builder handle", null)
            return
        }

        val signerType = signerMap["type"] as? String ?: "pem"

        // Callback signers need async execution to avoid deadlock:
        // The callback uses runBlocking + mainScope.launch to call Flutter,
        // so we must run the signing on a background thread to keep main thread free.
        if (signerType == "remote" || signerType == "callback") {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val signer = createSignerAsync(signerMap)
                    val sourceStream = ByteArrayStream(sourceData)
                    val destStream = ByteArrayStream()

                    val signResult = builder.sign(mimeType, sourceStream, destStream, signer)
                    val signedData = destStream.getData()

                    val resultMap = HashMap<String, Any?>()
                    resultMap["signedData"] = signedData
                    resultMap["manifestBytes"] = signResult.manifestBytes
                    resultMap["manifestSize"] = signResult.manifestBytes?.size ?: 0

                    signer.close()

                    // Return result on main thread
                    mainScope.launch {
                        result.success(resultMap)
                    }
                } catch (e: C2PAError) {
                    mainScope.launch {
                        result.error("C2PA_ERROR", e.message, null)
                    }
                } catch (e: Exception) {
                    mainScope.launch {
                        result.error("ERROR", e.message, null)
                    }
                }
            }
        } else {
            try {
                val signer = createSigner(signerMap, result) ?: return
                performBuilderSign(builder, sourceData, mimeType, signer, result)
                signer.close()
            } catch (e: C2PAError) {
                result.error("C2PA_ERROR", e.message, null)
            } catch (e: Exception) {
                result.error("ERROR", e.message, null)
            }
        }
    }

    private fun performBuilderSign(
        builder: Builder,
        sourceData: ByteArray,
        mimeType: String,
        signer: Signer,
        result: Result
    ) {
        val sourceStream = ByteArrayStream(sourceData)
        val destStream = ByteArrayStream()

        val signResult = builder.sign(mimeType, sourceStream, destStream, signer)
        val signedData = destStream.getData()

        val resultMap = HashMap<String, Any?>()
        resultMap["signedData"] = signedData
        resultMap["manifestBytes"] = signResult.manifestBytes
        resultMap["manifestSize"] = signResult.manifestBytes?.size ?: 0

        result.success(resultMap)
    }

    private fun handleBuilderSignFile(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val sourcePath = call.argument<String>("sourcePath")
        val destPath = call.argument<String>("destPath")
        val signerMap = call.argument<Map<String, Any?>>("signer")

        if (handle == null || sourcePath == null || destPath == null || signerMap == null) {
            result.error("INVALID_ARGUMENT", "handle, sourcePath, destPath, and signer are required", null)
            return
        }

        val builder = getBuilder(handle)
        if (builder == null) {
            result.error("INVALID_HANDLE", "Invalid builder handle", null)
            return
        }

        val signerType = signerMap["type"] as? String ?: "pem"

        // Callback signers need async execution to avoid deadlock
        if (signerType == "remote" || signerType == "callback") {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val signer = createSignerAsync(signerMap)
                    val sourceFile = File(sourcePath)
                    val sourceData = sourceFile.readBytes()
                    val mimeType = getMimeTypeFromPath(sourcePath)

                    val sourceStream = ByteArrayStream(sourceData)
                    val destStream = ByteArrayStream()

                    builder.sign(mimeType, sourceStream, destStream, signer)

                    val destFile = File(destPath)
                    destFile.writeBytes(destStream.getData())

                    signer.close()

                    mainScope.launch {
                        result.success(null)
                    }
                } catch (e: C2PAError) {
                    mainScope.launch {
                        result.error("C2PA_ERROR", e.message, null)
                    }
                } catch (e: Exception) {
                    mainScope.launch {
                        result.error("ERROR", e.message, null)
                    }
                }
            }
        } else {
            try {
                val signer = createSigner(signerMap, result) ?: return
                performBuilderSignFile(builder, sourcePath, destPath, signer, result)
                signer.close()
            } catch (e: C2PAError) {
                result.error("C2PA_ERROR", e.message, null)
            } catch (e: Exception) {
                result.error("ERROR", e.message, null)
            }
        }
    }

    private fun performBuilderSignFile(
        builder: Builder,
        sourcePath: String,
        destPath: String,
        signer: Signer,
        result: Result
    ) {
        val sourceFile = File(sourcePath)
        val sourceData = sourceFile.readBytes()
        val mimeType = getMimeTypeFromPath(sourcePath)

        val sourceStream = ByteArrayStream(sourceData)
        val destStream = ByteArrayStream()

        builder.sign(mimeType, sourceStream, destStream, signer)

        val destFile = File(destPath)
        destFile.writeBytes(destStream.getData())

        result.success(null)
    }

    private fun getMimeTypeFromPath(path: String): String {
        val extension = path.substringAfterLast('.', "").lowercase()
        return when (extension) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "tiff", "tif" -> "image/tiff"
            "heic" -> "image/heic"
            "heif" -> "image/heif"
            "avif" -> "image/avif"
            "mp4", "m4v" -> "video/mp4"
            "mov" -> "video/quicktime"
            "m4a" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "pdf" -> "application/pdf"
            "svg" -> "image/svg+xml"
            else -> "application/octet-stream"
        }
    }

    private fun handleBuilderDispose(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")

        if (handle == null) {
            result.error("INVALID_ARGUMENT", "handle is required", null)
            return
        }

        try {
            val builder = removeBuilder(handle)
            builder?.close()
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Advanced Signing API
    // ===========================================================================

    private fun handleCreateHashedPlaceholder(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val reservedSize = call.argument<Int>("reservedSize")
        val mimeType = call.argument<String>("mimeType")

        if (handle == null || reservedSize == null || mimeType == null) {
            result.error("INVALID_ARGUMENT", "handle, reservedSize, and mimeType are required", null)
            return
        }

        try {
            val builder = getBuilder(handle)
            if (builder == null) {
                result.error("INVALID_HANDLE", "Invalid builder handle", null)
                return
            }

            val placeholderData = builder.dataHashedPlaceholder(reservedSize.toLong(), mimeType)
            result.success(placeholderData)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleSignHashedEmbeddable(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val signerMap = call.argument<Map<String, Any?>>("signer")
        val dataHash = call.argument<String>("dataHash")
        val mimeType = call.argument<String>("mimeType")
        val assetData = call.argument<ByteArray>("assetData")

        if (handle == null || signerMap == null || dataHash == null || mimeType == null) {
            result.error("INVALID_ARGUMENT", "handle, signer, dataHash, and mimeType are required", null)
            return
        }

        val builder = getBuilder(handle)
        if (builder == null) {
            result.error("INVALID_HANDLE", "Invalid builder handle", null)
            return
        }

        val signerType = signerMap["type"] as? String ?: "pem"

        // Callback signers need async execution to avoid deadlock
        if (signerType == "remote" || signerType == "callback") {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val signer = createSignerAsync(signerMap)
                    val assetStream = if (assetData != null) ByteArrayStream(assetData) else null
                    val embeddableData = builder.signDataHashedEmbeddable(signer, dataHash, mimeType, assetStream)
                    signer.close()

                    mainScope.launch {
                        result.success(embeddableData)
                    }
                } catch (e: C2PAError) {
                    mainScope.launch {
                        result.error("C2PA_ERROR", e.message, null)
                    }
                } catch (e: Exception) {
                    mainScope.launch {
                        result.error("ERROR", e.message, null)
                    }
                }
            }
        } else {
            try {
                val signer = createSigner(signerMap, result) ?: return
                val assetStream = if (assetData != null) ByteArrayStream(assetData) else null
                val embeddableData = builder.signDataHashedEmbeddable(signer, dataHash, mimeType, assetStream)
                signer.close()
                result.success(embeddableData)
            } catch (e: C2PAError) {
                result.error("C2PA_ERROR", e.message, null)
            } catch (e: Exception) {
                result.error("ERROR", e.message, null)
            }
        }
    }

    private fun handleFormatEmbeddable(call: MethodCall, result: Result) {
        val mimeType = call.argument<String>("mimeType")
        val manifestBytes = call.argument<ByteArray>("manifestBytes")

        if (mimeType == null || manifestBytes == null) {
            result.error("INVALID_ARGUMENT", "mimeType and manifestBytes are required", null)
            return
        }

        // formatEmbeddable is not available in the Android C2PA library.
        // The manifest bytes from signDataHashedEmbeddable are already in the correct format.
        // Return the manifest bytes unchanged.
        Log.w("C2paPlugin", "formatEmbeddable: Not supported on Android, returning input unchanged")
        result.success(manifestBytes)
    }

    private fun handleGetSignerReserveSize(call: MethodCall, result: Result) {
        val signerMap = call.argument<Map<String, Any?>>("signer")

        if (signerMap == null) {
            result.error("INVALID_ARGUMENT", "signer is required", null)
            return
        }

        val signerType = signerMap["type"] as? String ?: "pem"

        // Callback signers need async execution to avoid deadlock
        if (signerType == "remote" || signerType == "callback") {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val signer = createSignerAsync(signerMap)
                    val reserveSize = signer.reserveSize()
                    signer.close()

                    mainScope.launch {
                        result.success(reserveSize)
                    }
                } catch (e: C2PAError) {
                    mainScope.launch {
                        result.error("C2PA_ERROR", e.message, null)
                    }
                } catch (e: Exception) {
                    mainScope.launch {
                        result.error("ERROR", e.message, null)
                    }
                }
            }
        } else {
            try {
                val signer = createSigner(signerMap, result) ?: return
                val reserveSize = signer.reserveSize()
                signer.close()
                result.success(reserveSize)
            } catch (e: C2PAError) {
                result.error("C2PA_ERROR", e.message, null)
            } catch (e: Exception) {
                result.error("ERROR", e.message, null)
            }
        }
    }

    // ===========================================================================
    // Settings API
    // ===========================================================================

    private fun handleLoadSettings(call: MethodCall, result: Result) {
        val settings = call.argument<String>("settings")
        val format = call.argument<String>("format")

        if (settings == null || format == null) {
            result.error("INVALID_ARGUMENT", "settings and format are required", null)
            return
        }

        try {
            C2PA.loadSettings(settings, format)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Settings Handle API
    // ===========================================================================

    private fun handleCreateSettings(result: Result) {
        try {
            val settingsObj = C2PASettings.create()
            val handle = storeSettings(settingsObj)
            result.success(handle)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleSettingsUpdateFromString(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val settingsStr = call.argument<String>("settings")
        val format = call.argument<String>("format")

        if (handle == null || settingsStr == null || format == null) {
            result.error("INVALID_ARGUMENT", "handle, settings, and format are required", null)
            return
        }

        try {
            val settingsObj = getSettings(handle)
            if (settingsObj == null) {
                result.error("INVALID_HANDLE", "Invalid settings handle", null)
                return
            }

            settingsObj.updateFromString(settingsStr, format)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleSettingsSetValue(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")
        val path = call.argument<String>("path")
        val value = call.argument<String>("value")

        if (handle == null || path == null || value == null) {
            result.error("INVALID_ARGUMENT", "handle, path, and value are required", null)
            return
        }

        try {
            val settingsObj = getSettings(handle)
            if (settingsObj == null) {
                result.error("INVALID_HANDLE", "Invalid settings handle", null)
                return
            }

            settingsObj.setValue(path, value)
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleSettingsDispose(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")

        if (handle == null) {
            result.error("INVALID_ARGUMENT", "handle is required", null)
            return
        }

        try {
            val settingsObj = removeSettings(handle)
            settingsObj?.close()
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Context Handle API
    // ===========================================================================

    private fun handleCreateContext(result: Result) {
        try {
            val contextObj = C2PAContext.create()
            val handle = storeContext(contextObj)
            result.success(handle)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleCreateContextFromSettings(call: MethodCall, result: Result) {
        val settingsHandle = call.argument<Int>("settingsHandle")

        if (settingsHandle == null) {
            result.error("INVALID_ARGUMENT", "settingsHandle is required", null)
            return
        }

        try {
            val settingsObj = getSettings(settingsHandle)
            if (settingsObj == null) {
                result.error("INVALID_HANDLE", "Invalid settings handle", null)
                return
            }

            val contextObj = C2PAContext.fromSettings(settingsObj)
            val handle = storeContext(contextObj)
            result.success(handle)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleContextDispose(call: MethodCall, result: Result) {
        val handle = call.argument<Int>("handle")

        if (handle == null) {
            result.error("INVALID_ARGUMENT", "handle is required", null)
            return
        }

        try {
            val contextObj = removeContext(handle)
            contextObj?.close()
            result.success(null)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Enhanced Reader with Context
    // ===========================================================================

    private fun handleReadFileWithContext(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        val contextHandle = call.argument<Int>("contextHandle")
        val detailed = call.argument<Boolean>("detailed") ?: false
        val dataDir = call.argument<String>("dataDir")

        if (path == null || contextHandle == null) {
            result.error("INVALID_ARGUMENT", "path and contextHandle are required", null)
            return
        }

        try {
            val contextObj = getContext(contextHandle)
            if (contextObj == null) {
                result.error("INVALID_HANDLE", "Invalid context handle", null)
                return
            }

            val file = File(path)
            val fileData = file.readBytes()
            val mimeType = getMimeTypeFromPath(path)
            val stream = ByteArrayStream(fileData)

            val reader = Reader.fromContext(contextObj).withStream(mimeType, stream)
            val json = if (detailed) reader.detailedJson() else reader.json()
            reader.close()
            result.success(json)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Enhanced Builder with Context/Settings
    // ===========================================================================

    private fun handleCreateBuilderWithContext(call: MethodCall, result: Result) {
        val contextHandle = call.argument<Int>("contextHandle")
        val manifestJson = call.argument<String>("manifestJson")

        if (contextHandle == null || manifestJson == null) {
            result.error("INVALID_ARGUMENT", "contextHandle and manifestJson are required", null)
            return
        }

        try {
            val contextObj = getContext(contextHandle)
            if (contextObj == null) {
                result.error("INVALID_HANDLE", "Invalid context handle", null)
                return
            }

            val builder = Builder.fromContext(contextObj).withDefinition(manifestJson)
            val handle = storeBuilder(builder)
            result.success(handle)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleCreateBuilderWithSettings(call: MethodCall, result: Result) {
        val manifestJson = call.argument<String>("manifestJson")
        val settingsHandle = call.argument<Int>("settingsHandle")

        if (manifestJson == null || settingsHandle == null) {
            result.error("INVALID_ARGUMENT", "manifestJson and settingsHandle are required", null)
            return
        }

        try {
            val settingsObj = getSettings(settingsHandle)
            if (settingsObj == null) {
                result.error("INVALID_HANDLE", "Invalid settings handle", null)
                return
            }

            val builder = Builder.fromJson(manifestJson, settingsObj)
            val handle = storeBuilder(builder)
            result.success(handle)
        } catch (e: C2PAError) {
            result.error("C2PA_ERROR", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    // ===========================================================================
    // Certificate Manager
    // ===========================================================================

    private fun handleCreateSelfSignedCertificateChain(call: MethodCall, result: Result) {
        // Self-signed certificate chain generation is not directly available
        // in the c2pa-android library.
        result.error("UNSUPPORTED", "createSelfSignedCertificateChain is not supported on Android", null)
    }

    // ===========================================================================
    // Helper Functions
    // ===========================================================================

    private fun parseAlgorithm(algorithmStr: String): SigningAlgorithm {
        return when (algorithmStr) {
            "es256" -> SigningAlgorithm.ES256
            "es384" -> SigningAlgorithm.ES384
            "es512" -> SigningAlgorithm.ES512
            "ps256" -> SigningAlgorithm.PS256
            "ps384" -> SigningAlgorithm.PS384
            "ps512" -> SigningAlgorithm.PS512
            "ed25519" -> SigningAlgorithm.ED25519
            else -> SigningAlgorithm.ES256
        }
    }

    private fun createSigner(map: Map<String, Any?>, result: Result): Signer? {
        val type = map["type"] as? String ?: "pem"

        return try {
            when (type) {
                "pem" -> createPemSigner(map)
                "callback" -> createCallbackSigner(map)
                "keystore" -> createKeystoreSigner(map)
                "hardware" -> createHardwareSigner(map)
                "settings" -> createSettingsSigner(map)
                "remote" -> {
                    // Remote signer is async, needs special handling
                    null // Will be handled separately
                }
                else -> {
                    result.error("INVALID_ARGUMENT", "Unknown signer type: $type", null)
                    null
                }
            }
        } catch (e: Exception) {
            result.error("SIGNER_ERROR", "Failed to create signer: ${e.message}", null)
            null
        }
    }

    private suspend fun createSignerAsync(map: Map<String, Any?>): Signer {
        val type = map["type"] as? String ?: "pem"

        return when (type) {
            "pem" -> createPemSigner(map)
            "callback" -> createCallbackSigner(map)
            "keystore" -> createKeystoreSigner(map)
            "hardware" -> createHardwareSigner(map)
            "settings" -> createSettingsSigner(map)
            "remote" -> createRemoteSigner(map)
            else -> throw IllegalArgumentException("Unknown signer type: $type")
        }
    }

    private fun createPemSigner(map: Map<String, Any?>): Signer {
        val algorithmStr = map["algorithm"] as String
        val certificatePem = map["certificatePem"] as String
        val privateKeyPem = map["privateKeyPem"] as String
        val tsaUrl = map["tsaUrl"] as String?

        val algorithm = parseAlgorithm(algorithmStr)
        val signerInfo = SignerInfo(algorithm, certificatePem, privateKeyPem, tsaUrl)
        return Signer.fromInfo(signerInfo)
    }

    private fun createCallbackSigner(map: Map<String, Any?>): Signer {
        val algorithmStr = map["algorithm"] as String
        val certificateChainPem = map["certificateChainPem"] as String
        val tsaUrl = map["tsaUrl"] as String?
        val callbackId = map["callbackId"] as String

        val algorithm = parseAlgorithm(algorithmStr)

        return Signer.withCallback(algorithm, certificateChainPem, tsaUrl) { data ->
            // Invoke Dart callback via method channel
            val callResult = runBlocking {
                kotlinx.coroutines.suspendCancellableCoroutine<ByteArray> { continuation ->
                    mainScope.launch {
                        try {
                            channel.invokeMethod(
                                "signCallback",
                                mapOf("callbackId" to callbackId, "data" to data),
                                object : Result {
                                    override fun success(result: Any?) {
                                        continuation.resume(result as ByteArray) {}
                                    }
                                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                                        continuation.cancel(Exception("Callback error: $errorMessage"))
                                    }
                                    override fun notImplemented() {
                                        continuation.cancel(Exception("Callback not implemented"))
                                    }
                                }
                            )
                        } catch (e: Exception) {
                            continuation.cancel(e)
                        }
                    }
                }
            }
            callResult
        }
    }

    private fun createKeystoreSigner(map: Map<String, Any?>): Signer {
        val algorithmStr = map["algorithm"] as String
        val certificateChainPem = map["certificateChainPem"] as String
        val keyAlias = map["keyAlias"] as String
        val tsaUrl = map["tsaUrl"] as String?

        val algorithm = parseAlgorithm(algorithmStr)

        return KeyStoreSigner.createSigner(algorithm, certificateChainPem, keyAlias, tsaUrl)
    }

    private fun createHardwareSigner(map: Map<String, Any?>): Signer {
        val certificateChainPem = map["certificateChainPem"] as String
        val keyAlias = map["keyAlias"] as String
        val tsaUrl = map["tsaUrl"] as String?
        val requireUserAuthentication = map["requireUserAuthentication"] as? Boolean ?: false

        android.util.Log.d("C2paPlugin", "Creating hardware signer for key: $keyAlias")
        android.util.Log.d("C2paPlugin", "Cert chain length: ${certificateChainPem.length}, starts with: ${certificateChainPem.take(50)}")

        val config = StrongBoxSigner.Config(
            keyTag = keyAlias,
            requireUserAuthentication = requireUserAuthentication
        )

        return StrongBoxSigner.createSigner(
            SigningAlgorithm.ES256, // StrongBox only supports ES256
            certificateChainPem,
            config,
            tsaUrl
        )
    }

    private fun createSettingsSigner(map: Map<String, Any?>): Signer {
        val settingsStr = map["settings"] as String
        val format = map["format"] as? String ?: "json"

        return when (format.lowercase()) {
            "toml" -> Signer.fromSettingsToml(settingsStr)
            else -> Signer.fromSettingsJson(settingsStr)
        }
    }

    private suspend fun createRemoteSigner(map: Map<String, Any?>): Signer {
        val configurationUrl = map["configurationUrl"] as String
        val bearerToken = map["bearerToken"] as String?
        @Suppress("UNCHECKED_CAST")
        val customHeaders = (map["customHeaders"] as? Map<String, String>) ?: emptyMap()

        val webServiceSigner = WebServiceSigner(configurationUrl, bearerToken, customHeaders)
        return webServiceSigner.createSigner()
    }

    private fun mapIntent(intent: String, digitalSourceType: DigitalSourceType = DigitalSourceType.DIGITAL_CAPTURE): BuilderIntent {
        return when (intent) {
            "create" -> BuilderIntent.Create(digitalSourceType)
            "edit" -> BuilderIntent.Edit
            "update" -> BuilderIntent.Update
            else -> BuilderIntent.Create(digitalSourceType)
        }
    }

    private fun mapDigitalSourceType(type: String): DigitalSourceType {
        return when (type) {
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
            else -> DigitalSourceType.DIGITAL_CAPTURE
        }
    }

    // ===========================================================================
    // Key Management API
    // ===========================================================================

    private fun handleIsHardwareSigningAvailable(result: Result) {
        try {
            val ctx = context
            if (ctx == null) {
                result.success(false)
                return
            }
            val available = StrongBoxSigner.isAvailable(ctx)
            result.success(available)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleCreateKey(call: MethodCall, result: Result) {
        val keyAlias = call.argument<String>("keyAlias")
        val algorithmStr = call.argument<String>("algorithm")
        val useHardware = call.argument<Boolean>("useHardware") ?: false

        if (keyAlias == null || algorithmStr == null) {
            result.error("INVALID_ARGUMENT", "keyAlias and algorithm are required", null)
            return
        }

        try {
            if (useHardware) {
                val config = StrongBoxSigner.Config(keyTag = keyAlias)
                StrongBoxSigner.createKey(config)
            } else {
                // For regular keystore, we would need to create a key
                // The KeyStoreSigner doesn't expose key creation directly
                // This would need to be done via Android KeyStore API
                result.error("NOT_IMPLEMENTED", "Non-hardware key creation not yet implemented", null)
                return
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("ERROR", "Failed to create key: ${e.message}", null)
        }
    }

    private fun handleDeleteKey(call: MethodCall, result: Result) {
        val keyAlias = call.argument<String>("keyAlias")

        if (keyAlias == null) {
            result.error("INVALID_ARGUMENT", "keyAlias is required", null)
            return
        }

        try {
            // Try StrongBox first, then KeyStore
            val strongBoxDeleted = StrongBoxSigner.deleteKey(keyAlias)
            if (strongBoxDeleted) {
                result.success(true)
                return
            }

            val keyStoreDeleted = KeyStoreSigner.deleteKey(keyAlias)
            result.success(keyStoreDeleted)
        } catch (e: Exception) {
            result.error("ERROR", "Failed to delete key: ${e.message}", null)
        }
    }

    private fun handleKeyExists(call: MethodCall, result: Result) {
        val keyAlias = call.argument<String>("keyAlias")

        if (keyAlias == null) {
            result.error("INVALID_ARGUMENT", "keyAlias is required", null)
            return
        }

        try {
            val exists = StrongBoxSigner.keyExists(keyAlias) || KeyStoreSigner.keyExists(keyAlias)
            result.success(exists)
        } catch (e: Exception) {
            result.error("ERROR", "Failed to check key: ${e.message}", null)
        }
    }

    private fun handleExportPublicKey(call: MethodCall, result: Result) {
        val keyAlias = call.argument<String>("keyAlias")

        if (keyAlias == null) {
            result.error("INVALID_ARGUMENT", "keyAlias is required", null)
            return
        }

        try {
            // Export public key from keystore
            val keyStore = java.security.KeyStore.getInstance("AndroidKeyStore")
            keyStore.load(null)
            val cert = keyStore.getCertificate(keyAlias)
            if (cert == null) {
                result.error("KEY_NOT_FOUND", "Key not found: $keyAlias", null)
                return
            }
            val publicKey = cert.publicKey
            val encoded = android.util.Base64.encodeToString(publicKey.encoded, android.util.Base64.DEFAULT)
            val pem = "-----BEGIN PUBLIC KEY-----\n$encoded-----END PUBLIC KEY-----"
            result.success(pem)
        } catch (e: Exception) {
            result.error("ERROR", "Failed to export public key: ${e.message}", null)
        }
    }

    private fun handleImportKey(call: MethodCall, result: Result) {
        val keyAlias = call.argument<String>("keyAlias")
        val privateKeyPem = call.argument<String>("privateKeyPem")
        val certificateChainPem = call.argument<String>("certificateChainPem")

        if (keyAlias == null || privateKeyPem == null || certificateChainPem == null) {
            result.error("INVALID_ARGUMENT", "keyAlias, privateKeyPem, and certificateChainPem are required", null)
            return
        }

        try {
            // Parse the private key from PEM
            val privateKey = parsePemPrivateKey(privateKeyPem)

            // Parse the certificate chain from PEM
            val certChain = parsePemCertificateChain(certificateChainPem)

            if (certChain.isEmpty()) {
                result.error("INVALID_ARGUMENT", "No certificates found in certificate chain", null)
                return
            }

            // Import into Android KeyStore
            val keyStore = KeyStore.getInstance("AndroidKeyStore")
            keyStore.load(null)

            // Set the key entry with the certificate chain
            keyStore.setKeyEntry(keyAlias, privateKey, null, certChain.toTypedArray())

            result.success(null)
        } catch (e: Exception) {
            result.error("ERROR", "Failed to import key: ${e.message}", null)
        }
    }

    private fun parsePemPrivateKey(pem: String): PrivateKey {
        // Remove PEM headers and decode base64
        val base64Content = pem
            .replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----", "")
            .replace("-----BEGIN EC PRIVATE KEY-----", "")
            .replace("-----END EC PRIVATE KEY-----", "")
            .replace("\\s".toRegex(), "")

        val keyBytes = Base64.getDecoder().decode(base64Content)

        // Try EC first, then RSA
        return try {
            val keySpec = PKCS8EncodedKeySpec(keyBytes)
            val keyFactory = KeyFactory.getInstance("EC")
            keyFactory.generatePrivate(keySpec)
        } catch (e: Exception) {
            val keySpec = PKCS8EncodedKeySpec(keyBytes)
            val keyFactory = KeyFactory.getInstance("RSA")
            keyFactory.generatePrivate(keySpec)
        }
    }

    private fun parsePemCertificateChain(pem: String): List<X509Certificate> {
        val certFactory = CertificateFactory.getInstance("X.509")
        val certificates = mutableListOf<X509Certificate>()

        // Split PEM into individual certificates
        val certPattern = Regex("-----BEGIN CERTIFICATE-----([^-]+)-----END CERTIFICATE-----")
        val matches = certPattern.findAll(pem)

        for (match in matches) {
            val base64Content = match.groupValues[1].replace("\\s".toRegex(), "")
            val certBytes = Base64.getDecoder().decode(base64Content)
            val cert = certFactory.generateCertificate(certBytes.inputStream()) as X509Certificate
            certificates.add(cert)
        }

        return certificates
    }

    private fun handleCreateCSR(call: MethodCall, result: Result) {
        val keyAlias = call.argument<String>("keyAlias")
        val commonName = call.argument<String>("commonName")
        val organization = call.argument<String>("organization")
        val organizationalUnit = call.argument<String>("organizationalUnit")
        val country = call.argument<String>("country")
        val state = call.argument<String>("state")
        val locality = call.argument<String>("locality")

        if (keyAlias == null || commonName == null) {
            result.error("INVALID_ARGUMENT", "keyAlias and commonName are required", null)
            return
        }

        try {
            val config = CertificateManager.CertificateConfig(
                commonName = commonName,
                organization = organization,
                organizationalUnit = organizationalUnit,
                country = country,
                state = state,
                locality = locality
            )

            val csr = CertificateManager.createCSR(keyAlias, config)
            result.success(csr)
        } catch (e: Exception) {
            result.error("ERROR", "Failed to create CSR: ${e.message}", null)
        }
    }

    private fun handleEnrollHardwareKey(call: MethodCall, result: Result) {
        val keyAlias = call.argument<String>("keyAlias")
        val signingServerUrl = call.argument<String>("signingServerUrl")
        val bearerToken = call.argument<String>("bearerToken")
        val commonName = call.argument<String>("commonName") ?: "C2PA Hardware Key"
        val organization = call.argument<String>("organization") ?: "C2PA App"
        val useStrongBox = call.argument<Boolean>("useStrongBox") ?: false

        if (keyAlias == null || signingServerUrl == null) {
            result.error("INVALID_ARGUMENT", "keyAlias and signingServerUrl are required", null)
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val keyStore = KeyStore.getInstance("AndroidKeyStore")
                keyStore.load(null)

                // Delete existing key to ensure fresh enrollment
                if (keyStore.containsAlias(keyAlias)) {
                    android.util.Log.d("C2paPlugin", "Deleting existing key: $keyAlias")
                    keyStore.deleteEntry(keyAlias)
                }

                // Create hardware key
                android.util.Log.d("C2paPlugin", "Creating hardware key: $keyAlias, useStrongBox: $useStrongBox")
                if (useStrongBox) {
                    val config = StrongBoxSigner.Config(
                        keyTag = keyAlias,
                        requireUserAuthentication = false
                    )
                    StrongBoxSigner.createKey(config)
                } else {
                    CertificateManager.generateHardwareKey(keyAlias, requireStrongBox = false)
                }

                // Generate CSR
                val certConfig = CertificateManager.CertificateConfig(
                    commonName = commonName,
                    organization = organization,
                    country = "US"
                )
                val csr = CertificateManager.createCSR(keyAlias, certConfig)

                // Submit CSR to signing server
                val enrollUrl = "$signingServerUrl/api/v1/certificates/sign"
                val requestBody = org.json.JSONObject().apply {
                    put("csr", csr)
                }.toString()

                val url = java.net.URL(enrollUrl)
                val connection = url.openConnection() as java.net.HttpURLConnection
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.connectTimeout = 30000
                connection.readTimeout = 30000

                bearerToken?.let {
                    connection.setRequestProperty("Authorization", "Bearer $it")
                }

                connection.outputStream.use { output ->
                    output.write(requestBody.toByteArray())
                }

                if (connection.responseCode == 200) {
                    val response = connection.inputStream.bufferedReader().use { it.readText() }
                    connection.disconnect()

                    android.util.Log.d("C2paPlugin", "Server response: $response")

                    val responseJson = org.json.JSONObject(response)
                    val certChain = responseJson.getString("certificate_chain")

                    // Count certificates in chain
                    val certCount = certChain.split("-----BEGIN CERTIFICATE-----").size - 1
                    android.util.Log.d("C2paPlugin", "Enrollment successful, cert chain length: ${certChain.length}, cert count: $certCount")
                    android.util.Log.d("C2paPlugin", "Cert chain starts with: ${certChain.take(200)}")

                    val resultMap = HashMap<String, Any?>()
                    resultMap["certificateChain"] = certChain
                    resultMap["keyAlias"] = keyAlias

                    mainScope.launch {
                        result.success(resultMap)
                    }
                } else {
                    val error = connection.errorStream?.bufferedReader()?.use { it.readText() }
                        ?: "HTTP ${connection.responseCode}"
                    connection.disconnect()

                    mainScope.launch {
                        result.error("ENROLLMENT_ERROR", "Certificate enrollment failed: $error", null)
                    }
                }
            } catch (e: Exception) {
                mainScope.launch {
                    result.error("ERROR", "Hardware key enrollment failed: ${e.message}", null)
                }
            }
        }
    }

    // ===========================================================================
    // Builder Handle Management
    // ===========================================================================

    private fun storeBuilder(builder: Builder): Int {
        builderLock.lock()
        try {
            val handle = nextBuilderHandle++
            builders[handle] = builder
            return handle
        } finally {
            builderLock.unlock()
        }
    }

    private fun getBuilder(handle: Int): Builder? {
        builderLock.lock()
        try {
            return builders[handle]
        } finally {
            builderLock.unlock()
        }
    }

    private fun removeBuilder(handle: Int): Builder? {
        builderLock.lock()
        try {
            return builders.remove(handle)
        } finally {
            builderLock.unlock()
        }
    }

    // ===========================================================================
    // Settings Handle Management
    // ===========================================================================

    private fun storeSettings(settingsObj: C2PASettings): Int {
        settingsLock.lock()
        try {
            val handle = nextSettingsHandle++
            settings[handle] = settingsObj
            return handle
        } finally {
            settingsLock.unlock()
        }
    }

    private fun getSettings(handle: Int): C2PASettings? {
        settingsLock.lock()
        try {
            return settings[handle]
        } finally {
            settingsLock.unlock()
        }
    }

    private fun removeSettings(handle: Int): C2PASettings? {
        settingsLock.lock()
        try {
            return settings.remove(handle)
        } finally {
            settingsLock.unlock()
        }
    }

    // ===========================================================================
    // Context Handle Management
    // ===========================================================================

    private fun storeContext(contextObj: C2PAContext): Int {
        contextLock.lock()
        try {
            val handle = nextContextHandle++
            contexts[handle] = contextObj
            return handle
        } finally {
            contextLock.unlock()
        }
    }

    private fun getContext(handle: Int): C2PAContext? {
        contextLock.lock()
        try {
            return contexts[handle]
        } finally {
            contextLock.unlock()
        }
    }

    private fun removeContext(handle: Int): C2PAContext? {
        contextLock.lock()
        try {
            return contexts.remove(handle)
        } finally {
            contextLock.unlock()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null

        // Clean up any remaining builders
        builderLock.lock()
        try {
            for (builder in builders.values) {
                try {
                    builder.close()
                } catch (e: Exception) {
                    // Ignore cleanup errors
                }
            }
            builders.clear()
        } finally {
            builderLock.unlock()
        }

        // Clean up any remaining settings
        settingsLock.lock()
        try {
            for (settingsObj in settings.values) {
                try {
                    settingsObj.close()
                } catch (e: Exception) {
                    // Ignore cleanup errors
                }
            }
            settings.clear()
        } finally {
            settingsLock.unlock()
        }

        // Clean up any remaining contexts
        contextLock.lock()
        try {
            for (contextObj in contexts.values) {
                try {
                    contextObj.close()
                } catch (e: Exception) {
                    // Ignore cleanup errors
                }
            }
            contexts.clear()
        } finally {
            contextLock.unlock()
        }
    }
}
