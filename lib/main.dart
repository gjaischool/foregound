import 'dart:async'; // Timer 등 비동기 작업을 위한 패키지
import 'dart:io'; // 플랫폼 특정 기능 사용을 위한 패키지
import 'package:flutter/material.dart'; // Flutter UI 패키지
import 'package:flutter_foreground_task/flutter_foreground_task.dart'; // 포그라운드 서비스 패키지

/// 포그라운드 서비스의 진입점 함수
/// Flutter가 새로운 Isolate에서 이 함수를 실행합니다.
/// @pragma('vm:entry-point')는 컴파일러에게 이 함수를 진입점으로 표시합니다.
@pragma('vm:entry-point')
void startCallback() {
  debugPrint('Starting Foreground  Service...');
  FlutterForegroundTask.setTaskHandler(CounterTaskHandler()); // TaskHandler 설정
  debugPrint('Foreground Service initialized successfully');
}

void main() {
  // Flutter 바인딩 초기화 (플러그인 사용을 위해 필요)
  WidgetsFlutterBinding.ensureInitialized();

  // 포그라운드 서비스와 UI 간의 통신을 위한 포트 초기화
  FlutterForegroundTask.initCommunicationPort();

  // 앱 실행
  runApp(const MainApp());
}

// Foreground Task를 처리하는 핸들러 클래스
class CounterTaskHandler extends TaskHandler {
  int _count = 0;

  /// 카운터 값을 증가시키고 UI에 업데이트하는 메서드
  void _incrementCount() {
    _count++;

    // 상태바에 표시될 알림 업데이트
    FlutterForegroundTask.updateService(
      notificationTitle: 'Hello MyTaskHandler :)', // 카메라 촬영중으로 바꾸기
      notificationText: 'count: $_count',
    );

    // UI로 현재 카운트 값 전송
    // sendDataToMain을 통해 메인 Isolate로 데이터를 전송합니다.
    FlutterForegroundTask.sendDataToMain(_count);
  }

  /// 서비스가 시작될 때 호출되는 메서드
  /// timestamp: 서비스 시작 시간
  /// starter: 서비스 시작 방법 (BOOT, RESTART 등)
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('onStart(starter: ${starter.name})');
    _incrementCount();
  }

  /// 주기적으로 실행되는 이벤트 처리 메서드
  /// ForegroundTaskOptions의 eventAction 설정에 따라 호출 주기가 결정됩니다.
  @override
  void onRepeatEvent(DateTime timestamp) {
    _incrementCount();
  }

  /// 서비스가 종료될 때 호출되는 메서드
  /// 리소스 정리 등의 작업을 수행할 수 있습니다.
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
  /// 카운터 값을 관리하는 ValueNotifier
  final ValueNotifier<int?> _counter = ValueNotifier<int?>(null);

  /// 오버레이 위젯의 상태를 관리하기 위한 키
  final GlobalKey<OverlayState> _overlayKey = GlobalKey<OverlayState>();

  /// 현재 표시 중인 오버레이 엔트리
  OverlayEntry? _overlayEntry;

  /// 증가 메시지 표시를 위한 타이머
  Timer? _messageTimer;

  /// 오버레이 위젯의 위치 (드래그로 위치 변경 가능)
  static Offset _overlayPosition = const Offset(20, 100);

  /// 포그라운드 서비스 초기화 및 필요한 권한 요청 메서드
  Future<void> _initializeService() async {
    // 필수 권한 요청
    if (Platform.isAndroid) {
      // 알림 권한 체크 및 요청
      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      // 오버레이 표시 권한 체크 및 요청
      if (!await FlutterForegroundTask.canDrawOverlays) {
        await FlutterForegroundTask.openSystemAlertWindowSettings();
      }
      // 배터리 최적화 예외 권한 체크 및 요청
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
      // 포그라운드 작업 옵션 설정
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // 5초마다 반복
        autoRunOnBoot: true, // 기기 재시작 시 자동 실행
        allowWakeLock: true, // 절전 모드 방지
      ),
    );
    // 포그라운드 서비스 시작
    await FlutterForegroundTask.startService(
      serviceId: 123,
      notificationTitle: '카운터 서비스',
      notificationText: '서비스가 시작되었습니다',
      callback: startCallback,
    );
  }

  /// 오버레이 위젯을 업데이트하는 메서드
  /// count: 표시할 카운터 값
  /// showAnimation: 증가 애니메이션 표시 여부
  void _updateOverlay(int count, {bool showAnimation = false}) {
    _overlayEntry?.remove(); // 기존 오버레이 제거

    // 새 오버레이 생성
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: _overlayPosition.dx,
        top: _overlayPosition.dy,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            // 드래그로 위치 이동 처리
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
    // 오버레이 삽입
    _overlayKey.currentState?.insert(_overlayEntry!);

    // 증가 애니메이션 처리
    if (showAnimation) {
      _messageTimer?.cancel();
      _messageTimer = Timer(
        const Duration(seconds: 2),
        () => _updateOverlay(count),
      );
    }
  }

  /// 위젯 초기화 시 호출되는 메서드
  @override
  void initState() {
    super.initState();

    // 포그라운드 서비스로부터 데이터를 받는 콜백 등록
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data is int) {
        final previousValue = _counter.value;
        _counter.value = data;
        // 카운터 값이 증가했을 때만 애니메이션 표시
        _updateOverlay(data,
            showAnimation: previousValue != null && data > previousValue);
      }
    });

    // UI 렌더링 후 서비스 초기화 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeService();
    });
  }

  /// 위젯 제거 시 호출되는 메서드
  /// 리소스 정리를 담당합니다.
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