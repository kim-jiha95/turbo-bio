package com.turbobio

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.fragment.app.FragmentActivity
import com.facebook.react.bridge.*
import com.facebook.react.module.annotations.ReactModule
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.PrivateKey
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import android.util.Base64

@ReactModule(name = TurboBioModule.NAME)
class TurboBioModule(reactContext: ReactApplicationContext) : 
    ReactContextBaseJavaModule(reactContext) {
    
    private val executor: Executor = Executors.newSingleThreadExecutor()
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private val KEY_NAME = "com.turbobio.keys"
    private val ALLOWED_AUTHENTICATORS = BiometricManager.Authenticators.BIOMETRIC_STRONG

    override fun getName() = NAME

    override fun canOverrideExistingModule(): Boolean {
        return true
    }

    @ReactMethod
    fun isSensorAvailable(promise: Promise) {
        val biometricManager = BiometricManager.from(reactApplicationContext)
        val canAuthenticate = biometricManager.canAuthenticate(ALLOWED_AUTHENTICATORS)
        
        val result = WritableNativeMap().apply {
            putBoolean("available", canAuthenticate == BiometricManager.BIOMETRIC_SUCCESS)
            putString("biometryType", "Biometrics")
            if (canAuthenticate != BiometricManager.BIOMETRIC_SUCCESS) {
                putString("error", when (canAuthenticate) {
                    BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> "No biometric hardware"
                    BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> "Biometric hardware unavailable"
                    BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "No biometric enrolled"
                    else -> "Biometric error"
                })
            }
        }
        promise.resolve(result)
    }

    @ReactMethod
    fun createKeys(promise: Promise) {
        try {
            val keyPairGenerator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore"
            )

            val builder = KeyGenParameterSpec.Builder(
                KEY_NAME,
                KeyProperties.PURPOSE_SIGN
            ).setDigests(KeyProperties.DIGEST_SHA256)
                .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                .setKeySize(2048)
                .setUserAuthenticationRequired(true)
                .setUserAuthenticationParameters(
                    0,
                    KeyProperties.AUTH_BIOMETRIC_STRONG
                )
                .setInvalidatedByBiometricEnrollment(true)
                .setIsStrongBoxBacked(false)

            keyPairGenerator.initialize(builder.build())
            val keyPair = keyPairGenerator.generateKeyPair()

            val publicKey = keyPair.public.encoded
            val publicKeyString = Base64.encodeToString(publicKey, Base64.NO_WRAP)

            val result = WritableNativeMap().apply {
                putString("publicKey", publicKeyString)
            }
            promise.resolve(result)
        } catch (e: Exception) {
            promise.reject("KEY_GENERATION_ERROR", e.message)
        }
    }

    @ReactMethod
    fun biometricKeysExist(promise: Promise) {
        val result = WritableNativeMap().apply {
            putBoolean("keysExist", keyStore.containsAlias(KEY_NAME))
        }
        promise.resolve(result)
    }

    @ReactMethod
    fun deleteKeys(promise: Promise) {
        try {
            keyStore.deleteEntry(KEY_NAME)
            val result = WritableNativeMap().apply {
                putBoolean("keysDeleted", true)
            }
            promise.resolve(result)
        } catch (e: Exception) {
            val result = WritableNativeMap().apply {
                putBoolean("keysDeleted", false)
            }
            promise.resolve(result)
        }
    }

    @ReactMethod
    fun createSignature(options: ReadableMap, promise: Promise) {
        val activity = currentActivity as? FragmentActivity ?: run {
            promise.reject("NO_ACTIVITY", "No activity available")
            return
        }

        try {
            val promptMessage = options.getString("promptMessage") ?: run {
                promise.reject("INVALID_PARAMS", "Missing prompt message")
                return
            }
            val payload = options.getString("payload") ?: run {
                promise.reject("INVALID_PARAMS", "Missing payload")
                return
            }
            val cancelButtonText = options.getString("cancelButtonText") ?: "취소"

            val signature = Signature.getInstance("SHA256withRSA")
            val privateKey = keyStore.getKey(KEY_NAME, null) as PrivateKey
            signature.initSign(privateKey)

            val cryptoObject = BiometricPrompt.CryptoObject(signature)

            activity.runOnUiThread {
                val promptInfo = BiometricPrompt.PromptInfo.Builder()
                    .setTitle(promptMessage)
                    .setNegativeButtonText(cancelButtonText)
                    .setAllowedAuthenticators(ALLOWED_AUTHENTICATORS)
                    .build()

                val biometricPrompt = BiometricPrompt(activity, executor,
                    object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                            try {
                                val cryptoSignature = result.cryptoObject?.signature
                                cryptoSignature?.update(payload.toByteArray())
                                val signedData = cryptoSignature?.sign()
                                val signatureString = Base64.encodeToString(signedData, Base64.NO_WRAP)

                                val resultMap = WritableNativeMap().apply {
                                    putBoolean("success", true)
                                    putString("signature", signatureString)
                                }
                                promise.resolve(resultMap)
                            } catch (e: Exception) {
                                promise.reject("SIGNING_FAILED", e.message)
                            }
                        }

                        override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                            when (errorCode) {
                                BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> {
                                    promise.reject("biometry_lockout", "Biometry is locked due to multiple failed attempts")
                                }
                                BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                                BiometricPrompt.ERROR_USER_CANCELED -> {
                                    val resultMap = WritableNativeMap().apply {
                                        putBoolean("success", false)
                                        putString("error", "User cancellation")
                                    }
                                    promise.resolve(resultMap)
                                }
                                else -> {
                                    promise.reject("AUTHENTICATION_ERROR", errString.toString())
                                }
                            }
                        }

                        override fun onAuthenticationFailed() {
                            promise.reject("AUTHENTICATION_FAILED", "Authentication failed")
                        }
                    })

                biometricPrompt.authenticate(promptInfo, cryptoObject)
            }
        } catch (e: Exception) {
            promise.reject("SIGNATURE_ERROR", e.message)
        }
    }

    @ReactMethod
    fun simplePrompt(options: ReadableMap, promise: Promise) {
        val activity = currentActivity as? FragmentActivity ?: run {
            promise.reject("NO_ACTIVITY", "No activity available")
            return
        }

        val promptMessage = options.getString("promptMessage") ?: run {
            promise.reject("INVALID_PARAMS", "Missing prompt message")
            return
        }
        val cancelButtonText = options.getString("cancelButtonText") ?: "취소"

        activity.runOnUiThread {
            val promptInfo = BiometricPrompt.PromptInfo.Builder()
                .setTitle(promptMessage)
                .setNegativeButtonText(cancelButtonText)
                .build()

            val biometricPrompt = BiometricPrompt(activity, executor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        val resultMap = WritableNativeMap().apply {
                            putBoolean("success", true)
                        }
                        promise.resolve(resultMap)
                    }

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        val resultMap = WritableNativeMap().apply {
                            putBoolean("success", false)
                            putString("error", errString.toString())
                        }
                        promise.resolve(resultMap)
                    }

                    override fun onAuthenticationFailed() {
                        val resultMap = WritableNativeMap().apply {
                            putBoolean("success", false)
                            putString("error", "Authentication failed")
                        }
                        promise.resolve(resultMap)
                    }
                })

            biometricPrompt.authenticate(promptInfo)
        }
    }

    companion object {
        const val NAME = "TurboBio"
    }
}
