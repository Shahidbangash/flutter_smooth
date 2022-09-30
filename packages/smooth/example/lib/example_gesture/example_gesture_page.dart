import 'package:example/example_gesture/gesture_visualizer.dart';
import 'package:example/utils/complex_widget.dart';
import 'package:example/utils/debug_plain_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:smooth/smooth.dart';

class ExampleGesturePage extends StatelessWidget {
  const ExampleGesturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Example'),
      ),
      body: GestureVisualizerByListener(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            children: [
              const RepaintBoundary(
                child: CounterWidget(prefix: 'Plain: '),
              ),
              SizedBox(
                height: 120,
                child: SmoothBuilder(
                  builder: (_, child) => const Directionality(
                    textDirection: TextDirection.ltr,
                    child: CounterWidget(prefix: 'Smooth: '),
                  ),
                  // child: Container(color: Colors.green),
                  child: const SizedBox(),
                ),
              ),
              Expanded(
                child: OverflowBox(
                  child: _buildAlwaysRebuildComplexWidget(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static var _dummy = 1;

  Widget _buildAlwaysRebuildComplexWidget() {
    return StatefulBuilder(builder: (_, setState) {
      SchedulerBinding.instance.addPostFrameCallback((_) => setState(() {}));

      return ComplexWidget(
        // thus it will recreate the whole subtree, in each frame
        key: ValueKey('${_dummy++}'),
        listTileCount: 150,
        wrapListTile: null,
      );
    });
  }
}