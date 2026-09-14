import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

enum _PasswordTransition { steady, visibility, append, removal, replacement }

/// Displays password edits without moving characters that did not change.
class AnimatedPasswordText extends StatefulWidget {
  const AnimatedPasswordText({
    required this.password,
    this.obscured = false,
    this.style,
    this.cellWidth,
    this.followEnd = false,
    this.backgroundColor = Colors.white,
    super.key,
  });

  final String password;
  final bool obscured;
  final TextStyle? style;
  final double? cellWidth;
  final bool followEnd;
  final Color backgroundColor;

  @override
  State<AnimatedPasswordText> createState() => _AnimatedPasswordTextState();
}

class _AnimatedPasswordTextState extends State<AnimatedPasswordText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late final ScrollController _scrollController;
  late List<String> _fromCharacters;
  late List<String> _toCharacters;
  late bool _fromObscured;
  late bool _toObscured;
  _PasswordTransition _transition = _PasswordTransition.steady;
  List<int> _newToOld = const [];

  TextStyle get _textStyle =>
      widget.style ??
      const TextStyle(
        fontFamily: 'Kumbh Sans',
        fontSize: 21,
        height: 1,
        fontWeight: FontWeight.w500,
        color: Color(0xFF152A96),
      );

  double get _cellWidth =>
      widget.cellWidth ?? ((_textStyle.fontSize ?? 21) * 0.9);

  @override
  void initState() {
    super.initState();
    _toCharacters = widget.password.characters.toList();
    _fromCharacters = List.of(_toCharacters);
    _fromObscured = widget.obscured;
    _toObscured = widget.obscured;
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      value: 1,
    );
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant AnimatedPasswordText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.password == widget.password &&
        oldWidget.obscured == widget.obscured) {
      return;
    }

    _fromCharacters = oldWidget.password.characters.toList();
    _toCharacters = widget.password.characters.toList();
    _fromObscured = oldWidget.obscured;
    _toObscured = widget.obscured;
    _newToOld = const [];

    if (oldWidget.password == widget.password) {
      _transition = _PasswordTransition.visibility;
      final steps = _toCharacters.length.clamp(1, 24);
      _animation.duration = Duration(milliseconds: 80 + ((steps - 1) * 12));
    } else if (widget.password.startsWith(oldWidget.password) &&
        _toCharacters.length > _fromCharacters.length) {
      _transition = _PasswordTransition.append;
      _animation.duration = const Duration(milliseconds: 130);
    } else {
      final mapping = _subsequenceMapping(_fromCharacters, _toCharacters);
      if (mapping != null && _toCharacters.length < _fromCharacters.length) {
        _transition = _PasswordTransition.removal;
        _newToOld = mapping;
        _animation.duration = const Duration(milliseconds: 300);
      } else {
        _transition = _PasswordTransition.replacement;
        _animation.duration = const Duration(milliseconds: 90);
      }
    }
    _animation.forward(from: 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (widget.followEnd) {
        _scrollController.jumpTo(max);
      } else if (_scrollController.offset > max) {
        _scrollController.jumpTo(max);
      }
    });
  }

  List<int>? _subsequenceMapping(List<String> oldValue, List<String> newValue) {
    final mapping = <int>[];
    var oldIndex = 0;
    for (final character in newValue) {
      while (oldIndex < oldValue.length && oldValue[oldIndex] != character) {
        oldIndex++;
      }
      if (oldIndex == oldValue.length) return null;
      mapping.add(oldIndex++);
    }
    return mapping;
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _animation.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  String _shownCharacter(String character, bool obscured) =>
      obscured ? '*' : character;

  Widget _glyph(String text, {double opacity = 1, double scale = 1}) {
    return ClipRect(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          child: Center(child: Text(text, maxLines: 1, style: _textStyle)),
        ),
      ),
    );
  }

  Widget _at(double left, Widget child) {
    return Positioned(left: left, width: _cellWidth, height: 32, child: child);
  }

  Widget _buildSteady() {
    return _stack(_toCharacters.length * _cellWidth, [
      for (var index = 0; index < _toCharacters.length; index++)
        _at(
          index * _cellWidth,
          _glyph(_shownCharacter(_toCharacters[index], _toObscured)),
        ),
    ]);
  }

  Widget _buildVisibility(double progress) {
    final durationMs = _animation.duration?.inMilliseconds ?? 80;
    return _stack(_toCharacters.length * _cellWidth, [
      for (var index = 0; index < _toCharacters.length; index++)
        _at(index * _cellWidth, _visibilityGlyph(index, progress, durationMs)),
    ]);
  }

  Widget _visibilityGlyph(int index, double progress, int durationMs) {
    final startMs = (index.clamp(0, 23) * 12).toDouble();
    final local = ((progress * durationMs - startMs) / 80).clamp(0.0, 1.0);
    final from = _shownCharacter(_fromCharacters[index], _fromObscured);
    final to = _shownCharacter(_toCharacters[index], _toObscured);
    if (local < 0.5) return _glyph(from, opacity: 1 - local * 2);
    return _glyph(to, opacity: (local - 0.5) * 2);
  }

  Widget _buildAppend(double progress) {
    final reveal = Curves.easeOutCubic.transform(progress);
    return _stack(_toCharacters.length * _cellWidth, [
      for (var index = 0; index < _toCharacters.length; index++)
        _at(
          index * _cellWidth,
          _glyph(
            _shownCharacter(_toCharacters[index], _toObscured),
            opacity: index < _fromCharacters.length ? 1 : reveal,
            scale: index < _fromCharacters.length ? 1 : 0.55 + 0.45 * reveal,
          ),
        ),
    ]);
  }

  Widget _buildRemoval(double progress) {
    final disappear = Curves.easeInCubic.transform(
      (progress / 0.42).clamp(0.0, 1.0),
    );
    final movement = Curves.easeOutCubic.transform(
      ((progress - 0.42) / 0.58).clamp(0.0, 1.0),
    );
    final oldToNew = <int, int>{
      for (var newIndex = 0; newIndex < _newToOld.length; newIndex++)
        _newToOld[newIndex]: newIndex,
    };
    final width =
        lerpDouble(
          _fromCharacters.length * _cellWidth,
          _toCharacters.length * _cellWidth,
          movement,
        ) ??
        0;

    return _stack(width, [
      for (var oldIndex = 0; oldIndex < _fromCharacters.length; oldIndex++)
        if (oldToNew.containsKey(oldIndex))
          _at(
            lerpDouble(
                  oldIndex * _cellWidth,
                  oldToNew[oldIndex]! * _cellWidth,
                  movement,
                ) ??
                0,
            _glyph(_shownCharacter(_fromCharacters[oldIndex], _fromObscured)),
          )
        else
          _at(
            oldIndex * _cellWidth,
            _glyph(
              _shownCharacter(_fromCharacters[oldIndex], _fromObscured),
              opacity: 1 - disappear,
              scale: 1 - disappear,
            ),
          ),
    ]);
  }

  Widget _buildReplacement(double progress) {
    return _stack(_toCharacters.length * _cellWidth, [
      for (var index = 0; index < _toCharacters.length; index++)
        _at(
          index * _cellWidth,
          progress < 0.5 && index < _fromCharacters.length
              ? _glyph(
                  _shownCharacter(_fromCharacters[index], _fromObscured),
                  opacity: 1 - progress * 2,
                )
              : _glyph(
                  _shownCharacter(_toCharacters[index], _toObscured),
                  opacity: progress < 0.5 ? 0 : (progress - 0.5) * 2,
                ),
        ),
    ]);
  }

  Widget _stack(double width, List<Widget> children) {
    return SizedBox(
      width: width,
      height: 32,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }

  Widget _animatedContent(double progress) {
    switch (_transition) {
      case _PasswordTransition.steady:
        return _buildSteady();
      case _PasswordTransition.visibility:
        return _buildVisibility(progress);
      case _PasswordTransition.append:
        return _buildAppend(progress);
      case _PasswordTransition.removal:
        return _buildRemoval(progress);
      case _PasswordTransition.replacement:
        return _buildReplacement(progress);
    }
  }

  int _hiddenCharacters(double viewportWidth) {
    final totalWidth = _toCharacters.length * _cellWidth;
    final visibleEnd = _scrollController.hasClients
        ? _scrollController.offset + viewportWidth
        : viewportWidth;
    final remaining = totalWidth - visibleEnd;
    if (remaining <= 0) return 0;
    return (remaining / _cellWidth).ceil();
  }

  @override
  Widget build(BuildContext context) {
    if (_toCharacters.isEmpty && _fromCharacters.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _toCharacters.length * _cellWidth;
        final hidden = _hiddenCharacters(viewportWidth);
        return SizedBox(
          height: 32,
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) =>
                        _animatedContent(_animation.value),
                  ),
                ),
              ),
              if (hidden > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 68,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            widget.backgroundColor.withValues(alpha: 0),
                            widget.backgroundColor,
                            widget.backgroundColor,
                          ],
                          stops: const [0, 0.48, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              if (hidden > 0)
                Positioned(
                  right: 0,
                  top: 1,
                  child: IgnorePointer(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 32),
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F3FA),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFD9E0EE)),
                      ),
                      child: Text(
                        '+$hidden',
                        style: const TextStyle(
                          fontFamily: 'Kumbh Sans',
                          fontSize: 10,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF52627F),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
