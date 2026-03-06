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

package org.guardianproject.c2pa_example

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val ballast = mutableListOf<ByteArray>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Test helper: fill JVM heap to simulate post-camera memory pressure
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "c2pa_test_helper").setMethodCallHandler { call, result ->
            when (call.method) {
                "fillHeap" -> {
                    val targetFreeBytes = (call.argument<Number>("targetFreeBytes")?.toLong())
                        ?: (20L * 1024 * 1024)
                    try {
                        val runtime = Runtime.getRuntime()
                        // Allocate 1MB chunks until we're near the target free space
                        while (runtime.maxMemory() - (runtime.totalMemory() - runtime.freeMemory()) > targetFreeBytes + 1024 * 1024) {
                            ballast.add(ByteArray(1024 * 1024))
                        }
                        val used = runtime.totalMemory() - runtime.freeMemory()
                        result.success(mapOf(
                            "maxMemory" to runtime.maxMemory(),
                            "usedMemory" to used,
                            "freeMemory" to (runtime.maxMemory() - used)
                        ))
                    } catch (e: OutOfMemoryError) {
                        result.success(mapOf(
                            "maxMemory" to Runtime.getRuntime().maxMemory(),
                            "usedMemory" to (Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()),
                            "freeMemory" to Runtime.getRuntime().freeMemory()
                        ))
                    }
                }
                "releaseHeap" -> {
                    ballast.clear()
                    System.gc()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
