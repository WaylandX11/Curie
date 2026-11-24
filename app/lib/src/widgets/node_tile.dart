import 'package:material_ui/material_ui.dart';

import '../models/profile.dart';
import '../services/country.dart';
import '../services/ping.dart';
import '../theme.dart';

/// Строка узла: флаг, имя, протоколы и задержка — как в привычных клиентах.
class NodeTile extends StatelessWidget {
  const NodeTile({
    super.key,
    required this.profile,
    required this.selected,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final Profile profile;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = Country.of(profile);
    final name = Country.cleanName(profile.name);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? theme.colorScheme.primary.withValues(alpha: 0.7) : Colors.transparent,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Text(
                  code == null ? '🏳️' : Country.flag(code),
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? profile.name : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (profile.chips.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            profile.chips.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (trailing != null)
                  trailing!
                else
                  _PingBadge(profileId: profile.id),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PingBadge extends StatelessWidget {
  const _PingBadge({required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([Ping.results, Ping.pending]),
      builder: (context, _) {
        final result = Ping.results.value[profileId];
        if (Ping.pending.value.contains(profileId)) {
          return const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        if (result == null) {
          return _chip(
            '—',
            theme.colorScheme.onSurfaceVariant,
            theme.colorScheme.onSurface.withValues(alpha: 0.06),
          );
        }
        if (!result.ok) {
          return _chip(
            'n/a',
            theme.colorScheme.error,
            theme.colorScheme.error.withValues(alpha: 0.12),
          );
        }
        final ms = result.ms!;
        final foreground = ms < 150
            ? curieGood(theme)
            : ms < 300
                ? const Color(0xFFFFD166)
                : theme.colorScheme.error;
        return _chip('$ms ms', foreground, foreground.withValues(alpha: 0.12));
      },
    );
  }

  /// Компактная «плашка» задержки: цвет показывает качество связи, как в Happ.
  static Widget _chip(String label, Color foreground, Color background) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
