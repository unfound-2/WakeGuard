import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/features/account/presentation/cubit/account_cubit.dart';

class AccountProfileEditor extends StatefulWidget {
  final AccountState state;
  final String? primaryActionLabel;
  final IconData? primaryActionIcon;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final IconData? secondaryActionIcon;
  final VoidCallback? onSecondaryAction;

  const AccountProfileEditor({
    super.key,
    required this.state,
    this.primaryActionLabel,
    this.primaryActionIcon,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.onSecondaryAction,
  });

  @override
  State<AccountProfileEditor> createState() => _AccountProfileEditorState();
}

class _AccountProfileEditorState extends State<AccountProfileEditor> {
  final _nameController = TextEditingController();
  final _imagePicker = ImagePicker();

  String? _loadedUid;
  Uint8List? _selectedPhotoBytes;
  String? _selectedPhotoExtension;
  String? _selectedPhotoContentType;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncProfileFields();

    final scheme = Theme.of(context).colorScheme;
    final state = widget.state;
    final email = state.email ?? 'WakeGuard user';
    final profileName = state.displayName?.trim();
    final title = profileName == null || profileName.isEmpty
        ? 'Your profile'
        : profileName;

    return GlassCard(
      padding: const EdgeInsets.all(22),
      shadows: wakeCardShadow(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _AvatarButton(
                photoUrl: state.photoUrl,
                selectedBytes: _selectedPhotoBytes,
                isBusy: state.isBusy,
                onPressed: state.isBusy ? null : _pickProfilePhoto,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.badge_rounded),
            ),
            onSubmitted: (_) => _saveProfile(context),
          ),
          const SizedBox(height: 14),
          WakeSecondaryButton(
            label: _selectedPhotoBytes == null
                ? 'Choose Profile Photo'
                : 'Change Profile Photo',
            icon: Icons.add_a_photo_rounded,
            onPressed: state.isBusy ? null : _pickProfilePhoto,
          ),
          const SizedBox(height: 18),
          WakePrimaryButton(
            label: state.isBusy ? 'Saving...' : 'Save Profile',
            icon: Icons.save_rounded,
            onPressed: state.isBusy ? null : () => _saveProfile(context),
          ),
          const SizedBox(height: 14),
          WakeStatusPill(
            label: 'Cloud profile active',
            icon: Icons.cloud_done_rounded,
            color: scheme.primary,
          ),
          if (widget.primaryActionLabel != null &&
              widget.primaryActionIcon != null &&
              widget.onPrimaryAction != null) ...[
            const SizedBox(height: 18),
            WakePrimaryButton(
              label: widget.primaryActionLabel!,
              icon: widget.primaryActionIcon!,
              onPressed: state.isBusy ? null : widget.onPrimaryAction,
            ),
          ],
          if (widget.secondaryActionLabel != null &&
              widget.secondaryActionIcon != null &&
              widget.onSecondaryAction != null) ...[
            const SizedBox(height: 10),
            WakeSecondaryButton(
              label: state.isBusy
                  ? 'Please Wait...'
                  : widget.secondaryActionLabel!,
              icon: widget.secondaryActionIcon!,
              onPressed: state.isBusy ? null : widget.onSecondaryAction,
            ),
          ],
        ],
      ),
    );
  }

  void _syncProfileFields() {
    final uid = widget.state.uid;
    if (uid == null || uid == _loadedUid) return;
    _loadedUid = uid;
    _selectedPhotoBytes = null;
    _selectedPhotoExtension = null;
    _selectedPhotoContentType = null;
    _nameController.text = widget.state.displayName ?? '';
  }

  Future<void> _pickProfilePhoto() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 720,
      maxHeight: 720,
      imageQuality: 86,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _selectedPhotoBytes = bytes;
      _selectedPhotoExtension = _extensionFromName(image.name);
      _selectedPhotoContentType = image.mimeType;
    });
  }

  void _saveProfile(BuildContext context) {
    context.read<AccountCubit>().updateProfile(
      displayName: _nameController.text,
      photoBytes: _selectedPhotoBytes,
      photoExtension: _selectedPhotoExtension,
      photoContentType: _selectedPhotoContentType,
    );
    setState(() {
      _selectedPhotoBytes = null;
      _selectedPhotoExtension = null;
      _selectedPhotoContentType = null;
    });
  }

  String? _extensionFromName(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) return null;
    return name.substring(dotIndex + 1);
  }
}

class _AvatarButton extends StatelessWidget {
  final String? photoUrl;
  final Uint8List? selectedBytes;
  final bool isBusy;
  final VoidCallback? onPressed;

  const _AvatarButton({
    required this.photoUrl,
    required this.selectedBytes,
    required this.isBusy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: 'Change profile photo',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: GlassTheme.of(context).stroke),
              ),
              clipBehavior: Clip.antiAlias,
              child: _avatarImage(context),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Icon(
                  isBusy ? Icons.hourglass_top_rounded : Icons.camera_alt,
                  color: scheme.onPrimary,
                  size: 15,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _avatarImage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = selectedBytes;
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover);
    }

    final url = photoUrl;
    if (url != null && url.trim().isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _avatarFallback(scheme),
      );
    }

    return _avatarFallback(scheme);
  }

  Widget _avatarFallback(ColorScheme scheme) {
    return Icon(Icons.person_rounded, color: scheme.primary, size: 36);
  }
}
