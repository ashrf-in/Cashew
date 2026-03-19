package com.cashew.notificationsimulator

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.cashew.notificationsimulator.databinding.ActivityMainBinding
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var notificationManager: NotificationManagerCompat
    private lateinit var presets: List<NotificationPreset>

    private var nextNotificationId = 4000
    private var lastNotificationId: Int? = null
    private var pendingNotificationRequest: PendingNotificationRequest? = null

    private val requestNotificationsPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (!granted) {
            pendingNotificationRequest = null
            updateStatus(getString(R.string.status_permission_denied), isError = true)
            return@registerForActivityResult
        }

        val request = pendingNotificationRequest ?: return@registerForActivityResult
        pendingNotificationRequest = null
        postNotification(request.title, request.body)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        notificationManager = NotificationManagerCompat.from(this)
        createNotificationChannel()

        binding.packageNameValue.text = packageName
        presets = createPresets()
        setupPresetDropdown()
        applyPreset(presets.first())

        binding.fillPresetButton.setOnClickListener {
            applySelectedPreset()
        }
        binding.sendNotificationButton.setOnClickListener {
            validateAndSendNotification()
        }
        binding.cancelLastButton.setOnClickListener {
            cancelLastNotification()
        }

        updateStatus(getString(R.string.status_idle))
    }

    private fun setupPresetDropdown() {
        val presetNames = presets.map(NotificationPreset::name)
        val adapter = android.widget.ArrayAdapter(
            this,
            android.R.layout.simple_list_item_1,
            presetNames,
        )
        binding.presetDropdown.setAdapter(adapter)
        binding.presetDropdown.setText(presetNames.first(), false)
        binding.presetDropdown.setOnItemClickListener { _, _, position, _ ->
            applyPreset(presets[position])
        }
    }

    private fun applySelectedPreset() {
        val selectedName = binding.presetDropdown.text?.toString().orEmpty()
        val preset = presets.firstOrNull { it.name == selectedName } ?: presets.first()
        applyPreset(preset)
    }

    private fun applyPreset(preset: NotificationPreset) {
        binding.titleInput.setText(preset.title)
        binding.bodyInput.setText(preset.body)
        clearErrors()
    }

    private fun clearErrors() {
        binding.titleInputLayout.error = null
        binding.bodyInputLayout.error = null
    }

    private fun validateAndSendNotification() {
        clearErrors()

        val title = binding.titleInput.text?.toString()?.trim().orEmpty()
        val body = binding.bodyInput.text?.toString()?.trim().orEmpty()

        var hasError = false
        if (title.isEmpty()) {
            binding.titleInputLayout.error = getString(R.string.error_missing_title)
            hasError = true
        }
        if (body.isEmpty()) {
            binding.bodyInputLayout.error = getString(R.string.error_missing_body)
            hasError = true
        }
        if (hasError) {
            return
        }

        if (!notificationManager.areNotificationsEnabled()) {
            updateStatus(getString(R.string.status_notifications_disabled), isError = true)
            return
        }

        val finalBody = if (binding.appendUniqueReferenceSwitch.isChecked) {
            appendUniqueReference(body)
        } else {
            body
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingNotificationRequest = PendingNotificationRequest(title = title, body = finalBody)
            requestNotificationsPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            updateStatus(getString(R.string.status_permission_required), isError = true)
            return
        }

        postNotification(title, finalBody)
    }

    private fun postNotification(title: String, body: String) {
        val notificationId = nextNotificationId++
        val contentIntent = PendingIntent.getActivity(
            this,
            notificationId,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag(),
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setContentIntent(contentIntent)
            .build()

        notificationManager.notify(notificationId, notification)
        lastNotificationId = notificationId
        updateStatus(getString(R.string.status_posted, notificationId))
    }

    private fun cancelLastNotification() {
        val notificationId = lastNotificationId
        if (notificationId == null) {
            updateStatus(getString(R.string.status_cancel_missing), isError = true)
            return
        }

        notificationManager.cancel(notificationId)
        updateStatus(getString(R.string.status_cancelled, notificationId))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(R.string.channel_description)
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun appendUniqueReference(body: String): String {
        val reference = SimpleDateFormat("HHmmssSSS", Locale.US).format(Date())
        return body.trimEnd() + "\nRef SIM-$reference"
    }

    private fun createPresets(): List<NotificationPreset> {
        val timestamp = SimpleDateFormat("dd MMM yyyy HH:mm", Locale.US).format(Date())
        return listOf(
            NotificationPreset(
                name = getString(R.string.preset_card_purchase),
                title = "Card purchase alert",
                body = "AED 48.25 spent at STARBUCKS DUBAI MALL on card ending 4432 at $timestamp. Available balance AED 1,824.16.",
            ),
            NotificationPreset(
                name = getString(R.string.preset_upi_debit),
                title = "UPI debit alert",
                body = "INR 849.00 sent to TALABAT AE via UPI on $timestamp from A/c XX1042.",
            ),
            NotificationPreset(
                name = getString(R.string.preset_salary_credit),
                title = "Salary credited",
                body = "AED 7,500.00 credited to your account from ACME LLC on $timestamp. Available balance AED 12,331.54.",
            ),
            NotificationPreset(
                name = getString(R.string.preset_cash_withdrawal),
                title = "ATM withdrawal",
                body = "EGP 1,200.00 withdrawn using card ending 1188 at Heliopolis Branch on $timestamp.",
            ),
            NotificationPreset(
                name = getString(R.string.preset_refund),
                title = "Refund processed",
                body = "AED 93.40 refunded by AMAZON AE to card ending 4432 on $timestamp.",
            ),
            NotificationPreset(
                name = getString(R.string.preset_fee),
                title = "Monthly fee charged",
                body = "AED 26.25 charged as account maintenance fee on $timestamp.",
            ),
        )
    }

    private fun pendingIntentImmutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }

    private fun updateStatus(message: String, isError: Boolean = false) {
        binding.statusText.text = message
        val colorRes = if (isError) {
            R.color.simulator_error
        } else {
            R.color.simulator_status_ok
        }
        binding.statusText.setTextColor(ContextCompat.getColor(this, colorRes))
    }

    private data class NotificationPreset(
        val name: String,
        val title: String,
        val body: String,
    )

    private data class PendingNotificationRequest(
        val title: String,
        val body: String,
    )

    companion object {
        private const val CHANNEL_ID = "bank_notification_simulator"
    }
}