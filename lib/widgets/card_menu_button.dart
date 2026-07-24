import 'package:flutter/material.dart';

import '../config/constants.dart';

enum _CardAction { edit, delete }

/// Small 3-dots menu that sits in the top-right corner of a selector card
/// (DCM / Station / Customer / Part / Line). Tapping it opens a dropdown with
/// Edit and Delete. Overlaid on the card in a Stack, so it intercepts taps in
/// its own corner while the rest of the card still triggers its onTap.
class CardMenuButton extends StatelessWidget {
  const CardMenuButton({
    super.key,
    required this.onEdit,
    required this.onDelete,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_CardAction>(
      tooltip: 'Options',
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      color: AppColors.surface,
      iconColor: AppColors.textSecondary,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 160),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (action) {
        if (action == _CardAction.edit) {
          onEdit();
        } else {
          onDelete();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_CardAction>(
          value: _CardAction.edit,
          child: Row(
            children: [
              const Icon(
                Icons.edit_rounded,
                size: 19,
                color: AppColors.steelBlue,
              ),
              const SizedBox(width: 12),
              Text(
                'Edit',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<_CardAction>(
          value: _CardAction.delete,
          child: Row(
            children: const [
              Icon(
                Icons.delete_outline_rounded,
                size: 19,
                color: AppColors.danger,
              ),
              SizedBox(width: 12),
              Text(
                'Delete',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
