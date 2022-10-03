import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:smooth/src/graft/adapter_in_main_tree.dart';
import 'package:smooth/src/graft/auxiliary_tree_root_view.dart';
import 'package:smooth/src/remove_sub_tree_widget.dart';
import 'package:smooth/src/service_locator.dart';

class GraftAuxiliaryTreeRegistry {
  Iterable<GraftAuxiliaryTreePack> get trees => _trees;
  final _trees = Set<GraftAuxiliaryTreePack>.identity();

  void _attach(GraftAuxiliaryTreePack value) {
    assert(!_trees.contains(value));
    _trees.add(value);
  }

  void _detach(GraftAuxiliaryTreePack value) {
    assert(_trees.contains(value));
    _trees.remove(value);
  }
}

class MainSubTreeSlotData {
  final layerHandle = LayerHandle(OffsetLayer());
  Size? size;

  void dispose() {
    layerHandle.layer = null;
    size = null;
  }
}

class GraftAuxiliaryTreePack<S extends Object> {
  late final PipelineOwner pipelineOwner;
  late final GraftAuxiliaryTreeRootView rootView;
  late final BuildOwner buildOwner;
  late final RenderObjectToWidgetElement<RenderBox> element;

  MainSubTreeSlotData mainSubTreeData(S slot) =>
      _mainSubTreeDataOfSlot[slot] ??= MainSubTreeSlotData();
  final _mainSubTreeDataOfSlot = <S, MainSubTreeSlotData>{};

  void removeMainSubTreeSlotsWhere(bool Function(S slot) test) {
    final keysToRemove = _mainSubTreeDataOfSlot.keys.where(test).toList();
    for (final key in keysToRemove) {
      final removed = _mainSubTreeDataOfSlot.remove(key)!;
      removed.dispose();
    }
  }

  final _tickerRegistry = TickerRegistry();
  final _removeSubTreeController = RemoveSubTreeController();
  final adapterInMainTreeController = GraftAdapterInMainTreeController();
  Duration? _previousRunPipelineTimeStamp;

  // final childPlaceholderRegistry = SmoothChildPlaceholderRegistry();

  GraftAuxiliaryTreePack(Widget widget) {
    pipelineOwner = PipelineOwner();
    rootView = pipelineOwner.rootNode = GraftAuxiliaryTreeRootView(
      configuration:
          const GraftAuxiliaryTreeRootViewConfiguration(size: Size.zero),
    );
    buildOwner = BuildOwner(
      focusManager: FocusManager(),
      // onBuildScheduled: () =>
      //     print('second tree BuildOwner.onBuildScheduled called'),
    );

    rootView.prepareInitialFrame();

    final wrappedWidget = RemoveSubTreeWidget(
      controller: _removeSubTreeController,
      // TODO may merge these providers (inherited widgets)
      child: AuxiliaryTreePackProvider(
        pack: this,
        // child: SmoothChildPlaceholderRegistryProvider(
        //   registry: childPlaceholderRegistry,
        child: TickerRegistryInheritedWidget(
          registry: _tickerRegistry,
          child: widget,
        ),
      ),
    );

    element = RenderObjectToWidgetAdapter<RenderBox>(
      container: rootView,
      debugShortDescription: '[AuxiliaryTreePack#${shortHash(this)}.root]',
      child: wrappedWidget,
    ).attachToRenderTree(buildOwner);

    ServiceLocator.instance.auxiliaryTreeRegistry._attach(this);
  }

  void runPipeline(
    Duration timeStamp, {
    required bool skipIfTimeStampUnchanged,
    required String debugReason,
  }) {
    // https://github.com/fzyzcjy/flutter_smooth/issues/23#issuecomment-1261687755
    if (skipIfTimeStampUnchanged &&
        _previousRunPipelineTimeStamp == timeStamp) {
      // print(
      //     '$runtimeType runPipeline skip since timeStamp=$timeStamp same as previous');
      return;
    }
    _previousRunPipelineTimeStamp = timeStamp;

    // print(
    //     'hi $runtimeType.runPipeline debugReason=$debugReason layer=${rootView.layer}');

    Timeline.timeSync('AuxTree.RunPipeline', () {
      // print(
      //     '$runtimeType runPipeline start timeStamp=$timeStamp debugReason=$debugReason');

      _callExtraTickerTick(timeStamp);

      // NOTE reference: WidgetsBinding.drawFrame & RendererBinding.drawFrame
      // https://github.com/fzyzcjy/yplusplus/issues/5778#issuecomment-1254490708
      buildOwner.buildScope(element);
      pipelineOwner.flushLayout();
      pipelineOwner.flushCompositingBits();
      _temporarilyRemoveDebugActiveLayout(() {
        // NOTE #5884
        // ignore: unnecessary_lambdas
        _temporarilyEnsureLayerAttached(() {
          // print(
          //     'hi call pipelineOwner.flushPaint pipelineOwner=${describeIdentity(pipelineOwner)} nodesNeedingPaint=${pipelineOwner.nodesNeedingPaint}');
          pipelineOwner.flushPaint();
        });
      });
      // renderView.compositeFrame(); // this sends the bits to the GPU
      // pipelineOwner.flushSemantics(); // this also sends the semantics to the OS.
      buildOwner.finalizeTree();

      // printWrapped(
      //     '$runtimeType.runPipeline after finalizeTree rootView.layer=${rootView.layer!.toStringDeep()}');

      // printWrapped('$runtimeType.runPipeline end');
      // printWrapped('pack.rootView.layer=${rootView.layer?.toStringDeep()}');
      // printWrapped(
      //     'pack.element.renderObject=${element.renderObject.toStringDeep()}');

      // print('$runtimeType runPipeline end');
    });
  }

  // NOTE #5884
  void _temporarilyEnsureLayerAttached(void Function() run) {
    final dummyOwner = _DummyOwnerForLayer();

    // ignore: invalid_use_of_protected_member
    final needAction = !rootView.layer!.attached;

    if (needAction) {
      // ignore: invalid_use_of_protected_member
      rootView.layer!.attach(dummyOwner);
    }
    try {
      run();
    } finally {
      if (needAction) {
        // ignore: invalid_use_of_protected_member
        assert(rootView.layer!.owner == dummyOwner);
        rootView.layer!.detach(); // ignore: invalid_use_of_protected_member
      }
    }
  }

  /// #5814
  void _callExtraTickerTick(Duration timeStamp) {
    // #5821
    // final now = DateTime.now();
    // final timeStamp = SchedulerBinding.instance.currentFrameTimeStamp +
    //     Duration(
    //         microseconds: now.microsecondsSinceEpoch -
    //             SchedulerBinding.instance.currentFrameStartTimeUs!);

    // print('$runtimeType callExtraTickerTick tickers=${tickerRegistry.tickers}');

    for (final ticker in _tickerRegistry.tickers) {
      ticker.maybeExtraTick(timeStamp);
    }
  }

  void dispose() {
    ServiceLocator.instance.auxiliaryTreeRegistry._detach(this);

    // #54
    final previousRunPipelineTimeStamp = _previousRunPipelineTimeStamp;
    if (previousRunPipelineTimeStamp != null) {
      _removeSubTreeController.markRemoveSubTree();

      runPipeline(
        previousRunPipelineTimeStamp,
        skipIfTimeStampUnchanged: false,
        debugReason: 'AuxiliaryTreePack.dispose',
      );
    }
  }
}

void _temporarilyRemoveDebugActiveLayout(VoidCallback f) {
  // NOTE we have to temporarily remove debugActiveLayout
  // b/c [SecondTreeRootView.paint] is called inside [preemptRender]
  // which is inside main tree's build/layout.
  // thus, if not set it to null we will see error
  // https://github.com/fzyzcjy/yplusplus/issues/5783#issuecomment-1254974511
  // In short, this is b/c [debugActiveLayout] is global variable instead
  // of per-tree variable
  // and also
  // https://github.com/fzyzcjy/yplusplus/issues/5793#issuecomment-1256095858
  final oldDebugActiveLayout = RenderObject.debugActiveLayout;
  RenderObject.debugActiveLayout = null;
  try {
    f();
  } finally {
    RenderObject.debugActiveLayout = oldDebugActiveLayout;
  }
}

class _DummyOwnerForLayer {}

class AuxiliaryTreePackProvider extends InheritedWidget {
  final GraftAuxiliaryTreePack pack;

  const AuxiliaryTreePackProvider({
    super.key,
    required super.child,
    required this.pack,
  });

  static AuxiliaryTreePackProvider of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuxiliaryTreePackProvider>()!;

  @override
  bool updateShouldNotify(AuxiliaryTreePackProvider old) => old.pack != pack;
}