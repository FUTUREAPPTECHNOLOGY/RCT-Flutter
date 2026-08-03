import 'package:flutter/material.dart';

class AppRouteObserver extends NavigatorObserver {
  static final AppRouteObserver instance = AppRouteObserver();

  Route<dynamic>? currentRoute;

  String? currentRouteName;

  @override
  void didPush(Route route, Route? previousRoute) {
    currentRoute = route;
    currentRouteName = route.settings.name;

    debugPrint(
      'Route pushed: ${route.settings.name}',
    );

    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    currentRoute = previousRoute;
    currentRouteName = previousRoute?.settings.name;

    debugPrint(
      'Route popped: ${route.settings.name}',
    );

    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({
    Route? newRoute,
    Route? oldRoute,
  }) {
    currentRoute = newRoute;
    currentRouteName = newRoute?.settings.name;

    debugPrint(
      'Route replaced: ${oldRoute?.settings.name} -> ${newRoute?.settings.name}',
    );

    super.didReplace(
      newRoute: newRoute,
      oldRoute: oldRoute,
    );
  }

  bool isCurrent<T>() {
    return currentRoute?.settings.name == T.toString();
  }

  bool isRouteOpen(String routeName) {
    return currentRouteName == routeName;
  }
}