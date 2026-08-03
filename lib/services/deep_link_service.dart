import 'dart:async';
import 'dart:developer';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:rct/services/route_observer.dart';
import 'package:rct/view/RealEstate/details_screen.dart';
import 'package:rct/view/ownership/ownership_details_screen.dart';
import 'package:rct/view/share_rct/details.dart';

class DeepLinkManager extends WidgetsBindingObserver {
  DeepLinkManager._();

  static final DeepLinkManager instance = DeepLinkManager._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  Uri? _pendingLink;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  bool _navigating = false;

  /// Call once from main()
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    _pendingLink = await _appLinks.getInitialLink();
  }

  /// Call once after Home/Splash finishes loading
  void handlePendingLink() {
    if (_pendingLink == null) return;
    handleDeepLink(_pendingLink);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log('App lifecycle: $state');

    if (state == AppLifecycleState.resumed && _pendingLink != null) {
      log('Handling pending deep link after resume');
      _navigateWhenReady();
    }
  }

  /// Call from HomeScreen.initState()
  void startListening() {
    _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen(
      (Uri? uri) {
        log('Deep link received: $uri');
        handleDeepLink(uri);
      },
      onError: (e) => log('Deep link error: $e'),
    );
  }

  void dispose() {
    _subscription?.cancel();
  }

  void handleDeepLink(Uri? link) {
    if (link == null || link.toString().isEmpty || _navigating) return;
    _pendingLink = link;
    _navigateWhenReady();
  }

  void _navigateWhenReady() async {
    // Check if navigator is ready and app is resumed
    if (navigatorKey.currentState == null ||
        SchedulerBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      await Future.delayed(const Duration(milliseconds: 300));
      _navigateWhenReady();
      return;
    }
    final Uri? link = _pendingLink;
    if (link == null) return;
    _navigating = true;
    _pendingLink = null;
    try {
      if (link.pathSegments.contains("product")) {
        _handleProductDetailsLink(link);
      } else if (link.pathSegments.contains("details")) {
        _handleRentDetailsLink(link);
      } else if (link.pathSegments.contains("share")) {
        _handleShareDetailsLink(link);
      }
    } finally {
      _navigating = false;
    }
  }

  void _handleShareDetailsLink(Uri link) {
    final propertyId = link.pathSegments.last;
    WidgetsBinding.instance.addPostFrameCallback((_) {
        if (AppRouteObserver.instance.currentRouteName ==
            ShareDetails.ScreenId) {
          log("shareDetailsScreen already opened");

          return;
        }
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            settings: const RouteSettings(name: ShareDetails.ScreenId),
            builder: (_) => ShareDetails(id: propertyId),
          ),
        );
      } else {
        Future.delayed(
          const Duration(milliseconds: 500),
          () => _handleShareDetailsLink(link),
        );
      }
    });
  }

  void _handleRentDetailsLink(Uri link) {
    final propertyId = link.pathSegments.last;
    log("Handling rent details: $propertyId");
    WidgetsBinding.instance.addPostFrameCallback((_) {
       if (AppRouteObserver.instance.currentRouteName ==
            OwnershipDetailsScreen.ScreenId) {
          log("OwnershipDetailsScreen already opened");

          return;
        }
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            settings:
                const RouteSettings(name: OwnershipDetailsScreen.ScreenId),
            builder: (_) => OwnershipDetailsScreen(
              id: propertyId,
            ),
          ),
        );
      } else {
        Future.delayed(
          const Duration(milliseconds: 500),
          () => _handleRentDetailsLink(link),
        );
      }
    });
  }

  void _handleProductDetailsLink(Uri link) {
    final productId = link.pathSegments.last;
    WidgetsBinding.instance.addPostFrameCallback((_) {
        if (AppRouteObserver.instance.currentRouteName ==
            DetailsScreen.screenId) {
          log("productDetailsScreen already opened");

          return;
        }
      if (navigatorKey.currentState != null) {
      
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            settings: const RouteSettings(
              name: DetailsScreen.screenId,
            ),
            builder: (_) => DetailsScreen(
              id: productId,
              isdeeplink: true,
            ),
          ),
        );
      } else {
        Future.delayed(
          const Duration(milliseconds: 500),
          () => _handleProductDetailsLink(link),
        );
      }
    });
  }
}
