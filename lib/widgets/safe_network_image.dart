import 'package:flutter/material.dart';

/// A widget that displays a network image with built-in error handling.
/// Falls back to a placeholder when the image fails to load.
class SafeNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Color? placeholderColor;
  final IconData placeholderIcon;
  final Color? placeholderIconColor;
  final double placeholderIconSize;

  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.placeholderColor,
    this.placeholderIcon = Icons.image,
    this.placeholderIconColor,
    this.placeholderIconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder();
    }

    Widget image = Image.network(
      imageUrl!,
      width: width,
      height: height,
      fit: fit,
      // Disable caching for problematic images
      cacheWidth: width?.toInt(),
      cacheHeight: height?.toInt(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder ?? _buildLoadingPlaceholder(loadingProgress);
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('SafeNetworkImage error: $error');
        return errorWidget ?? _buildPlaceholder();
      },
      // Use gapless playback to avoid frame issues with animated images
      gaplessPlayback: true,
      // Don't filter quality for problematic images
      filterQuality: FilterQuality.medium,
    );

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: image,
      );
    }

    return image;
  }

  Widget _buildLoadingPlaceholder(ImageChunkEvent loadingProgress) {
    final progress = loadingProgress.expectedTotalBytes != null
        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
        : null;
    
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: placeholderColor ?? Colors.grey.shade200,
        borderRadius: borderRadius,
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 2,
            color: placeholderIconColor ?? Colors.grey.shade400,
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: placeholderColor ?? Colors.grey.shade200,
        borderRadius: borderRadius,
      ),
      child: Center(
        child: Icon(
          placeholderIcon,
          size: placeholderIconSize,
          color: placeholderIconColor ?? Colors.grey.shade400,
        ),
      ),
    );
  }
}

/// A CircleAvatar that handles network image errors gracefully.
class SafeCircleAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final Widget? child;
  final Color? backgroundColor;
  final IconData fallbackIcon;
  final Color? fallbackIconColor;

  const SafeCircleAvatar({
    super.key,
    this.imageUrl,
    this.radius = 20,
    this.child,
    this.backgroundColor,
    this.fallbackIcon = Icons.person,
    this.fallbackIconColor,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? Colors.grey.shade200,
        child: child ?? Icon(
          fallbackIcon,
          size: radius,
          color: fallbackIconColor ?? Colors.grey.shade400,
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Colors.grey.shade200,
      backgroundImage: NetworkImage(imageUrl!),
      onBackgroundImageError: (exception, stackTrace) {
        debugPrint('SafeCircleAvatar image error: $exception');
      },
      child: child,
    );
  }
}

/// A decoration image that handles errors for BoxDecoration.
DecorationImage? safeDecorationImage({
  required String? imageUrl,
  BoxFit fit = BoxFit.cover,
}) {
  if (imageUrl == null || imageUrl.isEmpty) {
    return null;
  }
  
  return DecorationImage(
    image: NetworkImage(imageUrl),
    fit: fit,
    onError: (exception, stackTrace) {
      debugPrint('safeDecorationImage error: $exception');
    },
  );
}

