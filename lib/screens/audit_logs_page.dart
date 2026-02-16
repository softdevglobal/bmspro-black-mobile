import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils/timezone_helper.dart';

class AppColors {
  static const primary = Color(0xFFFF2D8F);
  static const primaryDark = Color(0xFFD81F75);
  static const accent = Color(0xFFFF6FB5);
  static const background = Color(0xFFFFF5FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF9E9E9E);
  static const border = Color(0xFFF2D2E9);
}

class AuditLogsPage extends StatefulWidget {
  const AuditLogsPage({super.key});

  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _ownerUid;
  String _adminTimezone = 'Australia/Sydney';
  bool _isLoading = true;
  List<Map<String, dynamic>> _logs = [];
  String _filterActionType = 'all';
  String _filterEntityType = 'all';
  String _searchQuery = '';

  final Map<String, Map<String, dynamic>> _actionTypeConfig = {
    'create': {'icon': FontAwesomeIcons.circlePlus, 'color': Colors.green, 'label': 'Created'},
    'update': {'icon': FontAwesomeIcons.penToSquare, 'color': Colors.blue, 'label': 'Updated'},
    'delete': {'icon': FontAwesomeIcons.trash, 'color': Colors.red, 'label': 'Deleted'},
    'statusChange': {'icon': FontAwesomeIcons.arrowsRotate, 'color': Colors.purple, 'label': 'Status Change'},
    'login': {'icon': FontAwesomeIcons.rightToBracket, 'color': Colors.teal, 'label': 'Login'},
    'logout': {'icon': FontAwesomeIcons.rightFromBracket, 'color': Colors.orange, 'label': 'Logout'},
    'other': {'icon': FontAwesomeIcons.circleInfo, 'color': Colors.grey, 'label': 'Other'},
  };

  final Map<String, Map<String, dynamic>> _entityTypeConfig = {
    'booking': {'icon': FontAwesomeIcons.calendarCheck, 'label': 'Booking'},
    'service': {'icon': FontAwesomeIcons.tags, 'label': 'Service'},
    'staff': {'icon': FontAwesomeIcons.user, 'label': 'Staff'},
    'branch': {'icon': FontAwesomeIcons.store, 'label': 'Branch'},
    'customer': {'icon': FontAwesomeIcons.userGroup, 'label': 'Customer'},
    'settings': {'icon': FontAwesomeIcons.gear, 'label': 'Settings'},
    'auth': {'icon': FontAwesomeIcons.shield, 'label': 'Auth'},
    'userProfile': {'icon': FontAwesomeIcons.userPen, 'label': 'Profile'},
  };

  @override
  void initState() {
    super.initState();
    _fetchOwnerUid();
  }

  Future<void> _fetchOwnerUid() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        final data = doc.data();
        final role = data?['role'] as String?;
        
        // Only salon_owner can view audit logs
        if (role != 'salon_owner') {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Access denied. Only salon owners can view audit logs.')),
            );
          }
          return;
        }
        
        // Get admin's timezone from their profile
        final timezone = data?['timezone'] as String? ?? 'Australia/Sydney';
        
        if (mounted) {
          setState(() {
            _ownerUid = user.uid;
            _adminTimezone = timezone;
          });
          _listenToLogs();
        }
      }
    } catch (e) {
      debugPrint('Error fetching owner UID: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _listenToLogs() {
    if (_ownerUid == null) return;

    _firestore
        .collection('auditLogs')
        .where('ownerUid', isEqualTo: _ownerUid)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      
      final logs = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
          'timestamp': data['createdAt'] ?? data['timestamp'],
        };
      }).toList();
      
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    }, onError: (error) {
      debugPrint('Error listening to audit logs: $error');
      // Try without orderBy if index doesn't exist
      _firestore
          .collection('auditLogs')
          .where('ownerUid', isEqualTo: _ownerUid)
          .limit(200)
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        
        final logs = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            ...data,
            'timestamp': data['createdAt'] ?? data['timestamp'],
          };
        }).toList();
        
        // Sort client-side
        logs.sort((a, b) {
          final aTime = a['timestamp'] as Timestamp?;
          final bTime = b['timestamp'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });
        
        setState(() {
          _logs = logs;
          _isLoading = false;
        });
      });
    });
  }

  List<Map<String, dynamic>> get _filteredLogs {
    return _logs.where((log) {
      if (_filterActionType != 'all' && log['actionType'] != _filterActionType) return false;
      if (_filterEntityType != 'all' && log['entityType'] != _filterEntityType) return false;
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final action = (log['action'] ?? '').toString().toLowerCase();
        final entityName = (log['entityName'] ?? '').toString().toLowerCase();
        final performedByName = (log['performedByName'] ?? '').toString().toLowerCase();
        final details = (log['details'] ?? '').toString().toLowerCase();
        return action.contains(query) || entityName.contains(query) || 
               performedByName.contains(query) || details.contains(query);
      }
      return true;
    }).toList();
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else {
      return 'Unknown';
    }
    
    // Convert to admin's timezone
    final localDate = TimezoneHelper.utcToLocal(date.toUtc(), _adminTimezone);
    final now = TimezoneHelper.nowInTimezone(_adminTimezone);
    final diff = now.difference(localDate);
    
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    
    return DateFormat('MMM d, yyyy').format(localDate);
  }

  String _formatFullTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else {
      return 'Unknown';
    }
    
    // Convert to admin's timezone
    final localDate = TimezoneHelper.utcToLocal(date.toUtc(), _adminTimezone);
    return DateFormat('EEEE, MMMM d, yyyy • h:mm a').format(localDate);
  }

  Map<String, dynamic> _getActionConfig(String? type) {
    return _actionTypeConfig[type] ?? _actionTypeConfig['other']!;
  }

  Map<String, dynamic> _getEntityConfig(String? type) {
    return _entityTypeConfig[type] ?? {'icon': FontAwesomeIcons.circle, 'label': type ?? 'Unknown'};
  }

  String _getRoleLabel(String? role) {
    switch (role) {
      case 'salon_owner': return 'Owner';
      case 'salon_branch_admin': return 'Branch Admin';
      case 'salon_staff': return 'Staff';
      default: return role ?? 'User';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(FontAwesomeIcons.arrowLeft, size: 20),
          color: AppColors.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Audit Logs',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                // Stats Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildStatCard('Total', _logs.length.toString(), FontAwesomeIcons.list, AppColors.primary),
                      const SizedBox(width: 12),
                      _buildStatCard('Today', _getTodayCount().toString(), FontAwesomeIcons.clock, Colors.blue),
                      const SizedBox(width: 12),
                      _buildStatCard('Filtered', _filteredLogs.length.toString(), FontAwesomeIcons.filter, Colors.green),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Search & Filters
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Search
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: TextField(
                          onChanged: (value) => setState(() => _searchQuery = value),
                          decoration: InputDecoration(
                            hintText: 'Search logs...',
                            hintStyle: TextStyle(color: AppColors.muted),
                            prefixIcon: Icon(FontAwesomeIcons.magnifyingGlass, size: 16, color: AppColors.muted),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Filter Dropdowns
                      Row(
                        children: [
                          Expanded(child: _buildFilterDropdown(
                            value: _filterActionType,
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('All Actions')),
                              ..._actionTypeConfig.entries.map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value['label'] as String),
                              )),
                            ],
                            onChanged: (value) => setState(() => _filterActionType = value ?? 'all'),
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _buildFilterDropdown(
                            value: _filterEntityType,
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('All Entities')),
                              ..._entityTypeConfig.entries.map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value['label'] as String),
                              )),
                            ],
                            onChanged: (value) => setState(() => _filterEntityType = value ?? 'all'),
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Logs List
                Expanded(
                  child: _filteredLogs.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredLogs.length,
                          itemBuilder: (context, index) => _buildLogCard(_filteredLogs[index]),
                        ),
                ),
              ],
            ),
    );
  }

  int _getTodayCount() {
    final today = DateTime.now();
    return _logs.where((log) {
      final timestamp = log['timestamp'];
      if (timestamp is Timestamp) {
        final date = timestamp.toDate();
        return date.year == today.year && date.month == today.month && date.day == today.day;
      }
      return false;
    }).length;
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(fontSize: 10, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(FontAwesomeIcons.chevronDown, size: 12, color: AppColors.muted),
          style: TextStyle(fontSize: 13, color: AppColors.text),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(FontAwesomeIcons.clipboardList, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'No audit logs found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _filterActionType != 'all' || _filterEntityType != 'all'
                ? 'Try adjusting your filters'
                : 'System activities will appear here',
            style: TextStyle(fontSize: 14, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final actionConfig = _getActionConfig(log['actionType']);
    final entityConfig = _getEntityConfig(log['entityType']);
    
    return GestureDetector(
      onTap: () => _showLogDetails(log),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (actionConfig['color'] as Color).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                actionConfig['icon'] as IconData,
                size: 16,
                color: actionConfig['color'] as Color,
              ),
            ),
            const SizedBox(width: 12),
            
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          log['action'] ?? 'Unknown action',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTimestamp(log['timestamp']),
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  
                  // Tags Row
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      // Entity Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(entityConfig['icon'] as IconData, size: 10, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Text(
                              entityConfig['label'] as String,
                              style: TextStyle(fontSize: 10, color: AppColors.muted),
                            ),
                            if (log['entityName'] != null) ...[
                              Text(': ', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                              Flexible(
                                child: Text(
                                  log['entityName'],
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.text),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      
                      // User Badge
                      if (log['performedByName'] != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FontAwesomeIcons.user, size: 10, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Text(
                              log['performedByName'],
                              style: TextStyle(fontSize: 10, color: AppColors.muted),
                            ),
                            if (log['performedByRole'] != null)
                              Text(
                                ' (${_getRoleLabel(log['performedByRole'])})',
                                style: TextStyle(fontSize: 10, color: AppColors.muted.withOpacity(0.7)),
                              ),
                          ],
                        ),
                    ],
                  ),
                  
                  // Details
                  if (log['details'] != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      log['details'],
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            
            // Chevron
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 12),
              child: Icon(FontAwesomeIcons.chevronRight, size: 12, color: AppColors.muted.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogDetails(Map<String, dynamic> log) {
    final actionConfig = _getActionConfig(log['actionType']);
    final entityConfig = _getEntityConfig(log['entityType']);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.grey.shade800, Colors.grey.shade900],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (actionConfig['color'] as Color).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(actionConfig['icon'] as IconData, color: actionConfig['color'] as Color, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Audit Log Details',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        Text(
                          entityConfig['label'] as String,
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(FontAwesomeIcons.xmark, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Action
                  _buildDetailCard(
                    title: 'Action',
                    icon: FontAwesomeIcons.bolt,
                    child: Text(
                      log['action'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                  
                  // Timestamp
                  _buildDetailCard(
                    title: 'Timestamp',
                    icon: FontAwesomeIcons.clock,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatFullTimestamp(log['timestamp']),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(FontAwesomeIcons.globe, size: 10, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Text(
                              TimezoneHelper.getTimezoneLabel(_adminTimezone),
                              style: TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Performed By
                  _buildDetailCard(
                    title: 'Performed By',
                    icon: FontAwesomeIcons.user,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primary,
                          child: Text(
                            (log['performedByName'] ?? 'U')[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log['performedByName'] ?? 'Unknown',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (log['performedByRole'] != null)
                              Text(
                                _getRoleLabel(log['performedByRole']),
                                style: TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Entity
                  if (log['entityName'] != null || log['entityId'] != null)
                    _buildDetailCard(
                      title: '${entityConfig['label']} Details',
                      icon: entityConfig['icon'] as IconData,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (log['entityName'] != null)
                            Text(log['entityName'], style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (log['entityId'] != null)
                            Text(
                              'ID: ${log['entityId']}',
                              style: TextStyle(fontSize: 11, color: AppColors.muted, fontFamily: 'monospace'),
                            ),
                        ],
                      ),
                    ),
                  
                  // Branch
                  if (log['branchName'] != null)
                    _buildDetailCard(
                      title: 'Branch',
                      icon: FontAwesomeIcons.store,
                      child: Text(log['branchName']),
                    ),
                  
                  // Value Changes
                  if (log['previousValue'] != null || log['newValue'] != null)
                    _buildDetailCard(
                      title: 'Changes',
                      icon: FontAwesomeIcons.codeBranch,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (log['previousValue'] != null) ...[
                            Text('Previous:', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                            Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(top: 4, bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(log['previousValue'], style: const TextStyle(fontSize: 13)),
                            ),
                          ],
                          if (log['newValue'] != null) ...[
                            Text('New:', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                            Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(log['newValue'], style: const TextStyle(fontSize: 13)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  
                  // Details
                  if (log['details'] != null)
                    _buildDetailCard(
                      title: 'Additional Details',
                      icon: FontAwesomeIcons.circleInfo,
                      child: Text(log['details']),
                    ),
                  
                  // Log ID
                  _buildDetailCard(
                    title: 'Log ID',
                    icon: FontAwesomeIcons.fingerprint,
                    child: Text(
                      log['id'] ?? 'Unknown',
                      style: TextStyle(fontSize: 11, color: AppColors.muted, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

