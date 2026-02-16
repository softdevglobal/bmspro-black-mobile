import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../services/audit_log_service.dart';

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

// ============================================================================
// MODELS
// ============================================================================

class ServiceModel {
  final String id;
  final String name;
  final double price;
  final int duration;
  final String? imageUrl;
  final int reviews;
  final List<String> staffIds;
  final List<String> branches;

  ServiceModel({
    required this.id,
    required this.name,
    required this.price,
    required this.duration,
    this.imageUrl,
    this.reviews = 0,
    this.staffIds = const [],
    this.branches = const [],
  });

  factory ServiceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ServiceModel(
      id: doc.id,
      name: data['name'] ?? '',
      price: (data['price'] ?? 0).toDouble(),
      duration: data['duration'] ?? 0,
      imageUrl: data['imageUrl'],
      reviews: data['reviews'] ?? 0,
      staffIds: List<String>.from(data['staffIds'] ?? []),
      branches: List<String>.from(data['branches'] ?? []),
    );
  }
}

class StaffModel {
  final String id;
  final String name;
  final String role;
  final String status;

  StaffModel({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
  });
}

class BranchModel {
  final String id;
  final String name;

  BranchModel({required this.id, required this.name});
}

// ============================================================================
// SERVICES PAGE
// ============================================================================

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  String? _ownerUid;
  String? _userRole;
  List<ServiceModel> _services = [];
  List<StaffModel> _staff = [];
  List<BranchModel> _branches = [];
  bool _loading = true;

  bool get _canEdit => _userRole == 'salon_owner';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    try {
      // Get user's ownerUid and role
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      final role = userDoc.data()?['role'] ?? '';
      _userRole = role;
      String ownerUid = user.uid;
      
      if (role == 'salon_branch_admin') {
        ownerUid = userDoc.data()?['ownerUid'] ?? user.uid;
      }

      _ownerUid = ownerUid;

      // Subscribe to services
      FirebaseFirestore.instance
          .collection('services')
          .where('ownerUid', isEqualTo: ownerUid)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _services = snapshot.docs
                .map((doc) => ServiceModel.fromFirestore(doc))
                .toList();
          });
        }
      });

      // Subscribe to branches
      FirebaseFirestore.instance
          .collection('branches')
          .where('ownerUid', isEqualTo: ownerUid)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _branches = snapshot.docs.map((doc) {
              final data = doc.data();
              return BranchModel(
                id: doc.id,
                name: data['name'] ?? '',
              );
            }).toList();
          });
        }
      });

      // Subscribe to staff
      FirebaseFirestore.instance
          .collection('users')
          .where('ownerUid', isEqualTo: ownerUid)
          .snapshots()
          .listen((snapshot) {
        if (mounted) {
          setState(() {
            _staff = snapshot.docs
                .where((doc) {
                  final role = doc.data()['role'] ?? '';
                  return role == 'salon_staff' || role == 'salon_branch_admin';
                })
                .map((doc) {
                  final data = doc.data();
                  return StaffModel(
                    id: doc.id,
                    name: data['displayName'] ?? data['name'] ?? '',
                    role: data['staffRole'] ?? data['role'] ?? '',
                    status: data['status'] ?? 'Active',
                  );
                })
                .toList();
          });
        }
      });

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading data: $e');
      setState(() => _loading = false);
    }
  }

  void _showAddEditServiceSheet({ServiceModel? service}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ServiceFormSheet(
        ownerUid: _ownerUid!,
        service: service,
        branches: _branches,
        staff: _staff.where((s) => s.status == 'Active').toList(),
        onSaved: () {
          Navigator.pop(context);
          _showToast(service == null ? 'Service added!' : 'Service updated!');
        },
      ),
    );
  }

  void _confirmDelete(ServiceModel service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(FontAwesomeIcons.triangleExclamation, 
                color: Colors.red.shade600, size: 18),
            ),
            const SizedBox(width: 12),
            const Text('Delete Service?', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${service.name}"? This action cannot be undone.',
          style: const TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteService(service);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteService(ServiceModel service) async {
    try {
      // Remove from branches
      for (String branchId in service.branches) {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(branchId)
            .update({
          'serviceIds': FieldValue.arrayRemove([service.id]),
        });
      }

      // Delete service
      await FirebaseFirestore.instance
          .collection('services')
          .doc(service.id)
          .delete();

      // Create audit log
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && _ownerUid != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final userData = userDoc.data();
        final userName = userData?['displayName'] ?? userData?['name'] ?? user.email ?? 'Unknown';
        final userRole = userData?['role'] ?? 'unknown';

        await AuditLogService.logServiceDeleted(
          ownerUid: _ownerUid!,
          serviceId: service.id,
          serviceName: service.name,
          performedBy: user.uid,
          performedByName: userName,
          performedByRole: userRole,
        );
      }

      _showToast('Service deleted');
    } catch (e) {
      debugPrint('Error deleting service: $e');
      _showToast('Failed to delete service');
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(FontAwesomeIcons.circleCheck, color: Colors.white, size: 16),
            const SizedBox(width: 10),
            Text(message),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(FontAwesomeIcons.arrowLeft, size: 18, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Services',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.text,
          ),
        ),
        centerTitle: true,
        actions: [
          // Only show Add button for salon owners
          if (_canEdit)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: GestureDetector(
                onTap: () => _showAddEditServiceSheet(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEC4899).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FontAwesomeIcons.plus, color: Colors.white, size: 12),
                      SizedBox(width: 6),
                      Text(
                        'Add',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _services.isEmpty
              ? _buildEmptyState()
              : _buildServicesList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Icon(FontAwesomeIcons.scissors, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Services Yet',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _canEdit ? 'Add your first service to get started' : 'No services available',
            style: const TextStyle(fontSize: 14, color: AppColors.muted),
          ),
          if (_canEdit) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddEditServiceSheet(),
              icon: const Icon(FontAwesomeIcons.plus, size: 14),
              label: const Text('Add Service'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServicesList() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _services.length,
        itemBuilder: (context, index) {
          final service = _services[index];
          return _buildServiceCard(service);
        },
      ),
    );
  }

  Widget _buildServiceCard(ServiceModel service) {
    final branchCount = service.branches.length;
    final branchLabel = branchCount == _branches.length 
        ? 'All Branches' 
        : '$branchCount Branch${branchCount != 1 ? 'es' : ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Section with overlay
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: service.imageUrl != null && service.imageUrl!.isNotEmpty
                      ? Image.network(
                          service.imageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => _buildPlaceholderImage(),
                        )
                      : _buildPlaceholderImage(),
                ),
              ),
              // Gradient Overlay
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.5),
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // Price Badge
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEC4899), Color(0xFFA855F7)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '\$${service.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              // Service Name on image
              Positioned(
                bottom: 12,
                left: 14,
                right: 14,
                child: Text(
                  service.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Colors.black45, blurRadius: 8),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          // Content Section
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info Chips Row
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(
                      icon: FontAwesomeIcons.clock,
                      label: '${service.duration} min',
                      color: const Color(0xFF8B5CF6),
                    ),
                    _buildInfoChip(
                      icon: FontAwesomeIcons.locationDot,
                      label: branchLabel,
                      color: const Color(0xFF3B82F6),
                    ),
                    _buildInfoChip(
                      icon: FontAwesomeIcons.userGroup,
                      label: '${service.staffIds.length} staff',
                      color: const Color(0xFF10B981),
                    ),
                    if (service.reviews > 0)
                      _buildInfoChip(
                        icon: FontAwesomeIcons.solidStar,
                        label: '${service.reviews} reviews',
                        color: Colors.amber.shade600,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                // Action Buttons Row
                Row(
                  children: [
                    Expanded(
                      child: _buildCardButton(
                        icon: FontAwesomeIcons.eye,
                        label: 'Preview',
                        color: const Color(0xFF8B5CF6),
                        onTap: () => _showPreviewDialog(service),
                      ),
                    ),
                    // Only show Edit and Delete for salon owners
                    if (_canEdit) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildCardButton(
                          icon: FontAwesomeIcons.penToSquare,
                          label: 'Edit',
                          color: const Color(0xFF3B82F6),
                          onTap: () => _showAddEditServiceSheet(service: service),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildIconButton(
                        icon: FontAwesomeIcons.trash,
                        color: Colors.red.shade400,
                        onTap: () => _confirmDelete(service),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.pink.shade200,
            Colors.purple.shade200,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          FontAwesomeIcons.scissors,
          size: 40,
          color: Colors.white.withOpacity(0.7),
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }

  void _showPreviewDialog(ServiceModel service) {
    final branchNames = service.branches
        .map((id) => _branches.firstWhere((b) => b.id == id, orElse: () => BranchModel(id: '', name: 'Unknown')).name)
        .where((name) => name.isNotEmpty && name != 'Unknown')
        .toList();
    
    final staffNames = service.staffIds
        .map((id) => _staff.firstWhere((s) => s.id == id, orElse: () => StaffModel(id: '', name: 'Unknown', role: '', status: '')).name)
        .where((name) => name.isNotEmpty && name != 'Unknown')
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Header - Same as Edit
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(FontAwesomeIcons.eye, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Service Preview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Service Image Section
                  _buildPreviewSectionCard(
                    title: 'Service Image',
                    icon: FontAwesomeIcons.image,
                    iconColor: const Color(0xFF8B5CF6),
                    child: Stack(
                      children: [
                        Container(
                          width: double.infinity,
                          height: 180,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Colors.pink.shade200, Colors.purple.shade200],
                            ),
                          ),
                          child: service.imageUrl != null && service.imageUrl!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.network(service.imageUrl!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                                )
                              : Center(
                                  child: Icon(FontAwesomeIcons.scissors, size: 40, color: Colors.white.withOpacity(0.7)),
                                ),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFA855F7)]),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '\$${service.price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Service Details Section
                  _buildPreviewSectionCard(
                    title: 'Service Details',
                    icon: FontAwesomeIcons.wandMagicSparkles,
                    iconColor: const Color(0xFFEC4899),
                    child: Column(
                      children: [
                        _buildDetailRow('Service Name', service.name),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(child: _buildDetailRow('Duration', '${service.duration} mins')),
                            Expanded(child: _buildDetailRow('Price', '\$${service.price.toStringAsFixed(0)}')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Available Branches Section
                  _buildPreviewSectionCard(
                    title: 'Available Branches',
                    icon: FontAwesomeIcons.building,
                    iconColor: const Color(0xFF3B82F6),
                    child: branchNames.isEmpty
                        ? const Text('No branches assigned', style: TextStyle(color: AppColors.muted))
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: branchNames.map((name) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(FontAwesomeIcons.locationDot, size: 12, color: Color(0xFF3B82F6)),
                                  const SizedBox(width: 6),
                                  Text(name, style: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w500)),
                                ],
                              ),
                            )).toList(),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // Qualified Staff Section
                  _buildPreviewSectionCard(
                    title: 'Qualified Staff',
                    icon: FontAwesomeIcons.userCheck,
                    iconColor: const Color(0xFF10B981),
                    child: staffNames.isEmpty
                        ? const Text('No staff assigned', style: TextStyle(color: AppColors.muted))
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: staffNames.map((name) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(FontAwesomeIcons.user, size: 12, color: Color(0xFF10B981)),
                                  const SizedBox(width: 6),
                                  Text(name, style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w500)),
                                ],
                              ),
                            )).toList(),
                          ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            // Bottom Button - Only show Edit for salon owners
            if (_canEdit)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddEditServiceSheet(service: service);
                    },
                    icon: const Icon(FontAwesomeIcons.penToSquare, size: 14),
                    label: const Text('Edit Service', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              )
            else
              // Simple close button for branch admins
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: AppColors.text,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }

}

// ============================================================================
// SERVICE FORM BOTTOM SHEET
// ============================================================================

class ServiceFormSheet extends StatefulWidget {
  final String ownerUid;
  final ServiceModel? service;
  final List<BranchModel> branches;
  final List<StaffModel> staff;
  final VoidCallback onSaved;

  const ServiceFormSheet({
    super.key,
    required this.ownerUid,
    this.service,
    required this.branches,
    required this.staff,
    required this.onSaved,
  });

  @override
  State<ServiceFormSheet> createState() => _ServiceFormSheetState();
}

class _ServiceFormSheetState extends State<ServiceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  
  // Duration dropdown options (30-minute intervals)
  final List<int> _durationOptions = [30, 60, 90, 120, 150, 180, 210, 240];
  int? _selectedDuration;
  
  String? _imageUrl;
  File? _imageFile;
  bool _uploading = false;
  bool _saving = false;
  
  Set<String> _selectedBranches = {};
  Set<String> _selectedStaff = {};

  @override
  void initState() {
    super.initState();
    if (widget.service != null) {
      _nameController.text = widget.service!.name;
      _priceController.text = widget.service!.price.toStringAsFixed(0);
      // Set duration from existing service, or find closest 30-min interval
      if (_durationOptions.contains(widget.service!.duration)) {
        _selectedDuration = widget.service!.duration;
      } else {
        // Find the closest 30-minute interval
        _selectedDuration = (_durationOptions.reduce((a, b) =>
            (a - widget.service!.duration).abs() < (b - widget.service!.duration).abs() ? a : b));
      }
      _imageUrl = widget.service!.imageUrl;
      _selectedBranches = Set.from(widget.service!.branches);
      _selectedStaff = Set.from(widget.service!.staffIds);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return _imageUrl;

    setState(() => _uploading = true);

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref()
          .child('services/${widget.ownerUid}/${timestamp}.jpg');
      
      await ref.putFile(_imageFile!);
      final url = await ref.getDownloadURL();
      
      setState(() => _uploading = false);
      return url;
    } catch (e) {
      setState(() => _uploading = false);
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _saveService() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate that at least one branch is selected
    if (_selectedBranches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one branch for this service'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // Upload image if new one selected
      String? imageUrl = await _uploadImage();

      final data = {
        'name': _nameController.text.trim(),
        'price': double.parse(_priceController.text),
        'duration': _selectedDuration ?? 60,
        'imageUrl': imageUrl ?? '',
        'branches': _selectedBranches.toList(),
        'staffIds': _selectedStaff.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final user = FirebaseAuth.instance.currentUser;
      final userDoc = user != null 
          ? await FirebaseFirestore.instance.collection('users').doc(user.uid).get()
          : null;
      final userData = userDoc?.data();
      final userName = userData?['displayName'] ?? userData?['name'] ?? user?.email ?? 'Unknown';
      final userRole = userData?['role'] ?? 'unknown';

      if (widget.service == null) {
        // Create new service
        data['ownerUid'] = widget.ownerUid;
        data['createdAt'] = FieldValue.serverTimestamp();
        data['reviews'] = 0;

        final docRef = await FirebaseFirestore.instance
            .collection('services')
            .add(data);

        final serviceId = docRef.id;

        // Add to branches
        for (String branchId in _selectedBranches) {
          await FirebaseFirestore.instance
              .collection('branches')
              .doc(branchId)
              .update({
            'serviceIds': FieldValue.arrayUnion([serviceId]),
          });
        }

        // Create audit log
        if (user != null) {
          final branchNames = _selectedBranches
              .map((id) => widget.branches.firstWhere((b) => b.id == id, orElse: () => BranchModel(id: '', name: 'Unknown')).name)
              .where((name) => name.isNotEmpty && name != 'Unknown')
              .toList();

          await AuditLogService.logServiceCreated(
            ownerUid: widget.ownerUid,
            serviceId: serviceId,
            serviceName: data['name'].toString(),
            price: (data['price'] as num).toDouble(),
            performedBy: user.uid,
            performedByName: userName,
            performedByRole: userRole,
            branchNames: branchNames.isNotEmpty ? branchNames : null,
          );
        }
      } else {
        // Update existing service
        await FirebaseFirestore.instance
            .collection('services')
            .doc(widget.service!.id)
            .update(data);

        // Update branches
        final oldBranches = Set.from(widget.service!.branches);
        final newBranches = _selectedBranches;
        
        final toAdd = newBranches.difference(oldBranches);
        final toRemove = oldBranches.difference(newBranches);

        for (String branchId in toAdd) {
          await FirebaseFirestore.instance
              .collection('branches')
              .doc(branchId)
              .update({
            'serviceIds': FieldValue.arrayUnion([widget.service!.id]),
          });
        }

        for (String branchId in toRemove) {
          await FirebaseFirestore.instance
              .collection('branches')
              .doc(branchId)
              .update({
            'serviceIds': FieldValue.arrayRemove([widget.service!.id]),
          });
        }

        // Create audit log
        if (user != null) {
          final changes = <String>[];
          if (widget.service!.name != data['name']) {
            changes.add('Name: ${widget.service!.name} → ${data['name']}');
          }
          if (widget.service!.price != data['price']) {
            final newPrice = (data['price'] as num).toDouble();
            changes.add('Price: \$${widget.service!.price.toStringAsFixed(0)} → \$${newPrice.toStringAsFixed(0)}');
          }
          if (widget.service!.duration != data['duration']) {
            changes.add('Duration: ${widget.service!.duration} → ${data['duration']} mins');
          }
          if (toAdd.isNotEmpty || toRemove.isNotEmpty) {
            changes.add('Branches updated');
          }
          if (_selectedStaff.length != widget.service!.staffIds.length) {
            changes.add('Staff updated');
          }

          await AuditLogService.logServiceUpdated(
            ownerUid: widget.ownerUid,
            serviceId: widget.service!.id,
            serviceName: data['name'].toString(),
            performedBy: user.uid,
            performedByName: userName,
            performedByRole: userRole,
            changes: changes.isNotEmpty ? changes.join(', ') : null,
          );
        }
      }

      widget.onSaved();
    } catch (e) {
      debugPrint('Error saving service: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save service')),
      );
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(FontAwesomeIcons.scissors, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.service == null ? 'Add Service' : 'Edit Service',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          // Form
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Service Details Section
                  _buildSectionCard(
                    title: 'Service Details',
                    icon: FontAwesomeIcons.wandMagicSparkles,
                    iconColor: const Color(0xFFEC4899),
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: _inputDecoration('Service Name', 'e.g. Deep Tissue Massage'),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _selectedDuration,
                              decoration: _inputDecoration('Duration (mins)', ''),
                              hint: const Text('Select', style: TextStyle(fontSize: 14)),
                              items: _durationOptions.map((duration) {
                                return DropdownMenuItem<int>(
                                  value: duration,
                                  child: Text('$duration mins', style: const TextStyle(fontSize: 14)),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedDuration = value;
                                });
                              },
                              validator: (v) => v == null ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _priceController,
                              decoration: _inputDecoration('Price (\$)', '120'),
                              keyboardType: TextInputType.number,
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Image Section
                  _buildSectionCard(
                    title: 'Service Image',
                    icon: FontAwesomeIcons.image,
                    iconColor: const Color(0xFF8B5CF6),
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: double.infinity,
                          height: 160,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade300, width: 1.5, style: BorderStyle.solid),
                          ),
                          child: _imageFile != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: Image.file(_imageFile!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                                )
                              : _imageUrl != null && _imageUrl!.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(15),
                                      child: Image.network(_imageUrl!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                                    )
                                  : Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 60,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF8B5CF6).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(30),
                                            ),
                                            child: const Icon(FontAwesomeIcons.cloudArrowUp, size: 24, color: Color(0xFF8B5CF6)),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Tap to upload image',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'JPG, PNG up to 5MB',
                                            style: TextStyle(
                                              color: Colors.grey.shade400,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Branches Section
                  _buildSectionCard(
                    title: 'Available Branches',
                    icon: FontAwesomeIcons.building,
                    iconColor: const Color(0xFF3B82F6),
                    children: [
                      ...widget.branches.map((branch) => CheckboxListTile(
                        value: _selectedBranches.contains(branch.id),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedBranches.add(branch.id);
                            } else {
                              _selectedBranches.remove(branch.id);
                            }
                          });
                        },
                        title: Text(branch.name, style: const TextStyle(fontSize: 14)),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        activeColor: AppColors.primary,
                      )),
                      if (widget.branches.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No branches configured', 
                            style: TextStyle(color: AppColors.muted)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Staff Section
                  _buildSectionCard(
                    title: 'Qualified Staff',
                    icon: FontAwesomeIcons.userCheck,
                    iconColor: const Color(0xFF10B981),
                    children: [
                      ...widget.staff.map((staff) => CheckboxListTile(
                        value: _selectedStaff.contains(staff.id),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedStaff.add(staff.id);
                            } else {
                              _selectedStaff.remove(staff.id);
                            }
                          });
                        },
                        title: Text(staff.name, style: const TextStyle(fontSize: 14)),
                        subtitle: Text(staff.role, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        activeColor: AppColors.primary,
                      )),
                      if (widget.staff.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No active staff found', 
                            style: TextStyle(color: AppColors.muted)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Save Button
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving || _uploading ? null : _saveService,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving || _uploading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Saving...', style: TextStyle(color: Colors.white, fontSize: 16)),
                        ],
                      )
                    : Text(
                        widget.service == null ? 'Add Service' : 'Save Changes',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

