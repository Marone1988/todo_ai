import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'paywall_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameCtrl = TextEditingController();
  String? _avatarPath;
  bool _nameValid = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() {
      final valid = _nameCtrl.text.trim().isNotEmpty;
      if (valid != _nameValid) setState(() => _nameValid = valid);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    haptic();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 400,
      maxHeight: 400,
    );
    if (picked != null && mounted) {
      setState(() => _avatarPath = picked.path);
    }
  }

  Future<void> _complete() async {
    if (!_nameValid) return;
    haptic();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameCtrl.text.trim());
    if (_avatarPath != null) await prefs.setString('user_avatar', _avatarPath!);
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    // Après l'onboarding → Paywall (premier accès)
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const PaywallScreen(fromOnboarding: true),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Logo + title
              const Icon(Icons.mic_rounded, color: Colors.white, size: 40),
              const SizedBox(height: 16),
              Text(t('onb_title'),
                style: const TextStyle(
                  fontSize: 32, fontWeight: FontWeight.w800,
                  color: Colors.white, letterSpacing: -0.5,
                )),
              const SizedBox(height: 8),
              const Text('Vocal Todo',
                style: TextStyle(
                  fontSize: 14, color: Color(0xFF636366),
                  fontWeight: FontWeight.w500,
                )),

              const Spacer(flex: 2),

              // Avatar picker
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(children: [
                  Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1C1C1E),
                      image: _avatarPath != null
                          ? DecorationImage(
                              image: FileImage(File(_avatarPath!)),
                              fit: BoxFit.cover)
                          : null,
                    ),
                    child: _avatarPath == null
                        ? const Center(child: Icon(
                            Icons.add_a_photo_outlined,
                            color: Color(0xFF636366), size: 32))
                        : null,
                  ),
                  Positioned(
                    bottom: 4, right: 4,
                    child: Container(
                      width: 28, height: 28,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.edit, size: 14, color: Colors.black),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Text(t('onb_photo'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF636366))),

              const Spacer(flex: 2),

              // Name field
              Align(
                alignment: Alignment.centerLeft,
                child: Text(t('onb_name_label'),
                  style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                autofocus: false,
                style: const TextStyle(fontSize: 16, color: Colors.white),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: t('onb_name_hint'),
                  hintStyle: const TextStyle(color: Color(0xFF636366)),
                  filled: true,
                  fillColor: const Color(0xFF1C1C1E),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white, width: 1.5)),
                ),
                onSubmitted: (_) => _complete(),
              ),

              const Spacer(flex: 2),

              // Start button
              GestureDetector(
                onTap: _nameValid ? _complete : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: _nameValid ? Colors.white : const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(child: Text(t('onb_start'),
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: _nameValid ? Colors.black : const Color(0xFF48484A),
                    ))),
                ),
              ),

              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
