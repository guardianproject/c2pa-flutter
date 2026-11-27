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

import org.contentauth.c2pa.KeyStoreSigner
import org.contentauth.c2pa.Signer
import org.contentauth.c2pa.SignerInfo
import org.contentauth.c2pa.SigningAlgorithm
import org.contentauth.c2pa.StrongBoxSigner
import org.contentauth.c2pa.WebServiceSigner
import kotlinx.coroutines.runBlocking

/**
 * Builds SDK [Signer]s from the signer messages Dart sends.
 *
 * Every method here must run off the main thread: callback signers block the
 * calling thread while Dart computes the signature on the main thread, and
 * remote signers wait for the network.
 */
class SignerFactory(private val signWithDart: (callbackId: String, data: ByteArray) -> ByteArray) {

    fun create(message: SignerMessage): Signer =
        when (message) {
            is PemSignerMessage -> Signer.fromInfo(
                SignerInfo(message.algorithm.toSdk(), message.certificatePem, message.privateKeyPem, message.tsaUrl),
            )
            is CallbackSignerMessage -> Signer.withCallback(
                message.algorithm.toSdk(),
                message.certificateChainPem,
                message.tsaUrl,
            ) { data -> signWithDart(message.callbackId, data) }
            is KeystoreSignerMessage -> KeyStoreSigner.createSigner(
                message.algorithm.toSdk(),
                message.certificateChainPem,
                message.keyAlias,
                message.tsaUrl,
            )
            // StrongBox only supports ES256.
            is HardwareSignerMessage -> StrongBoxSigner.createSigner(
                SigningAlgorithm.ES256,
                message.certificateChainPem,
                StrongBoxSigner.Config(
                    keyTag = message.keyAlias,
                    requireUserAuthentication = message.requireUserAuthentication,
                ),
                message.tsaUrl,
            )
            is RemoteSignerMessage -> {
                val webServiceSigner = WebServiceSigner(
                    message.configurationUrl,
                    message.bearerToken,
                    message.customHeaders,
                )
                runBlocking { webServiceSigner.createSigner() }
            }
            is CawgIdentitySignerMessage -> createCawgIdentity(message)
            is SettingsSignerMessage -> throw invalidArgument(
                "A SettingsSigner is not a standalone signer. Put the signer in the settings of a " +
                    "C2paContext and sign without passing a signer, or use C2pa.signBytes/signFile.",
            )
        }

    private fun createCawgIdentity(message: CawgIdentitySignerMessage): Signer {
        val claim = create(message.claimSigner)
        val identity = try {
            create(message.identitySigner)
        } catch (e: Exception) {
            claim.close()
            throw e
        }
        // withCawgIdentity consumes both inputs once it reaches native code, but
        // leaves them untouched when it rejects its arguments up front.
        return try {
            Signer.withCawgIdentity(claim, identity, message.referencedAssertions, message.roles)
        } catch (e: Exception) {
            claim.close()
            identity.close()
            throw e
        }
    }
}
