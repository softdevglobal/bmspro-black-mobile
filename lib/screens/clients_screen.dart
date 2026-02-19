import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'client_profile_page.dart';
import '../widgets/animated_toggle.dart';

// --- 1. Theme & Colors ---
class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const primaryDark = Color(0xFF000000);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const green = Color(0xFF10B981);
  static const yellow = Color(0xFFFFD700);
  static const red = Color(0xFFEF4444);
  static const chipBg = Color(0xFFF3F4F6);
}

// --- 2. Client Model ---
class Client {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String type; // 'vip', 'new', 'risk', 'active'
  final String avatarUrl;
  final int visits;
  final DateTime? lastVisit;

  Client({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.type,
    required this.avatarUrl,
    required this.visits,
    required this.lastVisit,
  });
}

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> with TickerProviderStateMixin {
  // Live data from Firestore
  List<Client> _allClients = [];
  List<Client> _myClients = [];
  List<Client> _branchClients = [];
  
  // Saved customers from customers collection
  List<Client> _savedMyClients = [];
  List<Client> _savedBranchClients = [];

  // State
  String _currentFilter = 'all';
  String _searchQuery = '';
  List<Client> _filteredClients = [];
  
  // Toggle state: false = My Clients, true = Branch Clients
  bool _showBranchClients = false;
  
  // User role info
  String? _userRole;
  String? _branchId;
  String? _ownerUid;
  bool _isLoadingRole = true;

  // Animation Controllers
  final List<AnimationController> _staggerControllers = [];

  @override
  void initState() {
    super.initState();
    _filteredClients = [];
    _fetchUserRoleAndListenToClients();
  }

  Future<void> _fetchUserRoleAndListenToClients() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoadingRole = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (mounted && userDoc.exists) {
        final data = userDoc.data()!;
        setState(() {
          String rawRole = (data['role'] ?? '').toString();
          // role is already normalized (staff, branch_admin, workshop_owner)
          _userRole = rawRole;
          _branchId = (data['branchId'] ?? '').toString();
          // For branch admin and staff, use ownerUid; for owner, use own uid
          if (_userRole == 'branch_admin' || _userRole == 'staff') {
            _ownerUid = (data['ownerUid'] ?? user.uid).toString();
          } else {
            _ownerUid = user.uid;
          }
          _isLoadingRole = false;
        });
        debugPrint('User role loaded: $_userRole, ownerUid: $_ownerUid, branchId: $_branchId');
        debugPrint('Is staff: $_isStaff, Is branch admin: $_isBranchAdmin');
        _listenToClients();
      } else {
        setState(() {
          // Try to get ownerUid from user document if available, otherwise use own uid
          _ownerUid = user.uid;
          _isLoadingRole = false;
        });
        _listenToClients();
      }
    } catch (e) {
      debugPrint('Error fetching user role: $e');
      final user = FirebaseAuth.instance.currentUser;
      setState(() {
        _ownerUid = user?.uid;
        _isLoadingRole = false;
      });
      _listenToClients();
    }
  }

  bool get _isBranchAdmin => _userRole == 'branch_admin';
  bool get _isStaff => _userRole == 'staff';

  void _listenToClients() {
    if (_ownerUid == null || _ownerUid!.isEmpty) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // Listen to saved customers collection (optional - may not have permissions)
    // If this fails, we'll still get clients from bookings
    FirebaseFirestore.instance
        .collection('customers')
        .where('ownerUid', isEqualTo: _ownerUid)
        .snapshots()
        .listen((snap) {
      final List<Client> myClients = [];
      final List<Client> branchClients = [];

      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] ?? data['fullName'] ?? '').toString().trim();
        final email = (data['email'] ?? '').toString().trim();
        final phone = (data['phone'] ?? '').toString().trim();
        final staffId = (data['staffId'] ?? '').toString();
        final customerBranchId = (data['branchId'] ?? '').toString();
        final visits = (data['visits'] ?? 0) as int;

        if (name.isEmpty && email.isEmpty && phone.isEmpty) continue;

        final client = Client(
          id: doc.id,
          name: name.isNotEmpty ? name : (email.isNotEmpty ? email : phone),
          phone: phone,
          email: email,
          type: visits >= 8 ? 'vip' : (visits <= 1 ? 'new' : 'active'),
          avatarUrl: '',
          visits: visits,
          lastVisit: null,
        );

        // Check if this is my client (created by me)
        if (staffId == currentUserId || data['createdBy'] == currentUserId) {
          myClients.add(client);
        }

        // Check if this belongs to my branch
        if (_branchId != null && _branchId!.isNotEmpty && customerBranchId == _branchId) {
          branchClients.add(client);
        }
      }

      if (!mounted) return;
      setState(() {
        _savedMyClients = myClients;
        _savedBranchClients = branchClients;
      });
      _mergeAndFilterClients();
    }, onError: (e) {
      // Silently handle permission errors - clients will still be loaded from bookings
      debugPrint('Note: Could not access customers collection (may not have permissions). Clients will be loaded from bookings instead.');
      // Initialize empty lists if customers collection is not accessible
      if (!mounted) return;
      setState(() {
        _savedMyClients = [];
        _savedBranchClients = [];
      });
      // Still merge and filter with empty saved clients
      _mergeAndFilterClients();
    });

    // Listen to bookings collection
    debugPrint('Starting to listen to bookings for ownerUid: $_ownerUid');
    FirebaseFirestore.instance
        .collection('bookings')
        .where('ownerUid', isEqualTo: _ownerUid)
        .snapshots()
        .listen((snap) {
      debugPrint('Received ${snap.docs.length} bookings from Firestore');
      final Map<String, Map<String, dynamic>> allClientsMap = {};
      final Map<String, Map<String, dynamic>> myClientsMap = {};
      final Map<String, Map<String, dynamic>> branchClientsMap = {};
      
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      debugPrint('Processing bookings for currentUserId: $currentUserId, role: $_userRole');

      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['client'] ?? '').toString().trim();
        final email = (data['clientEmail'] ?? '').toString().trim();
        final phone = (data['clientPhone'] ?? '').toString().trim();
        final bookingBranchId = (data['branchId'] ?? '').toString();

        if (name.isEmpty && email.isEmpty && phone.isEmpty) continue;

        final keySource = data['customerUid'] ??
            (email.isNotEmpty
                ? email
                : (phone.isNotEmpty ? phone : name));
        final key = keySource.toString().toLowerCase();

        final dateStr = (data['date'] ?? '').toString();
        DateTime? bookingDate;
        try {
          if (dateStr.isNotEmpty) {
            bookingDate = DateTime.parse(dateStr);
          }
        } catch (_) {}

        // Check if this booking belongs to current user (staff)
        // Check both staffId and staffAuthUid at booking level
        bool isMyClient = false;
        final bookingStaffId = data['staffId']?.toString();
        final bookingStaffAuthUid = data['staffAuthUid']?.toString();
        
        debugPrint('Checking booking for client: $name');
        debugPrint('  currentUserId: $currentUserId');
        debugPrint('  bookingStaffId: $bookingStaffId');
        debugPrint('  bookingStaffAuthUid: $bookingStaffAuthUid');
        
        if (bookingStaffId == currentUserId || bookingStaffAuthUid == currentUserId) {
          isMyClient = true;
          debugPrint('  ✓ Matched at booking level');
        }
        
        // Also check services array for staff assignment
        if (!isMyClient && data['services'] is List) {
          final services = data['services'] as List;
          debugPrint('  Checking ${services.length} services');
          for (final service in services) {
            if (service is Map) {
              final serviceStaffId = service['staffId']?.toString();
              final serviceStaffAuthUid = service['staffAuthUid']?.toString();
              
              debugPrint('    Service staffId: $serviceStaffId, staffAuthUid: $serviceStaffAuthUid');
              
              if (serviceStaffId == currentUserId || serviceStaffAuthUid == currentUserId) {
                isMyClient = true;
                debugPrint('  ✓ Matched at service level');
                break;
              }
            }
          }
        }
        
        debugPrint('  Final isMyClient: $isMyClient');

        // Check if this booking belongs to current branch
        bool isBranchClient = _branchId != null && 
            _branchId!.isNotEmpty && 
            bookingBranchId == _branchId;

        // Helper to add/update client in a map
        void addToMap(Map<String, Map<String, dynamic>> map) {
          final existing = map[key];
          if (existing == null) {
            map[key] = {
              'name': name.isNotEmpty ? name : (email.isNotEmpty ? email : phone),
              'email': email,
              'phone': phone,
              'visits': 1,
              'lastVisit': bookingDate,
            };
          } else {
            existing['visits'] = (existing['visits'] as int) + 1;
            final currentLast = existing['lastVisit'] as DateTime?;
            if (bookingDate != null &&
                (currentLast == null || bookingDate.isAfter(currentLast))) {
              existing['lastVisit'] = bookingDate;
            }
          }
        }

        // Add to all clients
        addToMap(allClientsMap);
        
        // Add to my clients if served by me
        if (isMyClient) {
          addToMap(myClientsMap);
        }
        
        // Add to branch clients if same branch
        if (isBranchClient) {
          addToMap(branchClientsMap);
        }
      }

      // Convert maps to Client lists
      List<Client> convertMapToClients(Map<String, Map<String, dynamic>> map) {
        final now = DateTime.now();
        return map.entries.map((entry) {
          final data = entry.value;
          final visits = (data['visits'] as int?) ?? 0;
          final DateTime? lastVisit = data['lastVisit'] as DateTime?;

          String type = 'active';
          if (visits >= 8) {
            type = 'vip';
          } else if (visits <= 1) {
            type = 'new';
          }
          if (lastVisit != null &&
              now.difference(lastVisit).inDays > 120 &&
              visits > 0) {
            type = 'risk';
          }

          final name = (data['name'] as String?) ?? 'Customer';
          final email = (data['email'] as String?) ?? '';
          final phone = (data['phone'] as String?) ?? '';

          final avatarUrl =
              'https://ui-avatars.com/api/?background=1A1A1A&color=fff&name=${Uri.encodeComponent(name)}';

          return Client(
            id: entry.key,
            name: name,
            phone: phone,
            email: email,
            type: type,
            avatarUrl: avatarUrl,
            visits: visits,
            lastVisit: lastVisit,
          );
        }).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }

      final allClients = convertMapToClients(allClientsMap);
      final myClients = convertMapToClients(myClientsMap);
      final branchClients = convertMapToClients(branchClientsMap);

      debugPrint('=== Client Summary ===');
      debugPrint('Total bookings processed: ${snap.docs.length}');
      debugPrint('All clients count: ${allClients.length}');
      debugPrint('My clients count: ${myClients.length}');
      debugPrint('Branch clients count: ${branchClients.length}');
      debugPrint('Current user role: $_userRole');
      debugPrint('Is staff: $_isStaff');
      if (myClients.isNotEmpty) {
        debugPrint('My clients: ${myClients.map((c) => c.name).join(", ")}');
      }

      if (!mounted) return;

      setState(() {
        _allClients = allClients;
        _myClients = myClients;
        _branchClients = branchClients;
      });

      _mergeAndFilterClients();
    }, onError: (e) {
      debugPrint('Error loading clients: $e');
    });
  }

  // Merge saved customers with booking customers and filter
  void _mergeAndFilterClients() {
    // Merge saved clients with booking-derived clients
    List<Client> mergeClients(List<Client> bookingClients, List<Client> savedClients) {
      final Map<String, Client> merged = {};
      
      // Add booking clients
      for (final client in bookingClients) {
        final key = (client.email.isNotEmpty ? client.email : 
            (client.phone.isNotEmpty ? client.phone : client.name)).toLowerCase();
        merged[key] = client;
      }
      
      // Add saved clients (won't overwrite if already exists from bookings)
      for (final client in savedClients) {
        final key = (client.email.isNotEmpty ? client.email : 
            (client.phone.isNotEmpty ? client.phone : client.name)).toLowerCase();
        if (!merged.containsKey(key)) {
          merged[key] = client;
        }
      }
      
      return merged.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    final mergedMyClients = mergeClients(_myClients, _savedMyClients);
    final mergedBranchClients = mergeClients(_branchClients, _savedBranchClients);

    // Update stagger controllers
    for (final c in _staggerControllers) {
      c.dispose();
    }
    _staggerControllers.clear();
    
    // For staff, only show clients who worked with them
    // For branch_admin, show branch clients or my clients based on toggle
    // For others (owner), show all clients
    final currentList = _isStaff
        ? mergedMyClients  // Staff only see their own clients
        : (_isBranchAdmin 
            ? (_showBranchClients ? mergedBranchClients : mergedMyClients)
            : _allClients);
        
    for (int i = 0; i < currentList.length; i++) {
      _staggerControllers.add(
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 600),
        ),
      );
    }

    _filterClients();
  }
  
  List<Client> _getActiveClientList() {
    // Merge saved clients with booking-derived clients
    List<Client> mergeClients(List<Client> bookingClients, List<Client> savedClients) {
      final Map<String, Client> merged = {};
      
      for (final client in bookingClients) {
        final key = (client.email.isNotEmpty ? client.email : 
            (client.phone.isNotEmpty ? client.phone : client.name)).toLowerCase();
        merged[key] = client;
      }
      
      for (final client in savedClients) {
        final key = (client.email.isNotEmpty ? client.email : 
            (client.phone.isNotEmpty ? client.phone : client.name)).toLowerCase();
        if (!merged.containsKey(key)) {
          merged[key] = client;
        }
      }
      
      return merged.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    // For staff, only show clients who worked with them
    if (_isStaff) {
      final merged = mergeClients(_myClients, _savedMyClients);
      debugPrint('Staff client list: ${merged.length} clients');
      debugPrint('  From bookings: ${_myClients.length}');
      debugPrint('  From saved: ${_savedMyClients.length}');
      return merged;
    }
    // For branch_admin, show branch clients or my clients based on toggle
    if (_isBranchAdmin) {
      return _showBranchClients 
          ? mergeClients(_branchClients, _savedBranchClients) 
          : mergeClients(_myClients, _savedMyClients);
    }
    // For others (owner), show all clients
    return _allClients;
  }

  void _startAnimations() {
    for (int i = 0; i < _filteredClients.length; i++) {
      if (i < _staggerControllers.length) {
        Future.delayed(Duration(milliseconds: 100 * i), () {
          if (mounted) _staggerControllers[i].forward();
        });
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _staggerControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  // --- Logic ---
  void _filterClients() {
    final sourceList = _getActiveClientList();
    final filtered = sourceList.where((client) {
      final query = _searchQuery.toLowerCase();
      final matchesSearch =
          client.name.toLowerCase().contains(query) ||
          client.phone.contains(_searchQuery) ||
          client.email.toLowerCase().contains(query);
      final matchesFilter =
          _currentFilter == 'all' || client.type == _currentFilter;
      return matchesSearch && matchesFilter;
    }).toList();

    // Rebuild animations for filtered list
    for (final c in _staggerControllers) {
      c.dispose();
    }
    _staggerControllers.clear();
    for (int i = 0; i < filtered.length; i++) {
      _staggerControllers.add(
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 600),
        ),
      );
    }

    setState(() {
      _filteredClients = filtered;
    });
    _startAnimations();
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;
    _filterClients();
  }

  void _onFilterChanged(String filter) {
    _currentFilter = filter;
    _filterClients();
  }
  
  void _onToggleChanged(int index) {
    setState(() {
      _showBranchClients = index == 1;
    });
    _filterClients();
  }

  // Add Client Modal
  void _showAddClientModal() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final notesController = TextEditingController();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          FontAwesomeIcons.userPlus,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add New Client',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.text,
                            ),
                          ),
                          Text(
                            'Add to your client list',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Name Field
                  _buildInputField(
                    label: 'Full Name *',
                    controller: nameController,
                    icon: FontAwesomeIcons.user,
                    placeholder: 'Enter client name',
                  ),
                  const SizedBox(height: 16),

                  // Phone Field
                  _buildInputField(
                    label: 'Phone Number',
                    controller: phoneController,
                    icon: FontAwesomeIcons.phone,
                    placeholder: 'Enter phone number',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),

                  // Email Field
                  _buildInputField(
                    label: 'Email Address',
                    controller: emailController,
                    icon: FontAwesomeIcons.envelope,
                    placeholder: 'Enter email address',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),

                  // Notes Field
                  _buildInputField(
                    label: 'Notes',
                    controller: notesController,
                    icon: FontAwesomeIcons.noteSticky,
                    placeholder: 'Any additional notes...',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey[300]!),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final name = nameController.text.trim();
                                  if (name.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please enter client name'),
                                        backgroundColor: AppColors.red,
                                      ),
                                    );
                                    return;
                                  }

                                  setModalState(() => isSaving = true);

                                  try {
                                    final user = FirebaseAuth.instance.currentUser;
                                    if (user == null) return;

                                    // Create customer document
                                    await FirebaseFirestore.instance
                                        .collection('customers')
                                        .add({
                                      'name': name,
                                      'phone': phoneController.text.trim(),
                                      'email': emailController.text.trim(),
                                      'notes': notesController.text.trim(),
                                      'ownerUid': _ownerUid,
                                      'staffId': user.uid,
                                      'branchId': _branchId ?? '',
                                      'status': 'Active',
                                      'visits': 0,
                                      'createdAt': FieldValue.serverTimestamp(),
                                      'createdBy': user.uid,
                                    });

                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('$name added successfully'),
                                          backgroundColor: AppColors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    debugPrint('Error adding client: $e');
                                    setModalState(() => isSaving = false);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Failed to add client'),
                                          backgroundColor: AppColors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Add Client',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String placeholder,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.chipBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: placeholder,
              hintStyle: TextStyle(color: AppColors.muted.withOpacity(0.7), fontSize: 14),
              prefixIcon: Icon(icon, size: 16, color: AppColors.muted),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                vertical: maxLines > 1 ? 12 : 14,
                horizontal: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final activeList = _getActiveClientList();
    final clientCount = activeList.length;
    final showAddButton = !_isBranchAdmin || !_showBranchClients;

    return SafeArea(
      child: Column(
        children: [
          // ═══════════ CREATIVE HERO HEADER ═══════════
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1A1A), Color(0xFF2D2D2D), Color(0xFF1A1A1A)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A1A1A).withOpacity(0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -20,
                  right: -20,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.03),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.15),
                            Colors.white.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: const Center(
                        child: Icon(FontAwesomeIcons.users, size: 16, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Clients',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            '$clientCount active clients',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showAddButton)
                      GestureDetector(
                        onTap: _showAddClientModal,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF3B82F6).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(FontAwesomeIcons.userPlus, color: Colors.white, size: 12),
                              SizedBox(width: 6),
                              Text(
                                'Add',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Toggle for branch admins
          if (_isBranchAdmin) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AnimatedToggle(
                backgroundColor: AppColors.card,
                values: const ['My Clients', 'Branch Clients'],
                selectedIndex: _showBranchClients ? 1 : 0,
                onChanged: _onToggleChanged,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _buildSearchAndFilter(),
          Expanded(
            child: Stack(
              children: [
                _buildClientList(),
                _buildAlphabetIndex(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Floating search bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or email...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: Icon(FontAwesomeIcons.magnifyingGlass, size: 15, color: Colors.grey.shade400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All Clients', 'all'),
                const SizedBox(width: 8),
                _filterChip('VIP', 'vip'),
                const SizedBox(width: 8),
                _filterChip('New', 'new'),
                const SizedBox(width: 8),
                _filterChip('At Risk', 'risk'),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String filterKey) {
    final isActive = _currentFilter == filterKey;
    return GestureDetector(
      onTap: () => _onFilterChanged(filterKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF333333)])
              : null,
          color: isActive ? null : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? Colors.transparent : const Color(0xFFE5E7EB),
          ),
          boxShadow: isActive
              ? [BoxShadow(color: const Color(0xFF1A1A1A).withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 3))]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildClientList() {
    final showAddButton = !_isBranchAdmin || !_showBranchClients;
    
    if (_filteredClients.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FontAwesomeIcons.users,
              size: 48,
              color: AppColors.muted.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _isBranchAdmin
                  ? (_showBranchClients ? 'No branch clients yet' : 'No clients yet')
                  : 'No clients found',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _isBranchAdmin
                    ? (_showBranchClients 
                        ? 'Clients will appear here when bookings are made at your branch'
                        : 'Add your first client or complete bookings')
                    : 'Try adjusting your search or filters',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.muted.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (showAddButton && _isBranchAdmin && !_showBranchClients) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _showAddClientModal,
                icon: const Icon(FontAwesomeIcons.userPlus, size: 14),
                label: const Text('Add Client'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _filteredClients.length,
      itemBuilder: (context, index) {
        if (index >= _staggerControllers.length) return const SizedBox();
        return FadeTransition(
          opacity: _staggerControllers[index],
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
              CurvedAnimation(parent: _staggerControllers[index], curve: Curves.easeOut),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ClientCard(client: _filteredClients[index]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlphabetIndex() {
    final letters = ['A', 'B', 'C', 'D', 'E', 'G', 'H', 'S'];
    return Positioned(
      right: 8,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 25, offset: const Offset(0, 8))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: letters
                .map((l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(l, style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.bold)),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// --- 3. Client Card Component ---
class _ClientCard extends StatelessWidget {
  final Client client;
  const _ClientCard({required this.client});

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(client.name);
    
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ClientProfilePage(client: client),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          children: [
            // Gradient top section
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _badgeColor(client.type).withOpacity(0.08),
                    Colors.white,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _badgeColor(client.type).withOpacity(0.15),
                          _badgeColor(client.type).withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _badgeColor(client.type).withOpacity(0.1)),
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: _badgeColor(client.type),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Color(0xFF1A1A1A),
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          client.phone.isNotEmpty ? client.phone : client.email,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(client.type),
                ],
              ),
            ),
            // Bottom section with details
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Icon(FontAwesomeIcons.calendarCheck, size: 11, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text(
                    '${client.visits} visits',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade500),
                  ),
                  const Spacer(),
                  Icon(FontAwesomeIcons.chevronRight, size: 11, color: Colors.grey.shade300),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _badgeColor(String type) {
    switch (type) {
      case 'vip': return const Color(0xFFF59E0B);
      case 'new': return const Color(0xFF10B981);
      case 'risk': return const Color(0xFFEF4444);
      default: return const Color(0xFF1A1A1A);
    }
  }

  Widget _buildStatusBadge(String type) {
    Color text = Colors.white;
    String label = type.toUpperCase();
    Gradient gradient;
    switch (type) {
      case 'vip':
        gradient = const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA500)]);
        text = AppColors.text;
        break;
      case 'new':
        gradient = const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]);
        break;
      case 'risk':
        gradient = const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)]);
        label = "AT RISK";
        break;
      case 'active':
      default:
        gradient = const LinearGradient(colors: [AppColors.primary, AppColors.accent]);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

