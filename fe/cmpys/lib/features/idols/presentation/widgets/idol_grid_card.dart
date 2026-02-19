import 'package:flutter/material.dart';
import '../../../../app/design_tokens.dart';
import '../../models/idol_models.dart';

class IdolGridCard extends StatelessWidget {
  const IdolGridCard({
    super.key,
    required this.idol,
    required this.onTap,
    this.isSelected = false,
  });

  final IdolCandidate idol;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadii.br16,
          border: isSelected 
             ? Border.all(color: AppColors.primary, width: 2)
             : Border.all(color: AppColors.cardBorder),
          boxShadow: isSelected ? AppShadows.glowLime : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image
            if (idol.avatarThumbUrl != null)
              Image.network(
                idol.avatarThumbUrl!,
                fit: BoxFit.cover,
                color: isSelected ? null : Colors.black.withOpacity(0.2), // Less dim
                colorBlendMode: isSelected ? null : BlendMode.darken,
              )
            else
              Container(color: AppColors.surfaceHighlight),
            
            // Gradient Overlay
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black54,
                    Colors.black87,
                  ],
                  stops: [0.5, 0.8, 1.0],
                ),
              ),
            ),

            // Text content
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    idol.name,
                    style: AppTypography.h4.copyWith(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (idol.occupations.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      idol.occupations.first,
                      style: AppTypography.caption.copyWith(color: AppColors.secondary), // Purple
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            
            // Selection Indicator
            if (isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.black),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
