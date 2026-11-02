import 'package:flutter/material.dart';

import '../theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 30, this.light = false});
  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: light ? Brand.accent : Brand.deep, borderRadius: BorderRadius.circular(size * 0.3)),
        alignment: Alignment.center,
        child: Text('p', style: display(size * 0.62, color: light ? Brand.ink : Colors.white)),
      ),
      const SizedBox(width: 10),
      Text('purpose', style: display(size * 0.68, color: light ? Colors.white : Brand.ink, weight: FontWeight.w700)),
    ]);
  }
}
