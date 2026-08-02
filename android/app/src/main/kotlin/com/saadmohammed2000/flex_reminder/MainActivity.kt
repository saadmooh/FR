package com.saadmohammed2000.flex_reminder

import android.content.Intent
import com.google.android.play.core.integrity.IntegrityManager
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val integrityChannel = "com.saadmohammed2000.flex_reminder/play_integrity"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupPlayIntegrityChannel(flutterEngine)
    }

    private fun setupPlayIntegrityChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, integrityChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestIntegrityToken" -> {
                        val nonce = call.argument<String>("nonce")
                        val cloudProjectNumber = call.argument<Number>("cloudProjectNumber")?.toLong()
                        if (nonce.isNullOrEmpty() || cloudProjectNumber == null || cloudProjectNumber <= 0) {
                            result.error(
                                "INVALID_ARGUMENTS",
                                "nonce and cloudProjectNumber are required",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        val manager: IntegrityManager =
                            IntegrityManagerFactory.create(applicationContext)
                        manager.requestIntegrityToken(
                            IntegrityTokenRequest.builder()
                                .setNonce(nonce)
                                .setCloudProjectNumber(cloudProjectNumber)
                                .build()
                        ).addOnSuccessListener { response ->
                            result.success(response.token())
                        }.addOnFailureListener { e ->
                            result.error(
                                "INTEGRITY_ERROR",
                                e.message ?: "Play Integrity request failed",
                                e.javaClass.simpleName,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.putExtra("android_launch_intent", intent.toUri(Intent.URI_INTENT_SCHEME))
    }
}
