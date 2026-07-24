import 'package:flutter/material.dart';

import '../config/constants.dart';

/// Branded app bar: real HICOM logo, deep-purple gradient header, amber
/// accent underline. Shown on every screen; [subtitle] names the current
/// screen (e.g. "Casting — Machines"). [actions] adds trailing icon buttons
/// (e.g. a settings/manage gear) next to the back button side.
class HicomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HicomAppBar({super.key, this.subtitle, this.actions});

  final String? subtitle;
  final List<Widget>? actions;

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 78 : 98);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Material(
      color: AppColors.navy,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.navy, AppColors.navyDark],
            ),
            border: Border(
              bottom: BorderSide(color: AppColors.amber, width: 3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (canPop)
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, size: 26),
                  color: Colors.white,
                  tooltip: 'Back',
                )
              else
                const SizedBox(width: 14),
              Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Image.asset('assets/logo.png', fit: BoxFit.contain),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: const [
                          Text(
                            'HICOM',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 1.5,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'DIECASTINGS',
                            style: TextStyle(
                              color: AppColors.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.6,
                            ),
                          ),
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Color(0xFFC9C4E8),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (actions != null)
                ...actions!.map(
                  (action) => IconTheme(
                    data: const IconThemeData(color: Colors.white),
                    child: action,
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
