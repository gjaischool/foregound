import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // TaskHandler와 UI 간의 통신을 위한 포트를 초기화합니다.
  FlutterForegroundTask.initCommunicationPort();
  runApp(const ExampleApp());
}

// 콜백 함수는 항상 최상위 레벨이나 정적 함수여야 합니다.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  static const String incrementCountCommand = 'incrementCount';

  int _count = 0;

  void _incrementCount() {
    _count++;

    // 알림 내용을 업데이트합니다.
    FlutterForegroundTask.updateService(
      notificationTitle: 'Hello MyTaskHandler :)',
      notificationText: 'count: $_count',
    );

    // 메인 isolate로 데이터를 전송합니다.
    FlutterForegroundTask.sendDataToMain(_count);
  }

  // 태스크가 시작될 때 호출됩니다.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('onStart(starter: ${starter.name})');
    _incrementCount();
  }

  // [ForegroundTaskOptions]의 eventAction에 의해 호출됩니다.
  // - nothing() : onRepeatEvent 콜백을 사용하지 않습니다.
  // - once() : onRepeatEvent를 한 번만 호출합니다.
  // - repeat(interval) : onRepeatEvent를 밀리초 간격으로 호출합니다.
  @override
  void onRepeatEvent(DateTime timestamp) {
    _incrementCount();
  }

  // 태스크가 종료될 때 호출됩니다.
  @override
  Future<void> onDestroy(DateTime timestamp) async {
    print('onDestroy');
  }

  // [FlutterForegroundTask.sendDataToTask]를 사용하여 데이터를 전송할 때 호출됩니다.
  @override
  void onReceiveData(Object data) {
    print('onReceiveData: $data');
    if (data == incrementCountCommand) {
      _incrementCount();
    }
  }

  // 알림 버튼이 눌렸을 때 호출됩니다.
  @override
  void onNotificationButtonPressed(String id) {
    print('onNotificationButtonPressed: $id');
  }

  // 알림 자체가 눌렸을 때 호출됩니다.
  // 안드로이드: 이 기능이 호출되려면 "android.permission.SYSTEM_ALERT_WINDOW" 권한이 필요합니다.
  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
    print('onNotificationPressed');
  }

  // 알림이 해제되었을 때 호출됩니다.
  // 안드로이드: Android 14+ 에서만 작동
  // iOS: iOS 10+ 에서만 작동
  @override
  void onNotificationDismissed() {
    print('onNotificationDismissed');
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
  // TaskHandler로부터 받은 데이터를 관리하는 ValueNotifier
  final ValueNotifier<Object?> _taskDataListenable = ValueNotifier(null);

  Future<void> _requestPermissions() async {
    // Android 13+에서는 포그라운드 서비스 알림을 표시하기 위해 알림 권한을 허용해야 합니다.
    // iOS: 알림이 필요한 경우 권한을 요청하세요.
    // final NotificationPermission notificationPermission =
    //     await FlutterForegroundTask.checkNotificationPermission();
    // if (notificationPermission != NotificationPermission.granted) {
    //   await FlutterForegroundTask.requestNotificationPermission();
    // }

    if (Platform.isAndroid) {
      // onNotificationPressed 함수가 호출되려면 "android.permission.SYSTEM_ALERT_WINDOW" 권한이 필요합니다.
      // 권한이 거부된 상태에서 알림이 눌리면,
      // onNotificationPressed 함수는 호출되지 않고 앱이 열립니다.
      // onNotificationPressed나 launchApp 함수를 사용하지 않는다면,
      // 이 코드를 작성할 필요가 없습니다.
      if (!await FlutterForegroundTask.canDrawOverlays) {
        await FlutterForegroundTask.openSystemAlertWindowSettings();
      }
      // Android 12+에서는 포그라운드 서비스 시작에 제한이 있습니다.
      // 기기 재부팅이나 예기치 않은 문제 발생 시 서비스를 재시작하려면 아래 권한이 필요합니다.
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        // This function requires `android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission.
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      // 정확한 알람 서비스, 헬스케어 서비스, 블루투스 통신과 같이
      // 장기 생존이 필요한 서비스를 제공하는 경우에만 이 유틸리티를 사용하세요.
      // 이 유틸리티는 "android.permission.SCHEDULE_EXACT_ALARM" 권한이 필요합니다.
      // 이 권한을 사용하면 구글 정책으로 인해 앱 배포가 어려워질 수 있습니다.
      if (!await FlutterForegroundTask.canScheduleExactAlarms) {
        // When you call this function, will be gone to the settings page.
        // So you need to explain to the user why set it.
        await FlutterForegroundTask.openAlarmsAndRemindersSettings();
      }
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
        allowWakeLock: true, // Wake Lock 허용
        allowWifiLock: true, // WiFi Lock 허용
      ),
    );
  }

  // 서비스 시작 함수
  Future<ServiceRequestResult> _startService() async {
    if (await FlutterForegroundTask.isRunningService) {
      return FlutterForegroundTask.restartService();
    } else {
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
  }

  // 서비스 중지 함수
  Future<ServiceRequestResult> _stopService() async {
    return FlutterForegroundTask.stopService();
  }

  // TaskHandler로부터 데이터를 받았을 때 호출되는 콜백
  void _onReceiveTaskData(Object data) {
    print('onReceiveTaskData: $data');
    _taskDataListenable.value = data;
  }

  // 카운트 증가 명령을 TaskHandler로 전송
  void _incrementCount() {
    FlutterForegroundTask.sendDataToTask(MyTaskHandler.incrementCountCommand);
  }

  @override
  void initState() {
    super.initState();
    // TaskHandler로부터 데이터를 받기 위한 콜백 등록
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 프레임이 그려진 후 권한 요청 및 서비스 초기화
      await _requestPermissions();
      _initService();
    });
  }

  @override
  void dispose() {
    // TaskHandler로부터 데이터를 받는 콜백 제거
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _taskDataListenable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // WithForegroundTask는 서비스가 실행 중일 때
    // 소프트 백 버튼을 눌렀을 때 앱을 종료하지 않고 최소화하는 위젯입니다.
    return WithForegroundTask(
      child: Scaffold(
        appBar: _buildAppBar(),
        body: _buildContent(),
      ),
    );
  }

  // 앱바 구성
  AppBar _buildAppBar() {
    return AppBar(
      title: const Text('Flutter Foreground Task'),
      centerTitle: true,
    );
  }

  // 본문 내용 구성
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

  // TaskHandler로부터 받은 데이터를 표시하는 위젯
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

  // 서비스 제어 버튼들을 구성하는 위젯
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
