import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:macos_window_utils/src/native_view_geometry.dart';
import 'package:macos_window_utils/widgets/visual_effect_subview_container/visual_effect_subview_container_resize_event_relay.dart';

import 'visual_effect_subview_container_property_storage.dart';

class VisualEffectSubviewContainerWithGlobalKey extends StatefulWidget {
  final Widget child;
  final double alphaValue;
  final double? cornerRadius;
  final int cornerMask;
  final NSVisualEffectViewMaterial material;
  final NSVisualEffectViewState state;
  final EdgeInsets padding;
  final VisualEffectSubviewContainerResizeEventRelay? resizeEventRelay;

  static const topLeftCorner = VisualEffectSubviewProperties.topLeftCorner;
  static const topRightCorner = VisualEffectSubviewProperties.topRightCorner;
  static const bottomRightCorner =
      VisualEffectSubviewProperties.bottomRightCorner;
  static const bottomLeftCorner =
      VisualEffectSubviewProperties.bottomLeftCorner;

  /// A visual effect subview container which needs to be provided a global key.
  ///
  /// This widget is intended to be used by the [VisualEffectSubviewContainer]
  /// widget. As a user of the [macos_window_utils] package it is recommended to
  /// use that widget instead, as it takes care of the global key creation by
  /// itself.
  const VisualEffectSubviewContainerWithGlobalKey(
      {required GlobalKey key,
      required this.child,
      this.alphaValue = 1.0,
      this.cornerRadius,
      this.cornerMask = 0xf,
      required this.material,
      required this.state,
      required this.padding,
      this.resizeEventRelay})
      : super(key: key);

  @override
  State<VisualEffectSubviewContainerWithGlobalKey> createState() =>
      _VisualEffectSubviewContainerWithGlobalKeyState();
}

class _VisualEffectSubviewContainerWithGlobalKeyState
    extends State<VisualEffectSubviewContainerWithGlobalKey> {
  int? _visualEffectSubviewId;
  var _propertyStorage = VisualEffectSubviewContainerPropertyStorage();
  bool _isAddingVisualEffectSubview = false;
  bool _isDisposed = false;
  int _nativeSubviewGeneration = 0;
  Timer? _updateTimer;
  late final VoidCallback _forceUpdateCallback;

  VisualEffectSubviewProperties _getVisualEffectSubviewProperties(
    _VisualEffectSubviewGeometry geometry,
  ) {
    return VisualEffectSubviewProperties(
      frameX: geometry.x,
      frameY: geometry.y,
      frameWidth: geometry.width,
      frameHeight: geometry.height,
      alphaValue: widget.alphaValue,
      cornerRadius: widget.cornerRadius,
      cornerMask: widget.cornerMask,
      material: widget.material,
      state: widget.state,
    );
  }

  /// Creates a new visual effect subview and adds it to the application window.
  Future<void> _addVisualEffectSubviewToApplicationWindow(
    _VisualEffectSubviewGeometry geometry,
  ) async {
    if (_isDisposed ||
        _isAddingVisualEffectSubview ||
        _visualEffectSubviewId != null) {
      return;
    }

    _isAddingVisualEffectSubview = true;
    final generation = _nativeSubviewGeneration;
    var shouldReschedule = false;

    try {
      final properties = _getVisualEffectSubviewProperties(geometry);
      final visualEffectSubviewId =
          await WindowManipulator.addVisualEffectSubview(properties);

      if (_isDisposed || generation != _nativeSubviewGeneration) {
        await WindowManipulator.removeVisualEffectSubview(
          visualEffectSubviewId,
        );
        shouldReschedule = !_isDisposed;
        return;
      }

      _visualEffectSubviewId = visualEffectSubviewId;
      _propertyStorage.updateProperties(properties);
      shouldReschedule = true;
    } catch (error, stackTrace) {
      _reportNativeViewError(error, stackTrace);
    } finally {
      _isAddingVisualEffectSubview = false;
      if (shouldReschedule && !_isDisposed && mounted) {
        _scheduleVisualEffectSubviewUpdate();
      }
    }
  }

  /// Initializes a resize event relay, if one is provided.
  void _initializeResizeEventRelay() {
    widget.resizeEventRelay?.registerForceUpdateFunction(_forceUpdateCallback);
  }

  @override
  void initState() {
    super.initState();
    _forceUpdateCallback = _scheduleVisualEffectSubviewUpdate;
    _initializeResizeEventRelay();
    _scheduleVisualEffectSubviewUpdate();
  }

  @override
  void didUpdateWidget(
    covariant VisualEffectSubviewContainerWithGlobalKey oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.resizeEventRelay != widget.resizeEventRelay) {
      oldWidget.resizeEventRelay
          ?.unregisterForceUpdateFunction(_forceUpdateCallback);
      _initializeResizeEventRelay();
    }

    _scheduleVisualEffectSubviewUpdate();
  }

  /// Removes the previously added visual effect subview from the application
  /// window.
  void _removeVisualEffectSubviewFromApplicationWindow() {
    if (_visualEffectSubviewId == null && !_isAddingVisualEffectSubview) {
      return;
    }

    _nativeSubviewGeneration++;
    final visualEffectSubviewId = _visualEffectSubviewId;
    _visualEffectSubviewId = null;
    _propertyStorage = VisualEffectSubviewContainerPropertyStorage();

    if (visualEffectSubviewId != null) {
      unawaited(_removeVisualEffectSubview(visualEffectSubviewId));
    }
  }

  Future<void> _removeVisualEffectSubview(int visualEffectSubviewId) async {
    try {
      await WindowManipulator.removeVisualEffectSubview(
        visualEffectSubviewId,
      );
    } catch (error, stackTrace) {
      _reportNativeViewError(error, stackTrace);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _updateTimer?.cancel();
    widget.resizeEventRelay
        ?.unregisterForceUpdateFunction(_forceUpdateCallback);
    _removeVisualEffectSubviewFromApplicationWindow();
    super.dispose();
  }

  /// Modifies the visual effect subview.
  ///
  /// This method takes the current position and size of the visual effect
  /// subview and compares the values of all of the subview's properties to
  /// their previous values. If any differences are identified, the visual
  /// effect subview will be updated on the Swift side.
  void _modifyVisualEffectSubview(_VisualEffectSubviewGeometry geometry) {
    final visualEffectSubviewId = _visualEffectSubviewId;
    if (visualEffectSubviewId == null) {
      return;
    }

    final newProperties = _getVisualEffectSubviewProperties(geometry);

    final delta = _propertyStorage.getDeltaProperties(newProperties);
    if (!delta.isEmpty) {
      unawaited(_updateVisualEffectSubviewProperties(
        visualEffectSubviewId,
        delta,
      ));
      _propertyStorage.updateProperties(newProperties);
    }
  }

  Future<void> _updateVisualEffectSubviewProperties(
    int visualEffectSubviewId,
    VisualEffectSubviewProperties properties,
  ) async {
    try {
      await WindowManipulator.updateVisualEffectSubviewProperties(
        visualEffectSubviewId,
        properties,
      );
    } catch (error, stackTrace) {
      _reportNativeViewError(error, stackTrace);
    }
  }

  /// Determines the position and size of this widget relative to the
  /// application window and modifies the visual effect subview accordingly.
  void _updateVisualEffectSubview() {
    if (_isDisposed || !mounted) {
      return;
    }

    final geometry = _getVisualEffectSubviewGeometry();
    if (geometry == null) {
      _removeVisualEffectSubviewFromApplicationWindow();
      return;
    }

    if (_visualEffectSubviewId == null) {
      unawaited(_addVisualEffectSubviewToApplicationWindow(geometry));
      return;
    }

    _modifyVisualEffectSubview(geometry);
  }

  _VisualEffectSubviewGeometry? _getVisualEffectSubviewGeometry() {
    final widgetContext = (widget.key as GlobalKey?)?.currentContext;
    if (widgetContext?.mounted != true) {
      return null;
    }

    final renderObject = widgetContext?.findRenderObject() as RenderBox?;
    if (renderObject == null ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }

    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) {
      return null;
    }

    final position = renderObject.localToGlobal(Offset.zero);
    final x = position.dx + widget.padding.left;
    final y = mediaQuery.size.height -
        renderObject.size.height -
        position.dy +
        widget.padding.bottom;
    final width =
        renderObject.size.width - widget.padding.left - widget.padding.right;
    final height =
        renderObject.size.height - widget.padding.bottom - widget.padding.top;

    if (!isValidNativeViewGeometry(
      x: x,
      y: y,
      width: width,
      height: height,
    )) {
      return null;
    }

    return _VisualEffectSubviewGeometry(
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  void _scheduleVisualEffectSubviewUpdate() {
    if (_isDisposed) {
      return;
    }

    _updateTimer?.cancel();
    _updateTimer = Timer(const Duration(), _updateVisualEffectSubview);
  }

  void _reportNativeViewError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'macos_window_utils',
        context: ErrorDescription('while updating a visual effect subview'),
      ),
    );
  }

  /// Update the visual effect subview only if no resize event relay has been
  /// provided that forbids automatically updating it inside the build method.
  void _updateVisualEffectSubviewFromBuildMethodIfPermitted() {
    if (widget.resizeEventRelay != null) {
      if (widget.resizeEventRelay!.disableUpdateOnBuild) {
        return;
      }
    }

    // Render geometry is only stable after the current build has completed.
    _scheduleVisualEffectSubviewUpdate();
  }

  @override
  Widget build(BuildContext context) {
    _updateVisualEffectSubviewFromBuildMethodIfPermitted();

    return widget.child;
  }
}

class _VisualEffectSubviewGeometry {
  const _VisualEffectSubviewGeometry({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}
