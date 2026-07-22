import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'router.dart';

class WorkItOutApp extends StatelessWidget {
  const WorkItOutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Work It Out',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}
