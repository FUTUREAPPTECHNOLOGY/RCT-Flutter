import 'package:animate_do/animate_do.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rct/constants/linkapi.dart';
import 'package:rct/view/home_screen.dart';
import 'package:rct/view/onboarding/onboarding_screen_1.dart';
import 'package:rct/view/ownership/renters_cubit.dart';
import 'package:rct/view/share_rct/cubit.dart';

class SplashScreen extends StatefulWidget {
  static String id = 'SplashScreen';

  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool hasCompletedOnboarding = false;
  final Color splashBackgroundColor = const Color(0xFF20262F);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ShareCubit>().fetchShare('$linkServerName/api/opportunities');
        context
            .read<RentersCubit>()
            .fetchUnAuthData('$linkServerName/api/renters');
        FirebaseMessaging.instance.requestPermission();
      }
    });

    reDirect();
  }

  Future<void> reDirect() async {
    await checkOnboardingStatus();
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    if (kDebugMode) {
      print('Onboarding status: $hasCompletedOnboarding');
    }

    if (hasCompletedOnboarding) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => OnboardingScreen()),
      );
    }
  }

  Future<void> checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        hasCompletedOnboarding =
            prefs.getBool('hasCompletedOnboarding') ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: splashBackgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: splashBackgroundColor),
          Align(
            alignment: Alignment.bottomCenter,
            child: FadeInUp(
              duration: const Duration(milliseconds: 1200),
              from: 80,
              child: SizedBox(
                height: size.height * 0.4,
                width: size.width,
                child: Image.asset(
                  'assets/images/splash_background.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Positioned(
            top: size.height * 0.3,
            left: 0,
            right: 0,
            child: Center(
              child: FadeInDown(
                duration: const Duration(milliseconds: 1800),
                from: 400,
                child: Image.asset(
                  'assets/images/splashLogo.png',
                  width: size.width * 0.5,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
