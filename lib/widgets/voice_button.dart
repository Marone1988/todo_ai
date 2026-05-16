import 'package:flutter/material.dart';

class VoiceButton extends StatelessWidget {
  final bool isListening;
  final bool isProcessing;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;

  const VoiceButton({
    super.key,
    required this.isListening,
    required this.isProcessing,
    required this.onTapDown,
    required this.onTapUp,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: onTapUp,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: isListening ? 90 : 72,
        height: isListening ? 90 : 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isProcessing
              ? const Color(0xFF2A2A3E)
              : isListening
                  ? const Color(0xFF6C63FF)
                  : const Color(0xFF6C63FF).withOpacity(0.9),
          boxShadow: isListening
              ? [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.5),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ]
              : [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.2),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
        ),
        child: isProcessing
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  color: Color(0xFF6C63FF),
                  strokeWidth: 2,
                ),
              )
            : Icon(
                isListening ? Icons.mic : Icons.mic_none,
                color: Colors.white,
                size: 32,
              ),
      ),
    );
  }
}
