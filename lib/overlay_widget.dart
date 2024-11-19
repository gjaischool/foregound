import 'package:flutter/material.dart';

class DraggableCounterOverlay extends StatefulWidget {
  final int count;
  final bool showIncrementMessage;

  const DraggableCounterOverlay({
    super.key,
    required this.count,
    required this.showIncrementMessage,
  });

  @override
  State<DraggableCounterOverlay> createState() =>
      _DraggableCounterOverlayState();
}

class _DraggableCounterOverlayState extends State<DraggableCounterOverlay> {
  static Offset position = const Offset(20, 100); // static으로 변경하여 위치 유지

  String get message => widget.showIncrementMessage
      ? '카운터가 ${widget.count}(으)로 증가했습니다!'
      : '카운터: ${widget.count}';

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            position = Offset(
              position.dx + details.delta.dx,
              position.dy + details.delta.dy,
            );
          });
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
