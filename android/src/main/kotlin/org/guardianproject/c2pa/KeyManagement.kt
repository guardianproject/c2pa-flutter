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

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.contentauth.c2pa.CertificateManager
import org.contentauth.c2pa.KeyStoreSigner
import org.contentauth.c2pa.StrongBoxSigner
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64

/** Android KeyStore / StrongBox key management behind the Dart key API. */
class KeyManagement(private val appContext: () -> android.content.Context?) {

    fun isHardwareSigningAvailable(): Boolean =
        try {
            appContext()?.let { StrongBoxSigner.isAvailable(it) } ?: false
        } catch (e: Exception) {
            false
        }

    fun createKey(keyAlias: String, algorithm: SigningAlgorithmMessage, useHardware: Boolean) {
        if (useHardware) {
            if (algorithm != SigningAlgorithmMessage.ES256) {
                throw invalidArgument("Hardware keys are P-256: use es256, not ${algorithm.dartName}")
            }
            StrongBoxSigner.createKey(StrongBoxSigner.Config(keyTag = keyAlias))
        } else {
            createSoftwareKey(keyAlias, curveFor(algorithm))
        }
    }

    private fun curveFor(algorithm: SigningAlgorithmMessage): String = when (algorithm) {
        SigningAlgorithmMessage.ES256 -> "secp256r1"
        SigningAlgorithmMessage.ES384 -> "secp384r1"
        SigningAlgorithmMessage.ES512 -> "secp521r1"
        else -> throw invalidArgument("createKey supports es256, es384 and es512, not ${algorithm.dartName}")
    }

    /**
     * An AndroidKeyStore EC key on [curve]. Every SHA-2 digest is allowed, so
     * the key serves the KeyStoreSigner for its algorithm and CSR creation
     * (which signs with SHA-256) alike.
     */
    private fun createSoftwareKey(keyAlias: String, curve: String) {
        val spec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
        )
            .setAlgorithmParameterSpec(ECGenParameterSpec(curve))
            .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384, KeyProperties.DIGEST_SHA512)
            .setUserAuthenticationRequired(false)
            .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").run {
            initialize(spec)
            generateKeyPair()
        }
    }

    fun deleteKey(keyAlias: String): Boolean {
        if (StrongBoxSigner.deleteKey(keyAlias)) return true
        return KeyStoreSigner.deleteKey(keyAlias)
    }

    fun keyExists(keyAlias: String): Boolean {
        return StrongBoxSigner.keyExists(keyAlias) || KeyStoreSigner.keyExists(keyAlias)
    }

    fun exportPublicKey(keyAlias: String): String {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val cert = keyStore.getCertificate(keyAlias)
            ?: throw PluginError("KEY_NOT_FOUND", "Key not found: $keyAlias")
        val encoded = android.util.Base64.encodeToString(cert.publicKey.encoded, android.util.Base64.DEFAULT)
        return "-----BEGIN PUBLIC KEY-----\n$encoded-----END PUBLIC KEY-----"
    }

    fun importKey(keyAlias: String, privateKeyPem: String, certificateChainPem: String) {
        val privateKey = parsePemPrivateKey(privateKeyPem)
        val chain = parsePemCertificateChain(certificateChainPem)
        if (chain.isEmpty()) throw invalidArgument("No certificates found in certificate chain")
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        keyStore.setKeyEntry(keyAlias, privateKey, null, chain.toTypedArray())
    }

    fun createCSR(keyAlias: String, config: CertificateConfigMessage): String =
        CertificateManager.createCSR(
            keyAlias,
            CertificateManager.CertificateConfig(
                commonName = config.commonName,
                organization = config.organization,
                organizationalUnit = config.organizationalUnit,
                country = config.country,
                state = config.state,
                locality = config.locality,
            ),
        )

    fun enrollHardwareKey(
        keyAlias: String,
        signingServerUrl: String,
        bearerToken: String?,
        commonNameOrNull: String?,
        organizationOrNull: String?,
        useStrongBox: Boolean,
    ): HardwareKeyEnrollmentMessage {
        val commonName = commonNameOrNull ?: "C2PA Hardware Key"
        val organization = organizationOrNull ?: "C2PA App"

        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(keyAlias)) keyStore.deleteEntry(keyAlias)

        if (useStrongBox) {
            StrongBoxSigner.createKey(StrongBoxSigner.Config(keyTag = keyAlias, requireUserAuthentication = false))
        } else {
            CertificateManager.generateHardwareKey(keyAlias, requireStrongBox = false)
        }

        val csr = CertificateManager.createCSR(
            keyAlias,
            CertificateManager.CertificateConfig(commonName = commonName, organization = organization, country = "US"),
        )

        val connection = URL("$signingServerUrl/api/v1/certificates/sign").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.connectTimeout = 30000
            connection.readTimeout = 30000
            bearerToken?.let { connection.setRequestProperty("Authorization", "Bearer $it") }
            connection.outputStream.use { it.write(JSONObject().put("csr", csr).toString().toByteArray()) }

            if (connection.responseCode != 200) {
                val error = connection.errorStream?.bufferedReader()?.use { it.readText() }
                    ?: "HTTP ${connection.responseCode}"
                throw PluginError("ENROLLMENT_ERROR", "Certificate enrollment failed: $error")
            }
            val response = connection.inputStream.bufferedReader().use { it.readText() }
            return HardwareKeyEnrollmentMessage(
                keyAlias = keyAlias,
                certificateChainPem = JSONObject(response).getString("certificate_chain"),
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun parsePemPrivateKey(pem: String): PrivateKey {
        val base64 = pem
            .replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----", "")
            .replace("-----BEGIN EC PRIVATE KEY-----", "")
            .replace("-----END EC PRIVATE KEY-----", "")
            .replace("\\s".toRegex(), "")
        val spec = PKCS8EncodedKeySpec(Base64.getDecoder().decode(base64))
        return try {
            KeyFactory.getInstance("EC").generatePrivate(spec)
        } catch (e: Exception) {
            KeyFactory.getInstance("RSA").generatePrivate(spec)
        }
    }

    private fun parsePemCertificateChain(pem: String): List<X509Certificate> {
        val factory = CertificateFactory.getInstance("X.509")
        return Regex("-----BEGIN CERTIFICATE-----([^-]+)-----END CERTIFICATE-----")
            .findAll(pem)
            .map { match ->
                val bytes = Base64.getDecoder().decode(match.groupValues[1].replace("\\s".toRegex(), ""))
                factory.generateCertificate(bytes.inputStream()) as X509Certificate
            }
            .toList()
    }
}
