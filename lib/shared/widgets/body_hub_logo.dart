import 'package:flutter/material.dart';

class BodyHubLogo extends StatelessWidget {
  final double width;
  final double? height;
  final BoxFit fit;

  const BodyHubLogo({
    super.key,
    this.width = 160,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/body_hub_logo.png',
      width: width,
      height: height,
      fit: fit,
    );
  }
}