import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hustl_app/core/widgets/responsive_center.dart';

void main() {
  testWidgets('constrains child width on wide screens', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(1000, 800)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 1000,
            child: ResponsiveCenter(
              maxContentWidth: 600,
              child: SizedBox(key: Key('wide'), width: 1000, height: 100),
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byKey(const Key('wide')));
    expect(size.width, 600);
  });
}
