package notification.listener.service;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

final class NotificationBackgroundExecutor implements MethodChannel.MethodCallHandler {
    private static final String TAG = "NotificationBackground";
    private static final String CHANNEL = "com.budget.tracker_app/notification_background";

    private static final Handler MAIN_HANDLER = new Handler(Looper.getMainLooper());
    private static final List<HashMap<String, Object>> PENDING_EVENTS = new ArrayList<>();
    private static final NotificationBackgroundExecutor INSTANCE = new NotificationBackgroundExecutor();

    private static FlutterEngine flutterEngine;
    private static MethodChannel channel;
    private static boolean backgroundReady = false;
    private static boolean engineStarting = false;

    private NotificationBackgroundExecutor() {
    }

    static void dispatch(Context context, HashMap<String, Object> event) {
        synchronized (PENDING_EVENTS) {
            PENDING_EVENTS.add(event);
        }
        ensureEngineStarted(context.getApplicationContext());
        flushPendingEvents();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if ("backgroundReady".equals(call.method)) {
            backgroundReady = true;
            result.success(null);
            flushPendingEvents();
            return;
        }
        result.notImplemented();
    }

    private static void ensureEngineStarted(Context context) {
        if (flutterEngine != null || engineStarting) {
            return;
        }
        engineStarting = true;

        MAIN_HANDLER.post(() -> {
            try {
                if (flutterEngine != null) {
                    engineStarting = false;
                    flushPendingEvents();
                    return;
                }

                io.flutter.embedding.engine.loader.FlutterLoader loader = FlutterInjector.instance().flutterLoader();
                loader.startInitialization(context);
                loader.ensureInitializationComplete(context, null);

                FlutterEngine engine = new FlutterEngine(context);
                registerGeneratedPlugins(engine);

                MethodChannel methodChannel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
                methodChannel.setMethodCallHandler(INSTANCE);

                flutterEngine = engine;
                channel = methodChannel;
                backgroundReady = false;

                DartExecutor.DartEntrypoint entrypoint = new DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "notificationBackgroundMain"
                );
                engine.getDartExecutor().executeDartEntrypoint(entrypoint);
                Log.i(TAG, "Started headless Flutter engine for notification processing");
            } catch (Throwable error) {
                Log.e(TAG, "Failed to start headless Flutter engine", error);
            } finally {
                engineStarting = false;
            }
        });
    }

    private static void flushPendingEvents() {
        final MethodChannel currentChannel = channel;
        if (currentChannel == null || !backgroundReady) {
            return;
        }

        final List<HashMap<String, Object>> eventsToDispatch = new ArrayList<>();
        synchronized (PENDING_EVENTS) {
            if (PENDING_EVENTS.isEmpty()) {
                return;
            }
            eventsToDispatch.addAll(PENDING_EVENTS);
            PENDING_EVENTS.clear();
        }

        MAIN_HANDLER.post(() -> {
            for (HashMap<String, Object> event : eventsToDispatch) {
                currentChannel.invokeMethod("handleNotification", event);
            }
        });
    }

    private static void registerGeneratedPlugins(FlutterEngine engine) {
        try {
            Class<?> registrant = Class.forName("io.flutter.plugins.GeneratedPluginRegistrant");
            Method registerWith = registrant.getDeclaredMethod("registerWith", FlutterEngine.class);
            registerWith.invoke(null, engine);
        } catch (Throwable error) {
            Log.w(TAG, "Unable to register generated Flutter plugins", error);
        }
    }
}