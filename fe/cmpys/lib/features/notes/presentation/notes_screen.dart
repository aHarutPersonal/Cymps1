import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../../app/assets.dart';
import '../../../app/design_tokens.dart';
import '../../../core/ui/cmpys_button.dart';
import '../../../core/ui/cmpys_card.dart';
import '../../../core/ui/cmpys_chip.dart';
import '../../../core/ui/cmpys_text_field.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/loading_state.dart';
import '../controllers/notes_controller.dart';
import '../models/note_models.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load notes on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notesControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await ref.read(notesControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(notesControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: AppSpacing.screenH,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.s8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Data Ledger', style: AppTypography.h1),
                      CmpysIconButton(
                        icon: AppAssets.iconFilter,
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  _buildSubtitle(notesState),
                  const SizedBox(height: AppSpacing.s16),
                  CmpysSearchField(
                    controller: _searchController,
                    hint: 'Search notes...',
                    onChanged: (value) {
                      ref.read(notesControllerProvider.notifier).search(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            // Content
            Expanded(
              child: _buildBody(notesState),
            ),
          ],
        ),
      ),
      floatingActionButton: CmpysFab(
        icon: AppAssets.iconPlus,
        onPressed: () => _showAddNote(context),
      ),
    );
  }

  Widget _buildSubtitle(NotesState state) {
    final count = switch (state) {
      NotesLoaded(:final totalCount) => totalCount ?? 0,
      _ => 0,
    };

    return Text(
      '$count notes',
      style: AppTypography.caption.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildBody(NotesState state) {
    return switch (state) {
      NotesInitial() || NotesLoading() => const LoadingState(
          message: 'Loading your notes...',
        ),
      NotesError(:final message) => _buildErrorState(message),
      NotesLoaded(:final notes, :final query) => _buildNotesList(notes, query),
    };
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              AppAssets.iconAlertCircle,
              width: 48,
              height: 48,
              colorFilter: const ColorFilter.mode(
                AppColors.error,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              'Failed to load notes',
              style: AppTypography.h3,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              message,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s24),
            CmpysButton(
              label: 'Try Again',
              onPressed: () => ref.read(notesControllerProvider.notifier).load(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesList(List<Note> notes, String query) {
    // Empty state
    if (notes.isEmpty) {
      if (query.isNotEmpty) {
        return NoResultsState(
          query: query,
          onClear: () {
            _searchController.clear();
            ref.read(notesControllerProvider.notifier).load();
          },
        );
      }
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: AppSpacing.s24,
          right: AppSpacing.s24,
          bottom: AppSpacing.s100,
        ),
        itemCount: notes.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
        itemBuilder: (context, index) {
          return _NoteCard(
            note: notes[index],
            onTap: () => _openNoteDetail(notes[index]),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadii.br16,
              ),
              child: Center(
                child: SvgPicture.asset(
                  AppAssets.iconFileText,
                  width: 32,
                  height: 32,
                  colorFilter: const ColorFilter.mode(
                    AppColors.textTertiary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            Text(
              'No notes yet',
              style: AppTypography.h3,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Capture your thoughts, reflections,\nand learnings',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s24),
            CmpysButton(
              label: 'Create First Note',
              icon: AppAssets.iconPlus,
              onPressed: () => _showAddNote(context),
              isExpanded: false,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddNote(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AddNoteScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  void _openNoteDetail(Note note) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NoteDetailScreen(noteId: note.id),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onTap,
  });

  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CmpysCard(
      onTap: onTap,
      padding: AppSpacing.p16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  note.title ?? 'Untitled',
                  style: AppTypography.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatDate(note.createdAt),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            note.content,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (note.attachments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            _buildAttachmentBadge(note.attachments!.first),
          ],
        ],
      ),
    );
  }

  Widget _buildAttachmentBadge(NoteAttachment attachment) {
    String label;
    if (attachment.idolId != null) {
      label = 'Linked to idol';
    } else if (attachment.planItemId != null) {
      label = 'Linked to plan';
    } else if (attachment.achievementId != null) {
      label = 'Linked to achievement';
    } else {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        SvgPicture.asset(
          AppAssets.iconLink,
          width: 12,
          height: 12,
          colorFilter: const ColorFilter.mode(
            AppColors.accent,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: AppSpacing.s4),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('M/d').format(date);
  }
}

// Add Note Screen
class AddNoteScreen extends ConsumerStatefulWidget {
  const AddNoteScreen({super.key});

  @override
  ConsumerState<AddNoteScreen> createState() => _AddNoteScreenState();
}

class _AddNoteScreenState extends ConsumerState<AddNoteScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _contentController.text.trim().isNotEmpty && !_isSaving;

  Future<void> _saveNote() async {
    if (!_canSave) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(notesControllerProvider.notifier).createNote(
            title: _titleController.text.trim().isEmpty
                ? null
                : _titleController.text.trim(),
            content: _contentController.text.trim(),
          );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          icon: SvgPicture.asset(
            AppAssets.iconX,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(
              _isSaving ? AppColors.textTertiary : AppColors.textPrimary,
              BlendMode.srcIn,
            ),
          ),
        ),
        title: Text('New Note', style: AppTypography.h3),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.s16),
            child: CmpysButton(
              label: 'Save',
              size: CmpysButtonSize.small,
              isExpanded: false,
              isLoading: _isSaving,
              onPressed: _canSave ? _saveNote : null,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: AppSpacing.s24,
              right: AppSpacing.s24,
              bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.s32,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Error banner
                if (_errorMessage != null) ...[
                  _ErrorBanner(
                    message: _errorMessage!,
                    onDismiss: () => setState(() => _errorMessage = null),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                ],
                const SizedBox(height: AppSpacing.s16),
                CmpysTextField(
                  controller: _titleController,
                  label: 'Title (optional)',
                  hint: 'Enter note title...',
                  enabled: !_isSaving,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.s20),
                CmpysTextArea(
                  controller: _contentController,
                  label: 'Content',
                  hint: 'Write your thoughts...',
                  minLines: 8,
                  maxLines: 12,
                  enabled: !_isSaving,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.s32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Note Detail Screen
class NoteDetailScreen extends ConsumerStatefulWidget {
  const NoteDetailScreen({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<NoteDetailScreen> {
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isDeleting = false;

  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final noteAsync = ref.watch(noteDetailProvider(widget.noteId));

    return noteAsync.when(
      loading: () => Scaffold(
        appBar: _buildAppBar(null),
        body: const LoadingState(message: 'Loading note...'),
      ),
      error: (error, _) => Scaffold(
        appBar: _buildAppBar(null),
        body: _buildErrorBody(error.toString()),
      ),
      data: (note) => _buildContent(note),
    );
  }

  Widget _buildContent(Note note) {
    // Initialize controllers if not editing
    if (!_isEditing) {
      _titleController.text = note.title ?? '';
      _contentController.text = note.content;
    }

    return Scaffold(
      appBar: _buildAppBar(note),
      body: _isEditing ? _buildEditMode(note) : _buildViewMode(note),
    );
  }

  AppBar _buildAppBar(Note? note) {
    return AppBar(
      backgroundColor: AppColors.bg,
      leading: IconButton(
        onPressed: () {
          if (_isEditing) {
            setState(() => _isEditing = false);
          } else {
            Navigator.pop(context);
          }
        },
        icon: SvgPicture.asset(
          _isEditing ? AppAssets.iconX : AppAssets.iconChevronLeft,
          width: 24,
          height: 24,
          colorFilter: const ColorFilter.mode(
            AppColors.textPrimary,
            BlendMode.srcIn,
          ),
        ),
      ),
      title: _isEditing ? Text('Edit Note', style: AppTypography.h3) : null,
      actions: note != null
          ? [
              if (_isEditing)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.s8),
                  child: CmpysButton(
                    label: 'Save',
                    size: CmpysButtonSize.small,
                    isExpanded: false,
                    isLoading: _isSaving,
                    onPressed: _isSaving ? null : () => _saveNote(note),
                  ),
                )
              else ...[
                IconButton(
                  onPressed: () => setState(() => _isEditing = true),
                  icon: SvgPicture.asset(
                    AppAssets.iconEdit,
                    width: 20,
                    height: 20,
                    colorFilter: const ColorFilter.mode(
                      AppColors.textSecondary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _showDeleteConfirm(note),
                  icon: SvgPicture.asset(
                    AppAssets.iconTrash,
                    width: 20,
                    height: 20,
                    colorFilter: const ColorFilter.mode(
                      AppColors.error,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
              ],
            ]
          : null,
    );
  }

  Widget _buildViewMode(Note note) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: AppSpacing.s24,
        right: AppSpacing.s24,
        bottom: AppSpacing.s48,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.s8),
          Text(note.title ?? 'Untitled', style: AppTypography.h2),
          const SizedBox(height: AppSpacing.s8),
          Row(
            children: [
              SvgPicture.asset(
                AppAssets.iconCalendar,
                width: 14,
                height: 14,
                colorFilter: const ColorFilter.mode(
                  AppColors.textTertiary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(
                _formatFullDate(note.createdAt),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              if (note.updatedAt != note.createdAt) ...[
                const SizedBox(width: AppSpacing.s12),
                Text(
                  '• Edited',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.s24),
          const Divider(color: AppColors.border),
          const SizedBox(height: AppSpacing.s24),
          Text(
            note.content,
            style: AppTypography.bodyLarge.copyWith(
              height: 1.7,
              color: AppColors.textSecondary,
            ),
          ),
          // Attachments
          if (note.attachments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s32),
            _buildAttachments(note.attachments!),
          ],
          const SizedBox(height: AppSpacing.s48),
        ],
      ),
    );
  }

  Widget _buildEditMode(Note note) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: AppSpacing.s24,
          right: AppSpacing.s24,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.s32,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.s16),
            CmpysTextField(
              controller: _titleController,
              label: 'Title',
              hint: 'Enter note title...',
              enabled: !_isSaving,
            ),
            const SizedBox(height: AppSpacing.s20),
            CmpysTextArea(
              controller: _contentController,
              label: 'Content',
              hint: 'Write your thoughts...',
              minLines: 10,
              maxLines: 20,
              enabled: !_isSaving,
            ),
            const SizedBox(height: AppSpacing.s32),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachments(List<NoteAttachment> attachments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attachments',
          style: AppTypography.label.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s12),
        ...attachments.map((attachment) => _AttachmentCard(attachment: attachment)),
      ],
    );
  }

  Widget _buildErrorBody(String message) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              AppAssets.iconAlertCircle,
              width: 48,
              height: 48,
              colorFilter: const ColorFilter.mode(
                AppColors.error,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Text('Failed to load note', style: AppTypography.h3),
            const SizedBox(height: AppSpacing.s8),
            Text(
              message,
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s24),
            CmpysButton(
              label: 'Go Back',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveNote(Note note) async {
    setState(() => _isSaving = true);

    try {
      await ref.read(notesControllerProvider.notifier).updateNote(
            note.id,
            title: _titleController.text.trim().isEmpty
                ? null
                : _titleController.text.trim(),
            content: _contentController.text.trim(),
          );

      // Refresh the detail provider
      ref.invalidate(noteDetailProvider(widget.noteId));

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isEditing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showDeleteConfirm(Note note) {
    showDialog(
      context: context,
      builder: (context) => _DeleteConfirmDialog(
        noteTitle: note.title ?? 'this note',
        onConfirm: () => _deleteNote(note),
        isDeleting: _isDeleting,
      ),
    );
  }

  Future<void> _deleteNote(Note note) async {
    setState(() => _isDeleting = true);

    try {
      await ref.read(notesControllerProvider.notifier).deleteNote(note.id);

      if (mounted) {
        Navigator.pop(context); // Close dialog
        Navigator.pop(context); // Close detail screen
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _formatFullDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }
}

/// Attachment card widget
class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.attachment});

  final NoteAttachment attachment;

  @override
  Widget build(BuildContext context) {
    String label;
    String icon;

    if (attachment.idolId != null) {
      label = 'Linked to idol';
      icon = AppAssets.iconUser;
    } else if (attachment.planItemId != null) {
      label = 'Linked to plan item';
      icon = AppAssets.iconListChecks;
    } else if (attachment.achievementId != null) {
      label = 'Linked to achievement';
      icon = AppAssets.iconTrophy;
    } else {
      return const SizedBox.shrink();
    }

    return CmpysCard(
      padding: AppSpacing.p12,
      backgroundColor: AppColors.accent.withValues(alpha: 0.05),
      borderColor: AppColors.accent.withValues(alpha: 0.2),
      child: Row(
        children: [
          SvgPicture.asset(
            icon,
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(
              AppColors.accent,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Error banner widget
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.p12,
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: AppRadii.br12,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            AppAssets.iconAlertCircle,
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(
              AppColors.error,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: SvgPicture.asset(
              AppAssets.iconX,
              width: 16,
              height: 16,
              colorFilter: ColorFilter.mode(
                AppColors.error.withValues(alpha: 0.7),
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Delete confirmation dialog
class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({
    required this.noteTitle,
    required this.onConfirm,
    required this.isDeleting,
  });

  final String noteTitle;
  final VoidCallback onConfirm;
  final bool isDeleting;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.br20),
      child: Padding(
        padding: AppSpacing.p24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: AppRadii.brFull,
              ),
              child: Center(
                child: SvgPicture.asset(
                  AppAssets.iconTrash,
                  width: 24,
                  height: 24,
                  colorFilter: const ColorFilter.mode(
                    AppColors.error,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s20),
            Text(
              'Delete Note?',
              style: AppTypography.h3,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Are you sure you want to delete "$noteTitle"? This action cannot be undone.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s24),
            Row(
              children: [
                Expanded(
                  child: CmpysButton(
                    label: 'Cancel',
                    variant: CmpysButtonVariant.ghost,
                    onPressed: isDeleting ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: CmpysButton(
                    label: 'Delete',
                    variant: CmpysButtonVariant.danger,
                    isLoading: isDeleting,
                    onPressed: isDeleting ? null : onConfirm,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
