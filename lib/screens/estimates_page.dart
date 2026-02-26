import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../widgets/safe_network_image.dart';

class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const primaryDark = Color(0xFF000000);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF8F9FA);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
}

class Estimate {
  final String id;
  final String ownerUid;
  final String workshopSlug;
  final String workshopName;
  final String? branchId;
  final String? branchName;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String vehicleMake;
  final String vehicleModel;
  final String vehicleYear;
  final String rego;
  final String mileage;
  final String description;
  final List<String> imageUrls;
  final String status;
  final dynamic createdAt;
  final dynamic updatedAt;

  Estimate({
    required this.id,
    required this.ownerUid,
    required this.workshopSlug,
    required this.workshopName,
    this.branchId,
    this.branchName,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.vehicleYear,
    required this.rego,
    this.mileage = '',
    required this.description,
    this.imageUrls = const [],
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory Estimate.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Estimate(
      id: doc.id,
      ownerUid: (d['ownerUid'] ?? '').toString(),
      workshopSlug: (d['workshopSlug'] ?? '').toString(),
      workshopName: (d['workshopName'] ?? '').toString(),
      branchId: d['branchId']?.toString(),
      branchName: d['branchName']?.toString(),
      customerName: (d['customerName'] ?? '').toString(),
      customerPhone: (d['customerPhone'] ?? '').toString(),
      customerEmail: (d['customerEmail'] ?? '').toString(),
      vehicleMake: (d['vehicleMake'] ?? '').toString(),
      vehicleModel: (d['vehicleModel'] ?? '').toString(),
      vehicleYear: (d['vehicleYear'] ?? '').toString(),
      rego: (d['rego'] ?? '').toString(),
      mileage: (d['mileage'] ?? '').toString(),
      description: (d['description'] ?? '').toString(),
      imageUrls: (d['imageUrls'] is List)
          ? (d['imageUrls'] as List).map((e) => e.toString()).toList()
          : [],
      status: (d['status'] ?? 'New').toString(),
      createdAt: d['createdAt'],
      updatedAt: d['updatedAt'],
    );
  }
}

class Reply {
  final String id;
  final String message;
  final List<String> imageUrls;
  final String? createdAt;

  Reply({
    required this.id,
    required this.message,
    this.imageUrls = const [],
    this.createdAt,
  });
}

const _apiBaseUrl = 'https://black.bmspros.com.au';

final statusConfig = {
  'New': {'bg': Color(0xFFFFF7ED), 'text': Color(0xFFB45309), 'icon': FontAwesomeIcons.wandSparkles},
  'Reviewed': {'bg': Color(0xFFEFF6FF), 'text': Color(0xFF1D4ED8), 'icon': FontAwesomeIcons.eye},
  'Quoted': {'bg': Color(0xFFECFDF5), 'text': Color(0xFF047857), 'icon': FontAwesomeIcons.check},
  'Closed': {'bg': Color(0xFFF5F5F5), 'text': Color(0xFF525252), 'icon': FontAwesomeIcons.xmark},
};

class EstimatesPage extends StatefulWidget {
  const EstimatesPage({super.key});

  @override
  State<EstimatesPage> createState() => _EstimatesPageState();
}

class _EstimatesPageState extends State<EstimatesPage> {
  String? _ownerUid;
  List<Estimate> _estimates = [];
  bool _loading = true;
  String _filterStatus = 'All';
  String? _expandedEstimateId;
  bool _updatingId = false;

  final Map<String, List<Reply>> _repliesByEstimate = {};
  String? _repliesLoadingId;
  final _replyController = TextEditingController();
  List<XFile> _replyImages = [];
  List<String> _replyImagePreviews = [];
  bool _replySending = false;
  String? _replySuccessId;
  String? _lightboxUrl;

  StreamSubscription<QuerySnapshot>? _estimatesSub;

  @override
  void initState() {
    super.initState();
    _loadUserAndEstimates();
  }

  @override
  void dispose() {
    _estimatesSub?.cancel();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAndEstimates() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    String? ownerUid = user.uid;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        final role = (userDoc.data()?['role'] ?? '').toString();
        if (role == 'branch_admin') {
          ownerUid = userDoc.data()?['ownerUid']?.toString() ?? user.uid;
        }
      }
    } catch (e) {
      debugPrint('Error loading user: $e');
    }

    setState(() {
      _ownerUid = ownerUid;
    });

    if (ownerUid == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final q = FirebaseFirestore.instance
          .collection('estimates')
          .where('ownerUid', isEqualTo: ownerUid)
          .orderBy('createdAt', descending: true);

      _estimatesSub = q.snapshots().listen((snap) {
        if (mounted) {
          setState(() {
            _estimates = snap.docs.map((d) => Estimate.fromFirestore(d)).toList();
            _loading = false;
          });
        }
      }, onError: (e) {
        debugPrint('Estimates query error: $e');
        _estimatesSub?.cancel();
        final fallbackQ = FirebaseFirestore.instance
            .collection('estimates')
            .where('ownerUid', isEqualTo: ownerUid);
        _estimatesSub = fallbackQ.snapshots().listen((snap) {
          if (mounted) {
            final list = snap.docs.map((d) => Estimate.fromFirestore(d)).toList();
            list.sort((a, b) {
              final aT = a.createdAt is Timestamp
                  ? (a.createdAt as Timestamp).toDate()
                  : DateTime(0);
              final bT = b.createdAt is Timestamp
                  ? (b.createdAt as Timestamp).toDate()
                  : DateTime(0);
              return bT.compareTo(aT);
            });
            setState(() {
              _estimates = list;
              _loading = false;
            });
          }
        });
      });
    } catch (e) {
      debugPrint('Error setting up estimates: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String id, String newStatus) async {
    setState(() => _updatingId = true);
    try {
      await FirebaseFirestore.instance.collection('estimates').doc(id).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to update status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingId = false);
    }
  }

  Future<void> _fetchReplies(String estimateId) async {
    setState(() => _repliesLoadingId = estimateId);
    try {
      final res = await http.get(
        Uri.parse('$_apiBaseUrl/api/book-now/estimate-reply?estimateId=$estimateId'),
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final list = (data['replies'] as List? ?? [])
            .map((r) => Reply(
                  id: r['id'] ?? '',
                  message: r['message'] ?? '',
                  imageUrls: (r['imageUrls'] is List)
                      ? (r['imageUrls'] as List).map((e) => e.toString()).toList()
                      : [],
                  createdAt: r['createdAt'],
                ))
            .toList();
        setState(() {
          _repliesByEstimate[estimateId] = list;
          _repliesLoadingId = null;
        });
      } else if (mounted) {
        setState(() => _repliesLoadingId = null);
      }
    } catch (e) {
      debugPrint('Failed to fetch replies: $e');
      if (mounted) setState(() => _repliesLoadingId = null);
    }
  }

  void _toggleReplies(Estimate est) {
    setState(() {
      if (_expandedEstimateId == est.id) {
        _expandedEstimateId = null;
        _replyController.clear();
        _replyImages = [];
        _replyImagePreviews = [];
      } else {
        _expandedEstimateId = est.id;
        _replyController.clear();
        _replyImages = [];
        _replyImagePreviews = [];
        _replySuccessId = null;
        if (!_repliesByEstimate.containsKey(est.id)) {
          _fetchReplies(est.id);
        }
      }
    });
  }

  Future<void> _pickReplyImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;
    final newList = [..._replyImages, ...picked].take(5).toList();
    setState(() {
      _replyImages = newList;
      _replyImagePreviews = newList.map((f) => f.path).toList();
    });
  }

  void _removeReplyImage(int idx) {
    setState(() {
      _replyImages = _replyImages.asMap().entries.where((e) => e.key != idx).map((e) => e.value).toList();
      _replyImagePreviews = _replyImagePreviews.asMap().entries.where((e) => e.key != idx).map((e) => e.value).toList();
    });
  }

  Future<void> _sendReply() async {
    final estimateId = _expandedEstimateId;
    if (estimateId == null || _ownerUid == null) return;
    final msg = _replyController.text.trim();
    if (msg.isEmpty) return;

    setState(() => _replySending = true);

    try {
      List<String> imageUrls = [];
      if (_replyImages.isNotEmpty) {
        final storage = FirebaseStorage.instance;
        for (int i = 0; i < _replyImages.length; i++) {
          final file = await _replyImages[i].readAsBytes();
          final path =
              'estimates/$estimateId/replies/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          final ref = storage.ref().child(path);
          await ref.putData(
            file,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          final url = await ref.getDownloadURL();
          imageUrls.add(url);
        }
      }

      final res = await http.post(
        Uri.parse('$_apiBaseUrl/api/book-now/estimate-reply'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'estimateId': estimateId,
          'ownerUid': _ownerUid,
          'message': msg,
          'imageUrls': imageUrls,
        }),
      );

      if (res.statusCode == 200) {
        setState(() {
          _replyController.clear();
          _replyImages = [];
          _replyImagePreviews = [];
          _replySuccessId = estimateId;
          _replySending = false;
        });
        _fetchReplies(estimateId);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _replySuccessId = null);
        });
      } else {
        final data = jsonDecode(res.body);
        throw Exception(data['error'] ?? 'Failed to send reply');
      }
    } catch (e) {
      debugPrint('Send reply error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
      setState(() => _replySending = false);
    }
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '-';
    DateTime d;
    if (ts is Timestamp) {
      d = ts.toDate();
    } else {
      try {
        d = DateTime.parse(ts.toString());
      } catch (_) {
        return '-';
      }
    }
    return DateFormat('d MMM yyyy, h:mm a').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filterStatus == 'All'
        ? _estimates
        : _estimates.where((e) => e.status == _filterStatus).toList();

    final counts = {
      'All': _estimates.length,
      'New': _estimates.where((e) => e.status == 'New').length,
      'Reviewed': _estimates.where((e) => e.status == 'Reviewed').length,
      'Quoted': _estimates.where((e) => e.status == 'Quoted').length,
      'Closed': _estimates.where((e) => e.status == 'Closed').length,
    };

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
          'Estimates',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: ['All', 'New', 'Reviewed', 'Quoted', 'Closed']
                        .map((s) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text('$s ${counts[s]! > 0 ? '(${counts[s]})' : ''}'),
                                selected: _filterStatus == s,
                                onSelected: (_) => setState(() => _filterStatus = s),
                                selectedColor: AppColors.primary,
                                labelStyle: TextStyle(
                                  color: _filterStatus == s ? Colors.white : AppColors.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(FontAwesomeIcons.fileInvoice, size: 48, color: AppColors.muted.withOpacity(0.5)),
                              const SizedBox(height: 16),
                              Text(
                                'No ${_filterStatus != 'All' ? _filterStatus.toLowerCase() : ''} estimates',
                                style: const TextStyle(color: AppColors.muted, fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final e = filtered[i];
                            final sc = statusConfig[e.status] ?? statusConfig['New']!;
                            final isExpanded = _expandedEstimateId == e.id;
                            final replies = _repliesByEstimate[e.id] ?? [];
                            final repliesLoading = _repliesLoadingId == e.id;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: AppColors.primary,
                                            child: Text(
                                              e.customerName.isNotEmpty
                                                  ? e.customerName[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  e.customerName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                    color: AppColors.text,
                                                  ),
                                                ),
                                                Text(
                                                  e.customerPhone,
                                                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: (sc['bg'] as Color).withOpacity(0.8),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              e.status,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: sc['text'] as Color,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (e.vehicleMake.isNotEmpty || e.vehicleModel.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppColors.background,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(FontAwesomeIcons.car, size: 12, color: AppColors.muted),
                                              const SizedBox(width: 6),
                                              Text(
                                                [e.vehicleYear, e.vehicleMake, e.vehicleModel]
                                                    .where((x) => x.isNotEmpty)
                                                    .join(' '),
                                                style: const TextStyle(fontSize: 13, color: AppColors.text),
                                              ),
                                              if (e.rego.isNotEmpty)
                                                Text(
                                                  ' (${e.rego})',
                                                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                                ),
                                              if (e.mileage.isNotEmpty)
                                                Text(
                                                  ' • ${e.mileage}',
                                                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Text(
                                        e.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13, color: AppColors.muted),
                                      ),
                                      if (e.imageUrls.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: e.imageUrls.asMap().entries.map((entry) {
                                            return GestureDetector(
                                              onTap: () => setState(() => _lightboxUrl = entry.value),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: SafeNetworkImage(
                                                  imageUrl: entry.value,
                                                  width: 64,
                                                  height: 64,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          if (e.branchName != null && e.branchName!.isNotEmpty)
                                            Row(
                                              children: [
                                                Icon(FontAwesomeIcons.locationDot, size: 10, color: AppColors.muted),
                                                const SizedBox(width: 4),
                                                Text(e.branchName!, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                              ],
                                            ),
                                          const Spacer(),
                                          Text(_formatDate(e.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          if (e.status == 'New')
                                            TextButton(
                                              onPressed: _updatingId
                                                  ? null
                                                  : () => _updateStatus(e.id, 'Reviewed'),
                                              child: const Text('Reviewed'),
                                            ),
                                          if (e.status == 'New' || e.status == 'Reviewed')
                                            TextButton(
                                              onPressed: _updatingId
                                                  ? null
                                                  : () => _updateStatus(e.id, 'Quoted'),
                                              child: const Text('Quoted'),
                                            ),
                                          if (e.status != 'Closed')
                                            TextButton(
                                              onPressed: _updatingId
                                                  ? null
                                                  : () => _updateStatus(e.id, 'Closed'),
                                              child: const Text('Close'),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      InkWell(
                                        onTap: () => _toggleReplies(e),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          child: Row(
                                            children: [
                                              Text(
                                                'Replies ${replies.isNotEmpty ? '(${replies.length})' : ''}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.text,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Icon(
                                                isExpanded ? FontAwesomeIcons.chevronUp : FontAwesomeIcons.chevronDown,
                                                size: 12,
                                                color: AppColors.muted,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (isExpanded) ...[
                                        if (repliesLoading)
                                          const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                                          ),
                                        if (!repliesLoading && replies.isNotEmpty)
                                          ...replies.map((r) => Container(
                                                margin: const EdgeInsets.only(bottom: 12),
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: AppColors.background,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(r.message, style: const TextStyle(height: 1.5, fontSize: 13)),
                                                    if (r.imageUrls.isNotEmpty)
                                                      Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        children: r.imageUrls.map((url) => GestureDetector(
                                                              onTap: () => setState(() => _lightboxUrl = url),
                                                              child: ClipRRect(
                                                                borderRadius: BorderRadius.circular(8),
                                                                child: SafeNetworkImage(imageUrl: url, width: 60, height: 60, fit: BoxFit.cover),
                                                              ),
                                                            )).toList(),
                                                      ),
                                                    if (r.createdAt != null)
                                                      Text(_formatDate(r.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                                  ],
                                                ),
                                              )),
                                        if (!repliesLoading && replies.isEmpty)
                                          const Padding(
                                            padding: EdgeInsets.only(bottom: 12),
                                            child: Text('No replies yet.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                                          ),
                                        if (e.status != 'Closed') ...[
                                          TextField(
                                            controller: _replyController,
                                            maxLines: 3,
                                            onChanged: (_) => setState(() {}),
                                            decoration: const InputDecoration(
                                              hintText: 'Write a reply to the customer...',
                                              border: OutlineInputBorder(),
                                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            ),
                                          ),
                                          if (_replyImagePreviews.isNotEmpty)
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: _replyImagePreviews.asMap().entries.map((entry) {
                                                return Stack(
                                                  children: [
                                                    ClipRRect(
                                                      borderRadius: BorderRadius.circular(8),
                                                      child: Image.file(
                                                        File(entry.value),
                                                        width: 64,
                                                        height: 64,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (_, __, ___) => Container(
                                                          width: 64,
                                                          height: 64,
                                                          color: AppColors.border,
                                                          child: const Icon(Icons.image),
                                                        ),
                                                      ),
                                                    ),
                                                    Positioned(
                                                      top: -4,
                                                      right: -4,
                                                      child: IconButton(
                                                        icon: const Icon(Icons.close, size: 18),
                                                        onPressed: () => _removeReplyImage(entry.key),
                                                        style: IconButton.styleFrom(
                                                          backgroundColor: Colors.red,
                                                          foregroundColor: Colors.white,
                                                          padding: const EdgeInsets.all(4),
                                                          minimumSize: Size.zero,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              }).toList(),
                                            ),
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: const Icon(FontAwesomeIcons.image, size: 20),
                                                onPressed: _pickReplyImages,
                                              ),
                                              const Spacer(),
                                              ElevatedButton(
                                                onPressed: _replySending || _replyController.text.trim().isEmpty ? null : _sendReply,
                                                child: _replySending
                                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                                    : const Text('Send Reply'),
                                              ),
                                            ],
                                          ),
                                          if (_replySuccessId == e.id)
                                            Container(
                                              margin: const EdgeInsets.only(top: 8),
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Row(
                                                children: [
                                                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Reply sent! Customer notified via email.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500, fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ],
                                    ],
                                  ),
                                ),
                              );
                          },
                        ),
                ),
              ],
            ),
          if (_lightboxUrl != null)
            GestureDetector(
              onTap: () => setState(() => _lightboxUrl = null),
              child: Container(
                color: Colors.black87,
                alignment: Alignment.center,
                child: InteractiveViewer(
                  child: SafeNetworkImage(imageUrl: _lightboxUrl!, fit: BoxFit.contain),
                ),
              ),
            ),
        ],
      ),
    );
  }

}
