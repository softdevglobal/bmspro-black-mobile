import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appointment_requests_page.dart';
import 'owner_bookings_page.dart';

class _NotifTheme {
  static const Color primary = Color(0xFF1A1A1A);
  static const Color accent = Color(0xFF333333);
  static const Color background = Color(0xFFF5F5F5);
  static const Color card = Colors.white;
  static const Color text = Color(0xFF1A1A1A);
  static const Color muted = Color(0xFF9E9E9E);
  static const Color unreadBg = Color(0xFFFFF1F7);
}

class NotificationItem {
  final String id;
  final String title;
  final String description;
  final String time;
  final IconData icon;
  final String type; // 'task', 'system', 'booking_assigned'
  bool isRead;
  final Map<String, dynamic>? rawData;
  
  NotificationItem({
    required this.id,
    required this.title,
    required this.description,
    required this.time,
    required this.icon,
    required this.type,
    this.isRead = false,
    this.rawData,
  });

  /// Create NotificationItem from Firestore document
  factory NotificationItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final type = (data['type'] ?? 'system').toString();
    final title = (data['title'] ?? 'Notification').toString();
    final message = (data['message'] ?? '').toString();
    final isRead = data['read'] == true;
    
    // Parse timestamp to relative time string
    String timeStr = 'Just now';
    if (data['createdAt'] != null) {
      try {
        final timestamp = data['createdAt'] as Timestamp;
        final dt = timestamp.toDate();
        timeStr = _formatRelativeTime(dt);
      } catch (_) {}
    }
    
    // Determine icon based on notification type
    IconData icon = FontAwesomeIcons.bell;
    String displayType = 'system';
    
    // Staff assignment notifications (new workflow)
    if (type == 'staff_assignment') {
      icon = FontAwesomeIcons.userClock;
      displayType = 'task';
    } else if (type == 'staff_reassignment') {
      icon = FontAwesomeIcons.userPlus;
      displayType = 'task';
    } else if (type == 'booking_assigned' || type == 'booking_confirmed') {
      icon = FontAwesomeIcons.calendarCheck;
      displayType = 'task';
    } else if (type == 'booking_completed') {
      icon = FontAwesomeIcons.circleCheck;
      displayType = 'task';
    } else if (type == 'booking_canceled') {
      icon = FontAwesomeIcons.ban;
      displayType = 'task';
    } else if (type == 'booking_status_changed') {
      icon = FontAwesomeIcons.calendarDay;
      displayType = 'task';
    } else if (type == 'staff_accepted') {
      icon = FontAwesomeIcons.thumbsUp;
      displayType = 'system';
    } else if (type == 'staff_rejected') {
      icon = FontAwesomeIcons.userXmark;
      displayType = 'system';
    } else if (type == 'staff_booking_created') {
      icon = FontAwesomeIcons.calendarPlus;
      displayType = 'task';
    } else if (type == 'branch_booking_created' || type == 'booking_needs_assignment') {
      icon = FontAwesomeIcons.calendarPlus;
      displayType = 'task';
    } else if (type == 'booking_engine_new_booking') {
      icon = FontAwesomeIcons.globe;
      displayType = 'task';
    } else if (type == 'auto_clock_out') {
      icon = FontAwesomeIcons.locationCrosshairs;
      displayType = 'system';
    }
    
    return NotificationItem(
      id: doc.id,
      title: title,
      description: message,
      time: timeStr,
      icon: icon,
      type: displayType,
      isRead: isRead,
      rawData: data,
    );
  }
  
  static String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} ${diff.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} ${diff.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with TickerProviderStateMixin {
  String _currentFilter = 'all'; // 'all', 'task', 'system'

  List<NotificationItem> _notifications = [];
  List<NotificationItem> _staffNotifications = [];
  List<NotificationItem> _ownerNotifications = [];
  List<NotificationItem> _customerNotifications = [];
  List<NotificationItem> _branchAdminNotifications = [];
  late AnimationController _bellBadgeController;
  StreamSubscription<QuerySnapshot>? _notificationsSub;
  StreamSubscription<QuerySnapshot>? _ownerNotificationsSub;
  StreamSubscription<QuerySnapshot>? _customerNotificationsSub;
  StreamSubscription<QuerySnapshot>? _branchAdminNotificationsSub;
  bool _loading = true;
  String? _currentUserId;
  Set<String> _dismissedNotificationIds = {};

  @override
  void initState() {
    super.initState();
    _bellBadgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _loadDismissedNotifications();
    _loadNotifications();
  }

  Future<void> _loadDismissedNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dismissedIds = prefs.getStringList('dismissed_notification_ids') ?? [];
      setState(() {
        _dismissedNotificationIds = dismissedIds.toSet();
      });
    } catch (e) {
      debugPrint("Error loading dismissed notifications: $e");
    }
  }

  Future<void> _saveDismissedNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('dismissed_notification_ids', _dismissedNotificationIds.toList());
    } catch (e) {
      debugPrint("Error saving dismissed notifications: $e");
    }
  }

  void _mergeNotifications() {
    // Combine staff, owner, and customer notifications, remove duplicates, and sort by time
    final allNotifications = <String, NotificationItem>{};
    
    for (final notification in _staffNotifications) {
      // Filter out dismissed notifications
      if (!_dismissedNotificationIds.contains(notification.id)) {
        allNotifications[notification.id] = notification;
      }
    }
    for (final notification in _ownerNotifications) {
      // Only add if not already present (avoid duplicates) and not dismissed
      if (!allNotifications.containsKey(notification.id) && 
          !_dismissedNotificationIds.contains(notification.id)) {
        allNotifications[notification.id] = notification;
      }
    }
    for (final notification in _customerNotifications) {
      // Only add if not already present (avoid duplicates) and not dismissed
      if (!allNotifications.containsKey(notification.id) && 
          !_dismissedNotificationIds.contains(notification.id)) {
        allNotifications[notification.id] = notification;
      }
    }
    for (final notification in _branchAdminNotifications) {
      // Only add if not already present (avoid duplicates) and not dismissed
      if (!allNotifications.containsKey(notification.id) && 
          !_dismissedNotificationIds.contains(notification.id)) {
        allNotifications[notification.id] = notification;
      }
    }
    
    final merged = allNotifications.values.toList();
    // Sort by createdAt timestamp (most recent first)
    merged.sort((a, b) {
      final aTime = a.rawData?['createdAt'] as Timestamp?;
      final bTime = b.rawData?['createdAt'] as Timestamp?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1; // nulls go to the end
      if (bTime == null) return -1;
      return bTime.compareTo(aTime); // Descending (newest first)
    });
    
    setState(() {
      _notifications = merged;
      _loading = false;
    });
  }

  Future<void> _loadNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
      });
      return;
    }
    
    _currentUserId = user.uid;
    
    // Listen to notifications where staffUid matches current user
    // This captures booking assignments to this staff member
    _notificationsSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('staffUid', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        _staffNotifications = snapshot.docs
            .map((doc) => NotificationItem.fromFirestore(doc))
            .toList();
        _mergeNotifications();
      }
    }, onError: (e) {
      debugPrint("Error loading staff notifications: $e");
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    });
    
    // Also listen to notifications where ownerUid or targetOwnerUid matches current user
    // This captures notifications for salon owners (e.g., staff created bookings)
    _ownerNotificationsSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('ownerUid', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        // Filter to only include owner-specific notifications
        // (not ones where staffUid == user.uid, those are already in _staffNotifications)
        _ownerNotifications = snapshot.docs
            .where((doc) {
              final data = doc.data();
              final staffUid = data['staffUid']?.toString();
              // Include if staffUid is different from current user or null
              return staffUid != user.uid;
            })
            .map((doc) => NotificationItem.fromFirestore(doc))
            .toList();
        _mergeNotifications();
      }
    }, onError: (e) {
      debugPrint("Error loading owner notifications: $e");
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    });
    
    // Also listen to notifications where customerUid matches current user
    // This captures customer booking notifications
    _customerNotificationsSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('customerUid', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        _customerNotifications = snapshot.docs
            .map((doc) => NotificationItem.fromFirestore(doc))
            .toList();
        _mergeNotifications();
      }
    }, onError: (e) {
      debugPrint("Error loading customer notifications: $e");
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    });
    
    // Also listen to notifications where branchAdminUid matches current user
    // This captures branch admin notifications (e.g., "any-staff" bookings)
    // Note: Not using orderBy to avoid needing Firestore index (same as notification_service.dart)
    _branchAdminNotificationsSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('branchAdminUid', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        // Sort manually by createdAt (descending)
        final notifications = snapshot.docs
            .map((doc) => NotificationItem.fromFirestore(doc))
            .toList();
        notifications.sort((a, b) {
          final aTime = a.rawData?['createdAt'] as Timestamp?;
          final bTime = b.rawData?['createdAt'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime); // Descending (newest first)
        });
        _branchAdminNotifications = notifications;
        _mergeNotifications();
      }
    }, onError: (e) {
      debugPrint("Error loading branch admin notifications: $e");
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    });
    
    // Also listen to notifications where targetAdminUid matches current user
    // This captures notifications targeted to branch admins
    FirebaseFirestore.instance
        .collection('notifications')
        .where('targetAdminUid', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        // Only add notifications that aren't already in branchAdminNotifications
        final newNotifications = snapshot.docs
            .where((doc) {
              final data = doc.data();
              final branchAdminUid = data['branchAdminUid']?.toString();
              // Only include if branchAdminUid doesn't match (to avoid duplicates)
              return branchAdminUid != user.uid;
            })
            .map((doc) => NotificationItem.fromFirestore(doc))
            .toList();
        
        // Merge with existing branch admin notifications
        final allBranchAdminNotifs = <String, NotificationItem>{};
        for (final notif in _branchAdminNotifications) {
          allBranchAdminNotifs[notif.id] = notif;
        }
        for (final notif in newNotifications) {
          if (!allBranchAdminNotifs.containsKey(notif.id)) {
            allBranchAdminNotifs[notif.id] = notif;
          }
        }
        // Sort by createdAt
        final sorted = allBranchAdminNotifs.values.toList();
        sorted.sort((a, b) {
          final aTime = a.rawData?['createdAt'] as Timestamp?;
          final bTime = b.rawData?['createdAt'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime); // Descending
        });
        _branchAdminNotifications = sorted;
        _mergeNotifications();
      }
    }, onError: (e) {
      debugPrint("Error loading targetAdminUid notifications: $e");
    });
  }

  @override
  void dispose() {
    _bellBadgeController.dispose();
    _notificationsSub?.cancel();
    _ownerNotificationsSub?.cancel();
    _customerNotificationsSub?.cancel();
    _branchAdminNotificationsSub?.cancel();
    super.dispose();
  }

  List<NotificationItem> get _filteredNotifications {
    if (_currentFilter == 'all') return _notifications;
    return _notifications.where((n) => n.type == _currentFilter).toList();
  }

  int get _unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> _markAsRead(NotificationItem item) async {
    if (!item.isRead) {
      // Update local state immediately for responsiveness
      setState(() {
        item.isRead = true;
      });
      
      // Update Firestore
      try {
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(item.id)
            .update({'read': true});
      } catch (e) {
        debugPrint("Error marking notification as read: $e");
      }
    }
  }

  Future<void> _clearAll() async {
    if (_notifications.isEmpty) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Notifications'),
        content: const Text('Are you sure you want to clear all notifications? This will hide them from your notification panel.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // Add all current notification IDs to dismissed set
    final allNotificationIds = _notifications.map((n) => n.id).toSet();
    setState(() {
      _dismissedNotificationIds.addAll(allNotificationIds);
      _notifications.clear();
    });
    
    // Save dismissed IDs to SharedPreferences
    await _saveDismissedNotifications();
    
    // Mark all notifications as read in Firestore (this is allowed by security rules)
    try {
      WriteBatch? batch = FirebaseFirestore.instance.batch();
      int batchCount = 0;
      
      for (final n in allNotificationIds) {
        if (batchCount >= 500) {
          await batch!.commit();
          batch = FirebaseFirestore.instance.batch();
          batchCount = 0;
        }
        
        batch!.update(
          FirebaseFirestore.instance.collection('notifications').doc(n),
          {'read': true},
        );
        batchCount++;
      }
      
      if (batchCount > 0 && batch != null) {
        await batch.commit();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications cleared'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error marking notifications as read: $e");
      // Even if marking as read fails, the notifications are already dismissed locally
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications cleared'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _NotifTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: _NotifTheme.primary,
                      ),
                    )
                  : _notifications.isEmpty
                      ? _buildEmptyState()
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildTabs(),
                            const SizedBox(height: 24),
                            _buildNotificationList(),
                            const SizedBox(height: 32),
                            if (_notifications.isNotEmpty) _buildClearButton(),
                            const SizedBox(height: 16),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: _NotifTheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                FontAwesomeIcons.bellSlash,
                size: 40,
                color: _NotifTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Notifications',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _NotifTheme.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You\'ll receive notifications here when bookings are assigned to you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: _NotifTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(color: _NotifTheme.background),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              FontAwesomeIcons.chevronLeft,
              size: 18,
              color: _NotifTheme.text,
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Notifications',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _NotifTheme.text),
              ),
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        _buildTab('All', 'all'),
        const SizedBox(width: 24),
        _buildTab('Tasks', 'task'),
        const SizedBox(width: 24),
        _buildTab('System', 'system'),
      ],
    );
  }

  Widget _buildTab(String label, String filterId) {
    final bool isActive = _currentFilter == filterId;
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentFilter = filterId;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              color: isActive ? _NotifTheme.primary : _NotifTheme.muted,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 3,
            width: isActive ? 20 : 0,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_NotifTheme.primary, _NotifTheme.accent]),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList() {
    final items = _filteredNotifications;
    if (items.isEmpty && _notifications.isNotEmpty) {
      // Filter returned no results
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(
              FontAwesomeIcons.filter,
              size: 32,
              color: _NotifTheme.muted.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No ${_currentFilter == 'task' ? 'task' : 'system'} notifications',
              style: const TextStyle(
                color: _NotifTheme.muted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _NotificationCard(
                item: item,
                onTap: () {
                  _markAsRead(item);
                  // Navigate based on notification type
                  final type = item.rawData?['type']?.toString() ?? '';
                  if (type == 'staff_assignment' || type == 'staff_reassignment') {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AppointmentRequestsPage()),
                    );
                  } else if (type == 'staff_booking_created' ||
                             type == 'branch_booking_created' ||
                             type == 'booking_needs_assignment' ||
                             type == 'booking_confirmed' ||
                             type == 'booking_status_changed' ||
                             type == 'booking_engine_new_booking' ||
                             type == 'staff_rejected') {
                    // Navigate to bookings page for owner notifications
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const OwnerBookingsPage()),
                    );
                  }
                },
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildClearButton() {
    return Center(
      child: TextButton(
        onPressed: _clearAll,
        style: TextButton.styleFrom(
          foregroundColor: _NotifTheme.primary,
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        child: const Text('Clear All'),
      ),
    );
  }
}

class _NotificationCard extends StatefulWidget {
  final NotificationItem item;
  final VoidCallback onTap;
  const _NotificationCard({
    required this.item,
    required this.onTap,
  });

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isRead = widget.item.isRead;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isRead ? _NotifTheme.card : _NotifTheme.unreadBg,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(
              color: isRead ? Colors.transparent : _NotifTheme.primary,
              width: 4,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: _NotifTheme.primary.withOpacity(0.08),
              blurRadius: 25,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 16),
              child: isRead
                  ? Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.grey.shade300, width: 2),
                        shape: BoxShape.circle,
                      ),
                    )
                  : ScaleTransition(
                      scale: Tween<double>(begin: 1.0, end: 1.2).animate(
                        CurvedAnimation(
                            parent: _pulseController, curve: Curves.easeInOut),
                      ),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _NotifTheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _NotifTheme.primary.withOpacity(0.5),
                              blurRadius: 8,
                            )
                          ],
                        ),
                      ),
                    ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isRead ? FontWeight.w500 : FontWeight.w600,
                      color: isRead ? _NotifTheme.muted : _NotifTheme.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.item.description,
                    style:
                        const TextStyle(fontSize: 14, color: _NotifTheme.muted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.item.time,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isRead ? _NotifTheme.muted : _NotifTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Icon(
                widget.item.icon,
                size: 18,
                color: isRead ? _NotifTheme.muted : _NotifTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


