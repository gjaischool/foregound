import 'dart:async'; // Timer 등 비동기 작업을 위한 패키지
import 'dart:io'; // 플랫폼 특정 기능 사용을 위한 패키지
import 'package:flutter/material.dart'; // Flutter UI 패키지
import 'package:flutter_foreground_task/flutter_foreground_task.dart'; // 포그라운드 서비스 패키지
import 'overlay_widget.dart'; // 커스텀 오버레이 위젯 파일

// 콜백 함수는 항상 최상위 레벨이나 정적 함수여야 합니다.
@pragma('vm:entry-point') // VM이 이 함수를 진입점으로 인식하도록 표시
void startCallback() {
  debugPrint('Starting Foreground  Service...');
  FlutterForegroundTask.setTaskHandler(MyTaskHandler()); // TaskHandler 설정
  debugPrint('Foreground Service initialized successfully');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // Flutter 엔진 초기화

  // TaskHandler와 UI 간의 통신을 위한 포트를 초기화합니다.
  FlutterForegroundTask.initCommunicationPort();
  runApp(const ExampleApp()); // 앱 실행
}

// Foreground Task를 처리하는 핸들러 클래스
class MyTaskHandler extends TaskHandler {
  static const String incrementCountCommand = 'incrementCount'; // 카운트 증가 명령어
  int _count = 0; // 카운터 변수

  // 카운트 증가 및 알림 업데이트 메서드
  void _incrementCount() {
    _count++;

    // 알림 내용을 업데이트합니다.
    FlutterForegroundTask.updateService(
      notificationTitle: 'Hello MyTaskHandler :)',
      notificationText: 'count: $_count',
    );

    // 메인 isolate로 데이터를 전송합니다.
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

  // UI로부터 데이터 수신 시 호출되는 메서드
  // _incrementCount() 에서 카운터를 전달받음
  @override
  void onReceiveData(Object data) {
    debugPrint('onReceiveData: $data');
    if (data == incrementCountCommand) {
      _incrementCount();
    }
  }
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: {
        '/': (context) => const ExamplePage(), // 메인 페이지를 루트 경로로 설정
      },
      initialRoute: '/',
    );
  }
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<StatefulWidget> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  final ValueNotifier<Object?> _taskDataListenable =
      ValueNotifier(null); // Task 데이터 관리
  final GlobalKey<OverlayState> _overlayKey =
      GlobalKey<OverlayState>(); // 오버레이 상태 키
  OverlayEntry? _overlayEntry; // 오버레이 엔트리
  Timer? _messageTimer; // 메시지 표시 타이머
  int? _lastValue; // 마지막 카운트 값

  // 오버레이 위젯 표시 메서드
  void _showOverlay(int count, {bool showIncrementMessage = false}) {
    _overlayEntry?.remove(); // 기존 오버레이 제거
    _overlayEntry = OverlayEntry(
      builder: (context) => DraggableCounterOverlay(
        count: count,
        showIncrementMessage: showIncrementMessage,
      ),
    );

    _overlayKey.currentState?.insert(_overlayEntry!); // 새 오버레이 삽입
  }

  // 필요한 권한 요청 메서드
  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Android 13 이상에서 필요한 알림 권한 요청
      final NotificationPermission notificationPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      // onNotificationPressed 함수가 호출되려면 "android.permission.SYSTEM_ALERT_WINDOW" 권한이 필요합니다.
      // 권한이 거부된 상태에서 알림이 눌리면,
      // onNotificationPressed 함수는 호출되지 않고 앱이 열립니다.
      // onNotificationPressed나 launchApp 함수를 사용하지 않는다면,
      // 이 코드를 작성할 필요가 없습니다.
      // SYSTEM_ALERT_WINDOW 권한 체크 및 요청 (오버레이 표시에 필요)
      if (!await FlutterForegroundTask.canDrawOverlays) {
        await FlutterForegroundTask.openSystemAlertWindowSettings();
      }

      // This function requires `android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission.
      // 배터리 최적화 예외 권한 (백그라운드 실행 유지에 필요)
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      // 정확한 알람 서비스, 헬스케어 서비스, 블루투스 통신과 같이
      // 장기 생존이 필요한 서비스를 제공하는 경우에만 이 유틸리티를 사용하세요.
      // 이 유틸리티는 "android.permission.SCHEDULE_EXACT_ALARM" 권한이 필요합니다.
      // 이 권한을 사용하면 구글 정책으로 인해 앱 배포가 어려워질 수 있습니다.
      // 정확한 알람 권한 체크 및 요청
      // if (!await FlutterForegroundTask.canScheduleExactAlarms) {
      //   await FlutterForegroundTask.openAlarmsAndRemindersSettings();
      // }
    }
  }

  void _initService() {
    FlutterForegroundTask.init(
      // 안드로이드 알림 옵션 설정
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'foreground_service',
        channelName: 'Foreground Service Notification',
        channelDescription: '이 알림은 포그라운드 서비스가 실행 중일 때 표시됩니다.',
        onlyAlertOnce: true,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      // iOS 알림 옵션 설정
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      // 포그라운드 작업 옵션 설정
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // 5초마다 반복
        autoRunOnBoot: true, // 기기 재시작 시 자동 실행
        autoRunOnMyPackageReplaced: true, // 앱 업데이트 시 자동 실행
        allowWakeLock: true, // 절전 모드 방지
        allowWifiLock: true, // WiFi Lock 허용
      ),
    );
  }

  // 서비스 시작 함수
  Future<ServiceRequestResult> _startService() async {
    debugPrint('Attempting to start foreground service...');

    // 이미 실행 중이면 재시작
    // if (await FlutterForegroundTask.isRunningService) {
    //   return FlutterForegroundTask.restartService();
    // }
    // 새로 시작
    return FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: '포그라운드 서비스가 실행 중입니다',
      notificationText: '앱으로 돌아가려면 탭하세요',
      notificationIcon: null,
      notificationButtons: [
        const NotificationButton(id: 'btn_hello', text: 'hello'),
      ],
      callback: startCallback,
    );
  }

  // 서비스 중지 함수
  Future<ServiceRequestResult> _stopService() async {
    return FlutterForegroundTask.stopService();
  }

  // TaskHandler로부터 데이터 수신 시 호출되는 콜백
  void _onReceiveTaskData(Object data) {
    debugPrint('onReceiveTaskData: $data');
    _taskDataListenable.value = data;

    // 데이터가 int 타입인지 확인
    if (data is int) {
      final currentValue = data;
      final isIncremented = _lastValue != null && currentValue > _lastValue!;

      // 증가했을 때만 증가 메시지 표시하고 타이머 설정
      if (isIncremented) {
        _messageTimer?.cancel(); // 이전 타이머가 있다면 취소
        _showOverlay(currentValue, showIncrementMessage: true);

        // 2초 후에 기본 카운터 표시로 돌아감
        _messageTimer = Timer(const Duration(seconds: 2), () {
          if (_overlayEntry?.mounted ?? false) {
            _showOverlay(currentValue);
          }
        });
      } else {
        _showOverlay(currentValue);
      }

      _lastValue = currentValue;
    }
  }

  // UI에서 카운트 증가 요청 메서드
  void _incrementCount() {
    FlutterForegroundTask.sendDataToTask(MyTaskHandler.incrementCountCommand);
  }

  // 위젯 초기화 메서드
  @override
  void initState() {
    super.initState();
    // TaskHandler로부터 데이터를 받기 위한 콜백 등록
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    // UI 렌더링 후 권한 요청 및 서비스 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestPermissions();
      _initService();

      // 초기 오버레이 표시
      if (_taskDataListenable.value is int) {
        _showOverlay(_taskDataListenable.value as int);
      }
    });
  }

  // 위젯 정리 메서드
  @override
  void dispose() {
    _messageTimer?.cancel();
    _overlayEntry?.remove();
    // TaskHandler로부터 데이터를 받는 콜백 제거
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _taskDataListenable.dispose();
    super.dispose();
  }

  // UI 빌드 메서드
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Overlay(
        key: _overlayKey,
        initialEntries: [
          OverlayEntry(
            builder: (context) => WithForegroundTask(
              child: Scaffold(
                appBar: _buildAppBar(),
                body: _buildContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 앱바 빌드 메서드
  AppBar _buildAppBar() {
    return AppBar(
      title: const Text('Flutter Foreground Task'),
      centerTitle: true,
    );
  }

  // // 본문 컨텐츠 빌드 메서드
  Widget _buildContent() {
    return SafeArea(
      child: Column(
        children: [
          Expanded(child: _buildCommunicationText()),
          _buildServiceControlButtons(),
        ],
      ),
    );
  }

  // TaskHandler로부터 받은 데이터 표시 위젯
  Widget _buildCommunicationText() {
    return ValueListenableBuilder(
      valueListenable: _taskDataListenable,
      builder: (context, data, _) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('TaskHandler로부터 받은 데이터:'),
              Text('$data', style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        );
      },
    );
  }

  // 서비스 제어 버튼 빌드 메서드
  Widget _buildServiceControlButtons() {
    // 버튼 생성 헬퍼 함수
    buttonBuilder(String text, {VoidCallback? onPressed}) {
      return ElevatedButton(
        onPressed: onPressed,
        child: Text(text),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buttonBuilder('서비스 시작', onPressed: _startService),
          buttonBuilder('서비스 중지', onPressed: _stopService),
          buttonBuilder('카운트 증가', onPressed: _incrementCount),
        ],
      ),
    );
  }
}




// E/flutter ( 9442): [ERROR:flutter/runtime/dart_isolate.cc(862)] Could not resolve main entrypoint function.
// E/flutter ( 9442): [ERROR:flutter/runtime/dart_isolate.cc(171)] Could not run the run main Dart entrypoint.
// E/flutter ( 9442): [ERROR:flutter/runtime/runtime_controller.cc(549)] Could not create root isolate.
// E/flutter ( 9442): [ERROR:flutter/shell/common/shell.cc(690)] Could not launch engine with configuration.