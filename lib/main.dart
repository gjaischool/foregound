import 'dart:async'; // Timer 등 비동기 작업을 위한 패키지
import 'dart:io'; // 플랫폼 특정 기능 사용을 위한 패키지
import 'package:flutter/material.dart'; // Flutter UI 패키지
import 'package:flutter_foreground_task/flutter_foreground_task.dart'; // 포그라운드 서비스 패키지

// 콜백 함수는 항상 최상위 레벨이나 정적 함수여야 합니다.
@pragma('vm:entry-point') // VM이 이 함수를 진입점으로 인식하도록 표시
void startCallback() {
  debugPrint('Starting Foreground  Service...');
  FlutterForegroundTask.setTaskHandler(CounterTaskHandler()); // TaskHandler 설정
  debugPrint('Foreground Service initialized successfully');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // Flutter 엔진 초기화

  // TaskHandler와 UI 간의 통신을 위한 포트를 초기화합니다.
  FlutterForegroundTask.initCommunicationPort();
  runApp(const MainApp()); // 앱 실행
}

// Foreground Task를 처리하는 핸들러 클래스
class CounterTaskHandler extends TaskHandler {
  int _count = 0;

  // 카운트 증가 및 알림 업데이트 메서드
  void _incrementCount() {
    _count++;

    // 알림 내용을 업데이트합니다.
    FlutterForegroundTask.updateService(
      notificationTitle: 'Hello MyTaskHandler :)', // 카메라 촬영중으로 바꾸기
      notificationText: 'count: $_count',
    );
    // UI로 현재 카운트 전송
    FlutterForegroundTask.sendDataToMain(_count);
  }

  // 서비스 시작 시 호출되는 메서드
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('onStart(starter: ${starter.name})');
    _incrementCount();
  }

  // [ForegroundTaskOptions]의 eventAction에 의해 호출됩니다.
  // - nothing() : onRepeatEvent 콜백을 사용하지 않습니다.
  // - once() : onRepeatEvent를 한 번만 호출합니다.
  // - repeat(interval) : onRepeatEvent를 밀리초 간격으로 호출합니다.
  // 주기적으로 실행되는 이벤트 처리 메서드
  @override
  void onRepeatEvent(DateTime timestamp) {
    _incrementCount();
  }

  // 서비스 종료 시 호출되는 메서드
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('onDestroy');
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final ValueNotifier<int?> _counter = ValueNotifier<int?>(null);
  final GlobalKey<OverlayState> _overlayKey = GlobalKey<OverlayState>();
  OverlayEntry? _overlayEntry; // 오버레이 엔트리
  Timer? _messageTimer; // 메시지 표시 타이머
  static Offset _overlayPosition = const Offset(20, 100);

  // 서비스 초기화
  Future<void> _initializeService() async {
    // 필수 권한 요청
    if (Platform.isAndroid) {
      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      // onNotificationPressed 함수가 호출되려면 "android.permission.SYSTEM_ALERT_WINDOW" 권한이 필요합니다.
      if (!await FlutterForegroundTask.canDrawOverlays) {
        await FlutterForegroundTask.openSystemAlertWindowSettings();
      }
      // This function requires `android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission.
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }
    // 포그라운드 서비스 초기화
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'counter_service',
        channelName: '카운터 서비스',
        channelDescription: '포그라운드에서 실행되는 카운터 서비스입니다.',
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true, // 기기 재시작 시 자동 실행
        allowWakeLock: true, // 절전 모드 방지
      ),
    );
    // 서비스 시작
    await FlutterForegroundTask.startService(
      serviceId: 123,
      notificationTitle: '카운터 서비스',
      notificationText: '서비스가 시작되었습니다',
      callback: startCallback,
    );
  }

  void _updateOverlay(int count, {bool showAnimation = false}) {
    _overlayEntry?.remove();
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: _overlayPosition.dx,
        top: _overlayPosition.dy,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onPanUpdate: (details) {
              _overlayPosition += details.delta;
              _overlayEntry?.markNeedsBuild();
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                showAnimation ? '카운트가 $count(으)로 증가되었습니다!' : '카운트: $count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _overlayKey.currentState?.insert(_overlayEntry!);

    if (showAnimation) {
      _messageTimer?.cancel();
      _messageTimer = Timer(
        const Duration(seconds: 2),
        () => _updateOverlay(count),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is int) {
        final previousValue = _counter.value;
        _counter.value = data;
        // 이전 값이 있고, 현재 값이 더 큰 경우에만 애니메이션 표시
        _updateOverlay(data,
            showAnimation: previousValue != null && data > previousValue);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeService();
    });
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _overlayEntry?.remove();
    FlutterForegroundTask.removeTaskDataCallback((data) {});
    _counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Overlay(
        key: _overlayKey,
        initialEntries: [
          OverlayEntry(
            builder: (context) => WithForegroundTask(
              child: Container(),
            ),
          )
        ],
      ),
    );
  }
}


// E/flutter ( 9442): [ERROR:flutter/runtime/dart_isolate.cc(862)] Could not resolve main entrypoint function.
// E/flutter ( 9442): [ERROR:flutter/runtime/dart_isolate.cc(171)] Could not run the run main Dart entrypoint.
// E/flutter ( 9442): [ERROR:flutter/runtime/runtime_controller.cc(549)] Could not create root isolate.
// E/flutter ( 9442): [ERROR:flutter/shell/common/shell.cc(690)] Could not launch engine with configuration.