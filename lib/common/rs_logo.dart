import 'package:flutter/material.dart';

/// The desktop's RetroShare logo: the symbol above the RETROSHARE wordmark
/// and its tagline, as in the desktop's about box and start window. The
/// wordmark is Lato with RETRO in blue; SHARE and the tagline are black on a
/// light theme and light grey on a dark one, as the desktop's two logo
/// pictures (logo_web_nobackground.png and its _black variant).
///
/// It scales to the room it is given. Its text sets no underline, as it
/// flies between screens (Hero) outside any Material.
class RsLogo extends StatelessWidget {
  const RsLogo({super.key, this.tagline = true});

  /// Whether to show "secure communication for everyone".
  final bool tagline;

  static const _retroBlue = Color(0xFF5EB9E5);
  static const _shareOnDark = Color(0xFFC4CFD6);

  // The layout is drawn at this width, then scaled.
  static const double _width = 300;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final share = dark ? _shareOnDark : Colors.black;

    Widget fullWidth(Widget text) => SizedBox(
          width: _width,
          child: FittedBox(fit: BoxFit.fitWidth, child: text),
        );

    return FittedBox(
      child: SizedBox(
        width: _width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/rs-logo.png',
              width: _width,
              height: _width,
              semanticLabel: 'RetroShare',
            ),
            const SizedBox(height: 28),
            fullWidth(
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 46,
                    height: 1.1,
                    letterSpacing: 0.5,
                    decoration: TextDecoration.none,
                  ),
                  children: [
                    const TextSpan(
                      text: 'RETRO',
                      style: TextStyle(color: _retroBlue),
                    ),
                    TextSpan(text: 'SHARE', style: TextStyle(color: share)),
                  ],
                ),
              ),
            ),
            if (tagline)
              fullWidth(
                Text(
                  'secure communication for everyone',
                  style: TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 19,
                    height: 1.2,
                    color: share,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
