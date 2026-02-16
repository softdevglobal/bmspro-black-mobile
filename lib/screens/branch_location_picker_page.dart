import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../services/location_service.dart';

class AppColors {
  static const primary = Color(0xFF1A1A1A);
  static const primaryDark = Color(0xFF000000);
  static const accent = Color(0xFF333333);
  static const background = Color(0xFFF5F5F5);
  static const card = Colors.white;
  static const text = Color(0xFF1A1A1A);
  static const muted = Color(0xFF9E9E9E);
  static const border = Color(0xFFE0E0E0);
}

/// Google Maps API Key
const String _googleMapsApiKey = 'AIzaSyA2LP8ornek2rve4QBm5d9FLQKOrF78I6M';

/// Radius options for check-in
const List<Map<String, dynamic>> radiusOptions = [
  {'value': 50, 'label': '50m (Strict)'},
  {'value': 100, 'label': '100m (Default)'},
  {'value': 150, 'label': '150m'},
  {'value': 200, 'label': '200m'},
  {'value': 300, 'label': '300m'},
  {'value': 500, 'label': '500m (Relaxed)'},
];

/// Branch location data
class BranchLocationData {
  final double latitude;
  final double longitude;
  final String? formattedAddress;
  final String? placeId;
  final int allowedRadius;

  BranchLocationData({
    required this.latitude,
    required this.longitude,
    this.formattedAddress,
    this.placeId,
    required this.allowedRadius,
  });
}

/// Place prediction for autocomplete
class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final structured = json['structured_formatting'] ?? {};
    return PlacePrediction(
      placeId: json['place_id'] ?? '',
      description: json['description'] ?? '',
      mainText: structured['main_text'] ?? json['description'] ?? '',
      secondaryText: structured['secondary_text'] ?? '',
    );
  }
}

/// Page for selecting/editing branch location with Google Maps
class BranchLocationPickerPage extends StatefulWidget {
  final String? branchId; // Null for new branches
  final String branchName;
  final double? initialLatitude;
  final double? initialLongitude;
  final int initialRadius;
  final String? initialAddress;

  const BranchLocationPickerPage({
    super.key,
    this.branchId, // Optional - null when adding new branch
    required this.branchName,
    this.initialLatitude,
    this.initialLongitude,
    this.initialRadius = 100,
    this.initialAddress,
  });

  @override
  State<BranchLocationPickerPage> createState() => _BranchLocationPickerPageState();
}

class _BranchLocationPickerPageState extends State<BranchLocationPickerPage> {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  int _selectedRadius = 100;
  bool _isSaving = false;
  bool _isGettingCurrentLocation = false;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  
  // Address search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<PlacePrediction> _predictions = [];
  bool _isSearching = false;
  String? _selectedAddress;
  String? _selectedPlaceId;
  bool _showPredictions = false;

  @override
  void initState() {
    super.initState();
    _selectedRadius = widget.initialRadius;
    _selectedAddress = widget.initialAddress;
    
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLocation = LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _updateMarkerAndCircle();
    }
    
    if (widget.initialAddress != null) {
      _searchController.text = widget.initialAddress!;
    }
    
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        setState(() => _showPredictions = false);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _updateMarkerAndCircle() {
    if (_selectedLocation == null) {
      setState(() {
        _markers = {};
        _circles = {};
      });
      return;
    }

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('branch_location'),
          position: _selectedLocation!,
          draggable: true,
          onDragEnd: (newPosition) {
            _onLocationSelected(newPosition, reverseGeocode: true);
          },
          infoWindow: InfoWindow(
            title: widget.branchName,
            snippet: 'Drag to adjust location',
          ),
        ),
      };

      _circles = {
        Circle(
          circleId: const CircleId('check_in_radius'),
          center: _selectedLocation!,
          radius: _selectedRadius.toDouble(),
          strokeWidth: 2,
          strokeColor: AppColors.primary,
          fillColor: AppColors.primary.withOpacity(0.15),
        ),
      };
    });
  }

  void _onLocationSelected(LatLng position, {bool reverseGeocode = false}) {
    setState(() {
      _selectedLocation = position;
    });
    _updateMarkerAndCircle();
    
    // Animate to the new location
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(position, 17),
    );
    
    // Reverse geocode to get address
    if (reverseGeocode) {
      _reverseGeocode(position);
    }
  }

  /// Search for places using Google Places Autocomplete API
  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() {
        _predictions = [];
        _showPredictions = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&types=establishment|geocode'
        '&key=$_googleMapsApiKey'
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final predictions = (data['predictions'] as List)
              .map((p) => PlacePrediction.fromJson(p))
              .toList();
          
          setState(() {
            _predictions = predictions;
            _showPredictions = predictions.isNotEmpty;
          });
        } else {
          debugPrint('Places API error: ${data['status']}');
        }
      }
    } catch (e) {
      debugPrint('Error searching places: $e');
    } finally {
      setState(() => _isSearching = false);
    }
  }

  /// Get place details and update location
  Future<void> _selectPlace(PlacePrediction prediction) async {
    setState(() {
      _isSearching = true;
      _showPredictions = false;
    });
    
    _searchFocusNode.unfocus();

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${prediction.placeId}'
        '&fields=geometry,formatted_address,name'
        '&key=$_googleMapsApiKey'
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final result = data['result'];
          final location = result['geometry']['location'];
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;
          final formattedAddress = result['formatted_address'] ?? result['name'] ?? prediction.description;

          setState(() {
            _selectedLocation = LatLng(lat, lng);
            _selectedAddress = formattedAddress;
            _selectedPlaceId = prediction.placeId;
            _searchController.text = formattedAddress;
          });

          _updateMarkerAndCircle();
          
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(LatLng(lat, lng), 17),
          );
        }
      }
    } catch (e) {
      debugPrint('Error getting place details: $e');
      _showSnackBar('Failed to get place details', isError: true);
    } finally {
      setState(() => _isSearching = false);
    }
  }

  /// Reverse geocode coordinates to address
  Future<void> _reverseGeocode(LatLng position) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${position.latitude},${position.longitude}'
        '&key=$_googleMapsApiKey'
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final result = data['results'][0];
          setState(() {
            _selectedAddress = result['formatted_address'];
            _selectedPlaceId = result['place_id'];
            _searchController.text = result['formatted_address'];
          });
        }
      }
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingCurrentLocation = true);

    try {
      final position = await LocationService.getCurrentLocation();
      if (position != null) {
        final latLng = LatLng(position.latitude, position.longitude);
        _onLocationSelected(latLng, reverseGeocode: true);
        _showSnackBar('Location captured successfully');
      } else {
        _showSnackBar('Could not get your location', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error getting location: $e', isError: true);
    } finally {
      setState(() => _isGettingCurrentLocation = false);
    }
  }

  Future<void> _saveLocation() async {
    if (_selectedLocation == null) {
      _showSnackBar('Please select a location first', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Only save to Firestore if we have an existing branch ID
      if (widget.branchId != null && widget.branchId!.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .update({
          'location': {
            'latitude': _selectedLocation!.latitude,
            'longitude': _selectedLocation!.longitude,
            'formattedAddress': _selectedAddress,
            'placeId': _selectedPlaceId,
          },
          'allowedCheckInRadius': _selectedRadius,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _showSnackBar('Branch location saved successfully');
      }
      
      // Return the location data (for both new and existing branches)
      Navigator.pop(context, BranchLocationData(
        latitude: _selectedLocation!.latitude,
        longitude: _selectedLocation!.longitude,
        formattedAddress: _selectedAddress,
        placeId: _selectedPlaceId,
        allowedRadius: _selectedRadius,
      ));
    } catch (e) {
      _showSnackBar('Failed to save location: $e', isError: true);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? FontAwesomeIcons.circleExclamation : FontAwesomeIcons.circleCheck,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Default center (Sydney) if no initial location
    final initialCenter = widget.initialLatitude != null && widget.initialLongitude != null
        ? LatLng(widget.initialLatitude!, widget.initialLongitude!)
        : const LatLng(-33.8688, 151.2093);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(FontAwesomeIcons.arrowLeft, size: 18, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set Branch Location',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            Text(
              widget.branchName,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
        actions: [
          if (_selectedLocation != null)
            TextButton(
              onPressed: _isSaving ? null : _saveLocation,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialCenter,
              zoom: widget.initialLatitude != null ? 17 : 12,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              if (_selectedLocation != null) {
                _updateMarkerAndCircle();
              }
            },
            onTap: (position) {
              _onLocationSelected(position, reverseGeocode: true);
            },
            markers: _markers,
            circles: _circles,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Search Bar at top
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // Search Input
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: Icon(FontAwesomeIcons.magnifyingGlass, 
                          color: AppColors.muted, size: 16),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: (value) {
                            _searchPlaces(value);
                          },
                          onTap: () {
                            if (_predictions.isNotEmpty) {
                              setState(() => _showPredictions = true);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Search for an address...',
                            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(FontAwesomeIcons.xmark, size: 14),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _predictions = [];
                                        _showPredictions = false;
                                      });
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                      if (_isSearching)
                        const Padding(
                          padding: EdgeInsets.only(right: 16),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      // Current Location Button
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: Material(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: _isGettingCurrentLocation ? null : _getCurrentLocation,
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: _isGettingCurrentLocation
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(FontAwesomeIcons.crosshairs, 
                                      color: AppColors.primary, size: 18),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Predictions dropdown
                if (_showPredictions && _predictions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 250),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _predictions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final prediction = _predictions[index];
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(FontAwesomeIcons.locationDot, 
                              color: AppColors.primary, size: 14),
                          ),
                          title: Text(
                            prediction.mainText,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            prediction.secondaryText,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _selectPlace(prediction),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Instructions Banner (shown when no location selected)
          if (_selectedLocation == null && !_showPredictions)
            Positioned(
              top: 90,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(FontAwesomeIcons.circleInfo, 
                      color: Colors.amber.shade700, size: 16),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Search, use current location, or tap the map',
                        style: TextStyle(fontSize: 12, color: AppColors.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Location Info
                      if (_selectedLocation != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(FontAwesomeIcons.locationDot, 
                                  color: Colors.green.shade700, size: 16),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedAddress ?? 'Location Selected',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                        fontSize: 13,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green.shade600,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(FontAwesomeIcons.xmark, 
                                  color: Colors.green.shade400, size: 14),
                                onPressed: () {
                                  setState(() {
                                    _selectedLocation = null;
                                    _selectedAddress = null;
                                    _selectedPlaceId = null;
                                    _searchController.clear();
                                  });
                                  _updateMarkerAndCircle();
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Radius Selector
                      const Text(
                        'Check-in Radius',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Staff must be within this distance to check in',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: radiusOptions.map((option) {
                          final isSelected = _selectedRadius == option['value'];
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedRadius = option['value'];
                              });
                              _updateMarkerAndCircle();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Text(
                                option['label'],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : AppColors.text,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: (_selectedLocation == null || _isSaving) ? null : _saveLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          child: _isSaving
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Saving...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  ],
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(FontAwesomeIcons.floppyDisk, size: 16),
                                    SizedBox(width: 12),
                                    Text('Save Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
