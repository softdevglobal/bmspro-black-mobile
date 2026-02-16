import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';

class AuditLogService {
  static const String _baseUrl = 'https://black.bmspros.com.au/api/audit-log';

  static Future<bool> createAuditLog({
    required String ownerUid,
    required String action,
    required String actionType, // 'create', 'update', 'delete', 'status_change', etc.
    required String entityType, // 'service', 'staff', 'branch', etc.
    required String performedBy,
    String? entityId,
    String? entityName,
    String? performedByName,
    String? performedByRole,
    String? details,
    String? previousValue,
    String? newValue,
    String? branchId,
    String? branchName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Get Firebase auth token for authentication
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('Audit log failed: No authenticated user');
        return false;
      }

      final token = await user.getIdToken();
      
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'ownerUid': ownerUid,
          'action': action,
          'actionType': actionType,
          'entityType': entityType,
          'performedBy': performedBy,
          if (entityId != null) 'entityId': entityId,
          if (entityName != null) 'entityName': entityName,
          if (performedByName != null) 'performedByName': performedByName,
          if (performedByRole != null) 'performedByRole': performedByRole,
          if (details != null) 'details': details,
          if (previousValue != null) 'previousValue': previousValue,
          if (newValue != null) 'newValue': newValue,
          if (branchId != null) 'branchId': branchId,
          if (branchName != null) 'branchName': branchName,
          if (metadata != null) 'metadata': metadata,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print('Audit log failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error creating audit log: $e');
      return false;
    }
  }

  // Helper methods for common actions
  static Future<bool> logServiceCreated({
    required String ownerUid,
    required String serviceId,
    required String serviceName,
    required double price,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
    List<String>? branchNames,
  }) {
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Service created: $serviceName',
      actionType: 'create',
      entityType: 'service',
      entityId: serviceId,
      entityName: serviceName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      details: 'Price: \$${price.toStringAsFixed(2)}${branchNames != null && branchNames.isNotEmpty ? ', Branches: ${branchNames.join(", ")}' : ""}',
    );
  }

  static Future<bool> logServiceUpdated({
    required String ownerUid,
    required String serviceId,
    required String serviceName,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
    String? changes,
  }) {
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Service updated: $serviceName',
      actionType: 'update',
      entityType: 'service',
      entityId: serviceId,
      entityName: serviceName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      details: changes,
    );
  }

  static Future<bool> logServiceDeleted({
    required String ownerUid,
    required String serviceId,
    required String serviceName,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
  }) {
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Service deleted: $serviceName',
      actionType: 'delete',
      entityType: 'service',
      entityId: serviceId,
      entityName: serviceName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
    );
  }

  static Future<bool> logBranchCreated({
    required String ownerUid,
    required String branchId,
    required String branchName,
    required String address,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
  }) {
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Branch created: $branchName',
      actionType: 'create',
      entityType: 'branch',
      entityId: branchId,
      entityName: branchName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      details: 'Address: $address',
      branchId: branchId,
      branchName: branchName,
    );
  }

  static Future<bool> logBranchUpdated({
    required String ownerUid,
    required String branchId,
    required String branchName,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
    String? changes,
  }) {
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Branch updated: $branchName',
      actionType: 'update',
      entityType: 'branch',
      entityId: branchId,
      entityName: branchName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      details: changes,
      branchId: branchId,
      branchName: branchName,
    );
  }

  static Future<bool> logBranchDeleted({
    required String ownerUid,
    required String branchId,
    required String branchName,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
  }) {
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Branch deleted: $branchName',
      actionType: 'delete',
      entityType: 'branch',
      entityId: branchId,
      entityName: branchName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
    );
  }

  static Future<bool> logBranchAdminAssigned({
    required String ownerUid,
    required String branchId,
    required String branchName,
    required String adminId,
    required String adminName,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
  }) {
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Branch admin assigned: $adminName to $branchName',
      actionType: 'update',
      entityType: 'branch',
      entityId: branchId,
      entityName: branchName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      details: 'Admin: $adminName ($adminId)',
      branchId: branchId,
      branchName: branchName,
    );
  }

  static Future<bool> logStaffCreated({
    required String ownerUid,
    required String staffId,
    required String staffName,
    required String staffRole,
    required String branchName,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
  }) {
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Staff member created: $staffName',
      actionType: 'create',
      entityType: 'staff',
      entityId: staffId,
      entityName: staffName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      details: 'Role: $staffRole, Branch: $branchName',
      branchName: branchName,
    );
  }

  static Future<bool> logStaffUpdated({
    required String ownerUid,
    required String staffId,
    required String staffName,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
    String? changes,
  }) {
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Staff member updated: $staffName',
      actionType: 'update',
      entityType: 'staff',
      entityId: staffId,
      entityName: staffName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      details: changes,
    );
  }

  static Future<bool> logStaffDeleted({
    required String ownerUid,
    required String staffId,
    required String staffName,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
  }) {
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Staff member deleted: $staffName',
      actionType: 'delete',
      entityType: 'staff',
      entityId: staffId,
      entityName: staffName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
    );
  }

  static Future<bool> logStaffStatusChanged({
    required String ownerUid,
    required String staffId,
    required String staffName,
    required String previousStatus,
    required String newStatus,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
  }) {
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Staff member status changed: $staffName',
      actionType: 'status_change',
      entityType: 'staff',
      entityId: staffId,
      entityName: staffName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      previousValue: previousStatus,
      newValue: newStatus,
    );
  }

  static Future<bool> logUserLogin({
    String? ownerUid,
    String? performedBy,
    String? performedByName,
    String? performedByRole,
    String? branchId,
    String? branchName,
  }) {
    if (ownerUid == null || performedBy == null) {
      return Future.value(false);
    }
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'User logged in',
      actionType: 'login',
      entityType: 'auth',
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      branchId: branchId,
      branchName: branchName,
      details: branchName != null ? 'Logged in to branch: $branchName' : null,
    );
  }

  static Future<bool> logUserLogout({
    String? ownerUid,
    String? performedBy,
    String? performedByName,
    String? performedByRole,
  }) {
    if (ownerUid == null || performedBy == null) {
      return Future.value(false);
    }
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'User logged out',
      actionType: 'logout',
      entityType: 'auth',
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
    );
  }

  static Future<bool> logPasswordChanged({
    String? ownerUid,
    String? userId,
    String? userName,
    String? performedByRole,
  }) {
    if (ownerUid == null || userId == null) {
      return Future.value(false);
    }
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Password changed: ${userName ?? "User"}',
      actionType: 'update',
      entityType: 'auth',
      entityId: userId,
      entityName: userName ?? 'User',
      performedBy: userId,
      performedByName: userName,
      performedByRole: performedByRole,
      details: 'User changed their account password',
    );
  }

  static Future<bool> logProfilePictureChanged({
    String? ownerUid,
    String? userId,
    String? userName,
    String? performedByRole,
    required String pictureType, // 'logo' or 'avatar'
  }) {
    if (ownerUid == null || userId == null) {
      return Future.value(false);
    }
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Profile $pictureType changed: ${userName ?? "User"}',
      actionType: 'update',
      entityType: 'user_profile',
      entityId: userId,
      entityName: userName ?? 'User',
      performedBy: userId,
      performedByName: userName,
      performedByRole: performedByRole,
      details: 'User changed their profile $pictureType',
    );
  }

  static Future<bool> logBookingStatusChanged({
    String? ownerUid,
    required String bookingId,
    String? bookingCode,
    String? clientName,
    required String previousStatus,
    required String newStatus,
    String? performedBy,
    String? performedByName,
    String? performedByRole,
    String? details,
    String? branchName,
  }) {
    if (ownerUid == null || performedBy == null) {
      return Future.value(false);
    }
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Booking status changed: $previousStatus → $newStatus',
      actionType: 'status_change',
      entityType: 'booking',
      entityId: bookingId,
      entityName: bookingCode ?? 'Booking for ${clientName ?? "Customer"}',
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      previousValue: previousStatus,
      newValue: newStatus,
      details: details,
      branchName: branchName,
    );
  }

  static Future<bool> logStaffCheckIn({
    String? ownerUid,
    required String checkInId,
    required String staffId,
    required String staffName,
    required String branchId,
    required String branchName,
    String? performedBy,
    String? performedByName,
    String? performedByRole,
    String? details,
  }) {
    if (ownerUid == null || performedBy == null) {
      return Future.value(false);
    }
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Staff checked in',
      actionType: 'create',
      entityType: 'staff_check_in',
      entityId: checkInId,
      entityName: staffName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      branchId: branchId,
      branchName: branchName,
      details: details ?? 'Checked in at $branchName',
    );
  }

  static Future<bool> logStaffCheckOut({
    String? ownerUid,
    required String checkInId,
    required String staffId,
    required String staffName,
    required String branchId,
    required String branchName,
    String? performedBy,
    String? performedByName,
    String? performedByRole,
    String? hoursWorked,
  }) {
    if (ownerUid == null || performedBy == null) {
      return Future.value(false);
    }
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Staff checked out',
      actionType: 'update',
      entityType: 'staff_check_in',
      entityId: checkInId,
      entityName: staffName,
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      branchId: branchId,
      branchName: branchName,
      details: hoursWorked != null 
          ? 'Checked out from $branchName. Hours worked: $hoursWorked'
          : 'Checked out from $branchName',
    );
  }

  static Future<bool> logWalkInBookingCreated({
    String? ownerUid,
    required String bookingId,
    String? bookingCode,
    required String clientName,
    required String serviceName,
    required String performedBy,
    String? performedByName,
    String? performedByRole,
    String? branchId,
    String? branchName,
    String? bookingDate,
    String? bookingTime,
    double? price,
    int? duration,
    String? notes,
    String? bookingSource,
    String? clientEmail,
    String? clientPhone,
    String? staffName,
  }) {
    if (ownerUid == null || performedBy == null) {
      return Future.value(false);
    }
    
    // Build comprehensive details string
    String details = 'Client: $clientName, Service: $serviceName';
    if (staffName != null && staffName.isNotEmpty && staffName != 'Any Available') {
      details += ', Staff: $staffName';
    }
    if (price != null && price > 0) {
      details += ', Price: \$${price.toStringAsFixed(2)}';
    }
    if (duration != null && duration > 0) {
      details += ', Duration: $duration mins';
    }
    if (bookingDate != null && bookingTime != null) {
      details += ', Date/Time: $bookingDate $bookingTime';
    }
    if (notes != null && notes.trim().isNotEmpty) {
      details += ', Notes: ${notes.trim()}';
    }
    if (bookingSource != null && bookingSource.isNotEmpty) {
      details += ', Source: $bookingSource';
    }
    
    // Build metadata map
    Map<String, dynamic>? metadata;
    if (price != null || duration != null || notes != null || bookingSource != null || clientEmail != null || clientPhone != null) {
      metadata = <String, dynamic>{};
      if (price != null) metadata!['price'] = price;
      if (duration != null) metadata!['duration'] = duration;
      if (notes != null && notes.trim().isNotEmpty) metadata!['notes'] = notes.trim();
      if (bookingSource != null) metadata!['bookingSource'] = bookingSource;
      if (clientEmail != null && clientEmail.isNotEmpty) metadata!['clientEmail'] = clientEmail;
      if (clientPhone != null && clientPhone.isNotEmpty) metadata!['clientPhone'] = clientPhone;
      if (staffName != null && staffName.isNotEmpty) metadata!['staffName'] = staffName;
    }
    
    return createAuditLog(
      ownerUid: ownerUid,
      action: 'Booking created for $clientName',
      actionType: 'create',
      entityType: 'booking',
      entityId: bookingId,
      entityName: bookingCode ?? 'Booking for $clientName',
      performedBy: performedBy,
      performedByName: performedByName,
      performedByRole: performedByRole,
      branchId: branchId,
      branchName: branchName,
      details: details,
      metadata: metadata,
    );
  }
}
