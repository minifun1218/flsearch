import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/app_state.dart';
import '../../data/recognition_service.dart';
import '../../domain/models/food.dart';
import '../review/review_page.dart';
import 'consent_sheet.dart';

/// 拍照识别。
///
/// 取景框是真实的相机预览（camera 插件），快门拍下的文件路径直接交给
/// [FoodRecognizer]；相机打不开时（没授权、没摄像头、桌面端没有实现）
/// 页面不会卡死在黑屏上 —— 退回占位取景框，并给出重试、相册、手动三条出路。
class CapturePage extends ConsumerStatefulWidget {
  const CapturePage({super.key, required this.date, required this.meal});

  final DateTime date;
  final MealType meal;

  @override
  ConsumerState<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends ConsumerState<CapturePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late MealType _meal = widget.meal;
  bool _analyzing = false;
  String? _error;
  List<RecognizedItem> _found = const [];

  /// 相机。null 表示还没开起来 —— 配合 [_opening] / [_cameraError] 决定显示什么。
  CameraController? _camera;
  bool _opening = false;
  String? _cameraError;
  bool _torch = false;

  /// 正在识别的那张照片，识别期间显示在取景框里。
  String? _shotPath;

  /// 识别轮次。取消或重拍都会让上一轮的返回结果作废。
  int _analysis = 0;

  final _picker = ImagePicker();

  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scan.dispose();
    _camera?.dispose();
    super.dispose();
  }

  /// 相机是独占的系统资源：退到后台必须交还，回前台再重新拿。
  /// 少了这一步，切出去再切回来就是一块黑屏 —— 也就是「相机打不开」。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_camera == null && !_opening && ref.read(photoConsentProvider)) {
        _openCamera();
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final camera = _camera;
      if (camera == null) return;
      _camera = null;
      _torch = false;
      camera.dispose();
      if (mounted) setState(() {});
    }
  }

  Future<void> _start() async {
    if (!await _ensureConsent()) return;
    await _openCamera();
  }

  /// 首次使用拍照识别前必须明确告知并取得同意（PRD R-048）。
  Future<bool> _ensureConsent() async {
    if (ref.read(photoConsentProvider)) return true;
    final accepted = await showPhotoConsentSheet(context);
    if (!mounted) return false;
    if (accepted == true) {
      ref.read(photoConsentProvider.notifier).accept();
      return true;
    }
    // 兑现「不同意，改用手动记录」那颗按钮的承诺。
    Navigator.of(context).pop('manual');
    return false;
  }

  Future<void> _openCamera() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _cameraError = null;
    });

    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('noCamera', '没有可用的摄像头');
      }
      final lens = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        lens,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _opening = false;
        _torch = false;
      });
    } catch (error) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _camera = null;
        _opening = false;
        _cameraError = _cameraMessage(error);
      });
    }
  }

  String _cameraMessage(Object error) {
    if (error is CameraException) {
      return switch (error.code) {
        'noCamera' => '这台设备上没有找到摄像头，可以改用相册或手动记录。',
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' ||
        'cameraPermission' => '相机权限被拒绝。到系统设置里允许 FitMeal 使用相机，再回来重试。',
        _ => '相机打不开：${error.description ?? error.code}',
      };
    }
    if (error is MissingPluginException) {
      return '当前平台没有相机实现（桌面 / Web 调试时常见），可以改用相册或手动记录。';
    }
    return '相机打不开：$error';
  }

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    final next = !_torch;
    try {
      await camera.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torch = next);
    } on CameraException {
      // 没有闪光灯的设备直接忽略，不值得为此弹一条错误。
    }
  }

  /// 快门。相机没开起来时，这颗按钮的语义是「再试一次」。
  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      await _openCamera();
      return;
    }
    if (camera.value.isTakingPicture) return;

    try {
      final shot = await camera.takePicture();
      if (!mounted) return;
      await _analyze(shot.path);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = _cameraMessage(e));
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
      await _analyze(picked.path);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '打不开相册：$error');
    }
  }

  Future<void> _analyze(String imagePath) async {
    if (_torch) unawaited(_toggleTorch());
    final round = ++_analysis;
    setState(() {
      _analyzing = true;
      _error = null;
      _found = const [];
      _shotPath = imagePath;
    });

    try {
      final items = await ref
          .read(recognizerProvider)
          .recognize(imagePath: imagePath);
      // 用户中途取消或重拍了，这一轮的结果就不该再往下走。
      if (!mounted || round != _analysis) return;

      if (items.isEmpty) {
        setState(() {
          _analyzing = false;
          _shotPath = null;
          _error = '没认出食物，换个角度重拍，或者直接手动录入。';
        });
        return;
      }

      setState(() => _found = items);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted || round != _analysis) return;

      final saved = await Navigator.of(context).pushReplacement<bool, void>(
        MaterialPageRoute(
          builder: (_) =>
              ReviewPage(items: items, meal: _meal, date: widget.date),
        ),
      );
      if (saved == false && mounted) Navigator.of(context).pop(false);
    } on RecognitionFailure catch (e) {
      if (!mounted || round != _analysis) return;
      setState(() {
        _analyzing = false;
        _shotPath = null;
        _error = e.message;
      });
    }
  }

  void _cancelAnalyzing() {
    _analysis++;
    setState(() {
      _analyzing = false;
      _shotPath = null;
      _found = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = _camera?.value.isInitialized ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF191713),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              analyzing: _analyzing,
              torchOn: _torch,
              canTorch: ready,
              onToggleTorch: _toggleTorch,
              onClose: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: _Viewfinder(
                analyzing: _analyzing,
                scan: _scan,
                camera: _camera,
                opening: _opening,
                cameraError: _cameraError,
                shotPath: _shotPath,
                onRetry: _openCamera,
              ),
            ),
            const SizedBox(height: 26),
            Expanded(
              child: _analyzing
                  ? _AnalyzingBody(found: _found)
                  : _ReadyBody(
                      meal: _meal,
                      error: _error,
                      cameraReady: ready,
                      onPickMeal: (m) => setState(() => _meal = m),
                    ),
            ),
            if (_analyzing)
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
                child: _GhostButton(label: '取消', onTap: _cancelAnalyzing),
              )
            else
              _ShutterBar(
                ready: ready,
                onShoot: _shoot,
                onGallery: _pickFromGallery,
                onManual: () => Navigator.of(context).pop('manual'),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.analyzing,
    required this.torchOn,
    required this.canTorch,
    required this.onToggleTorch,
    required this.onClose,
  });

  final bool analyzing;
  final bool torchOn;
  final bool canTorch;
  final VoidCallback onToggleTorch;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _RoundButton(icon: Icons.close, onTap: onClose),
          Text(
            analyzing ? '正在识别' : '拍照记录',
            style: AppFonts.text(
              size: 14,
              weight: FontWeight.w500,
              color: const Color(0xFFF5F2EC).withValues(alpha: 0.85),
            ),
          ),
          analyzing || !canTorch
              ? const SizedBox(width: 40)
              : _RoundButton(
                  icon: torchOn ? Icons.bolt : Icons.bolt_outlined,
                  active: torchOn,
                  onTap: onToggleTorch,
                ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFF5F2EC);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? cream : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Icon(
          icon,
          size: 18,
          color: active ? const Color(0xFF191713) : cream,
        ),
      ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.analyzing,
    required this.scan,
    required this.camera,
    required this.opening,
    required this.cameraError,
    required this.shotPath,
    required this.onRetry,
  });

  final bool analyzing;
  final Animation<double> scan;
  final CameraController? camera;
  final bool opening;
  final String? cameraError;
  final String? shotPath;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 330 / 330,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xFF24211C),
                child: Opacity(
                  opacity: analyzing ? 0.55 : 1,
                  child: _surface(),
                ),
              ),
            ),
            if (!analyzing && cameraError != null)
              Positioned.fill(
                child: _CameraFallback(message: cameraError!, onRetry: onRetry),
              ),
            if (!analyzing && cameraError == null && opening)
              const Positioned.fill(child: _CameraOpening()),
            if (!analyzing)
              for (final corner in const [
                Alignment.topLeft,
                Alignment.topRight,
                Alignment.bottomLeft,
                Alignment.bottomRight,
              ])
                Align(
                  alignment: corner,
                  child: CustomPaint(
                    size: const Size(30, 30),
                    painter: _CornerPainter(corner),
                  ),
                ),
            if (analyzing)
              AnimatedBuilder(
                animation: scan,
                builder: (context, _) {
                  return LayoutBuilder(
                    builder: (context, box) {
                      final y = box.maxHeight * scan.value;
                      return Stack(
                        children: [
                          Positioned(
                            top: y,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 2,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0x007AA080),
                                    Color(0xFF7AA080),
                                    Color(0x007AA080),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: y,
                            left: 0,
                            right: 0,
                            height: 74,
                            child: Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x297AA080),
                                    Color(0x007AA080),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 取景框里放什么：识别中放刚拍的那张，其次放实时预览，都没有就退回占位图形。
  Widget _surface() {
    final path = shotPath;
    if (analyzing && path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => CustomPaint(painter: _PlatePainter()),
      );
    }

    final controller = camera;
    if (controller != null && controller.value.isInitialized) {
      final preview = controller.value.previewSize;
      if (preview == null) return CameraPreview(controller);
      // previewSize 用的是传感器方向（横向），竖屏要换轴再按 cover 铺满。
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: preview.height,
          height: preview.width,
          child: CameraPreview(controller),
        ),
      );
    }

    return CustomPaint(painter: _PlatePainter());
  }
}

class _CameraOpening extends StatelessWidget {
  const _CameraOpening();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: const Color(0xFFF5F2EC).withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '正在打开相机…',
            style: AppFonts.text(
              size: 12,
              color: const Color(0xFFF5F2EC).withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraFallback extends StatelessWidget {
  const _CameraFallback({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFF5F2EC);
    return Container(
      color: const Color(0xFF24211C).withValues(alpha: 0.82),
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.no_photography_outlined,
            size: 26,
            color: cream.withValues(alpha: 0.75),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppFonts.text(
              size: 12.5,
              height: 1.7,
              color: cream.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: onRetry,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                border: Border.all(color: cream.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh, size: 15, color: cream),
                  const SizedBox(width: 7),
                  Text(
                    '重试',
                    style: AppFonts.text(
                      size: 13,
                      weight: FontWeight.w500,
                      color: cream,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide * 0.38;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFF5F2EC).withValues(alpha: 0.20);

    canvas.drawCircle(center, r, paint);
    canvas.drawCircle(center, r * 0.82, paint);

    final food = Path()
      ..addOval(
        Rect.fromCenter(
          center: center.translate(-r * 0.12, -r * 0.1),
          width: r * 0.52,
          height: r * 0.46,
        ),
      );
    canvas.drawPath(food, paint);

    canvas.drawPath(
      Path()
        ..moveTo(center.dx + r * 0.18, center.dy + r * 0.2)
        ..quadraticBezierTo(
          center.dx + r * 0.42,
          center.dy + r * 0.08,
          center.dx + r * 0.52,
          center.dy + r * 0.18,
        ),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - r * 0.38, center.dy + r * 0.3)
        ..quadraticBezierTo(
          center.dx - r * 0.16,
          center.dy + r * 0.2,
          center.dx - r * 0.02,
          center.dy + r * 0.34,
        ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => false;
}

class _CornerPainter extends CustomPainter {
  _CornerPainter(this.corner);

  final Alignment corner;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF5F2EC);

    final path = Path();
    if (corner == Alignment.topLeft) {
      path
        ..moveTo(0, size.height)
        ..lineTo(0, 0)
        ..lineTo(size.width, 0);
    } else if (corner == Alignment.topRight) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height);
    } else if (corner == Alignment.bottomLeft) {
      path
        ..moveTo(0, 0)
        ..lineTo(0, size.height)
        ..lineTo(size.width, size.height);
    } else {
      path
        ..moveTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => false;
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({
    required this.meal,
    required this.error,
    required this.cameraReady,
    required this.onPickMeal,
  });

  final MealType meal;
  final String? error;
  final bool cameraReady;
  final ValueChanged<MealType> onPickMeal;

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFF5F2EC);

    return SingleChildScrollView(
      child: Column(
        children: [
          if (error != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 30),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 17,
                    color: Color(0xFFE8B4AF),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      error!,
                      style: AppFonts.text(
                        size: 12,
                        color: const Color(0xFFE8B4AF),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                Text(
                  cameraReady ? '将整餐放进取景框' : '相机没开起来也能记',
                  style: AppFonts.text(
                    size: 14,
                    color: cream.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cameraReady
                      ? '俯拍、光线充足时识别更准；餐具可作为份量参照'
                      : '从相册选一张照片识别，或者直接手动录入',
                  textAlign: TextAlign.center,
                  style: AppFonts.text(
                    size: 12,
                    color: cream.withValues(alpha: 0.45),
                    height: 1.6,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 26),
          Wrap(
            spacing: 8,
            children: [
              for (final m in MealType.values)
                GestureDetector(
                  onTap: () => onPickMeal(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: m == meal
                          ? cream
                          : Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      m.label,
                      style: AppFonts.text(
                        size: 13,
                        weight: m == meal ? FontWeight.w500 : FontWeight.w400,
                        color: m == meal
                            ? const Color(0xFF191713)
                            : cream.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalyzingBody extends StatelessWidget {
  const _AnalyzingBody({required this.found});

  final List<RecognizedItem> found;

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFF5F2EC);

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 4),
          Text(
            '正在分析这一餐…',
            style: AppFonts.text(
              size: AppText.body,
              weight: FontWeight.w500,
              color: cream.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 7),
          NumText(
            '通常需要 5–8 秒',
            size: 12,
            weight: FontWeight.w400,
            color: cream.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                for (final item in found) ...[
                  _FoundRow(item: item),
                  const SizedBox(height: 9),
                ],
                if (found.isEmpty) const _PendingRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FoundRow extends StatelessWidget {
  const _FoundRow({required this.item});

  final RecognizedItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          const Icon(Icons.check, size: 15, color: Color(0xFF7AA080)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              item.food.name,
              style: AppFonts.text(size: 14, color: const Color(0xFFF5F2EC)),
            ),
          ),
          NumText(
            '约 ${item.estimatedGrams} g',
            size: 12,
            weight: FontWeight.w400,
            color: const Color(0xFFF5F2EC).withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: const Color(0xFFF5F2EC).withValues(alpha: 0.6),
              backgroundColor: const Color(0xFFF5F2EC).withValues(alpha: 0.18),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 96,
            height: 9,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F2EC).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShutterBar extends StatelessWidget {
  const _ShutterBar({
    required this.ready,
    required this.onShoot,
    required this.onGallery,
    required this.onManual,
  });

  final bool ready;
  final VoidCallback onShoot;
  final VoidCallback onGallery;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 0, 36, 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SideButton(
            icon: Icons.photo_library_outlined,
            label: '相册',
            onTap: onGallery,
          ),
          Semantics(
            button: true,
            label: ready ? '拍照识别' : '重新打开相机',
            child: GestureDetector(
              onTap: onShoot,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(
                      0xFFF5F2EC,
                    ).withValues(alpha: ready ? 0.9 : 0.4),
                    width: 3,
                  ),
                ),
                child: Center(
                  child: ready
                      ? Container(
                          width: 60,
                          height: 60,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF5F2EC),
                            shape: BoxShape.circle,
                          ),
                        )
                      : Icon(
                          Icons.refresh,
                          size: 26,
                          color: const Color(
                            0xFFF5F2EC,
                          ).withValues(alpha: 0.55),
                        ),
                ),
              ),
            ),
          ),
          _SideButton(icon: Icons.edit_outlined, label: '手动', onTap: onManual),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({required this.icon, required this.onTap, this.label});

  final IconData icon;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF2E2A24),
          border: Border.all(
            color: const Color(0xFFF5F2EC).withValues(alpha: 0.16),
          ),
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: const Color(0xFFF5F2EC)),
            if (label != null) ...[
              const SizedBox(height: 2),
              Text(
                label!,
                style: AppFonts.text(
                  size: 8,
                  color: const Color(0xFFF5F2EC).withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFFF5F2EC).withValues(alpha: 0.18),
          ),
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        child: Text(
          label,
          style: AppFonts.text(
            size: 14,
            color: const Color(0xFFF5F2EC).withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
