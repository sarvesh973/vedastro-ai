import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/user_profile.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../providers/providers.dart';
import '../widgets/location_autocomplete_field.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  final UserProfile profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _placeController;
  late DateTime _selectedDate;
  String? _selectedTime;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _placeController = TextEditingController(text: widget.profile.placeOfBirth);
    _selectedDate = widget.profile.dateOfBirth;
    _selectedTime = widget.profile.timeOfBirth;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _placeController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      locale: const Locale('en', 'IN'),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogTheme: DialogThemeData(
              backgroundColor: AppColors.surface,
            ),
            colorScheme: const ColorScheme.dark(
              primary: AppColors.purpleAccent,
              surface: AppColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime != null
          ? TimeOfDay(
              hour: int.tryParse(_selectedTime!.split(':')[0]) ?? 12,
              minute: int.tryParse(_selectedTime!.split(':')[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
            )
          : const TimeOfDay(hour: 12, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.purpleAccent,
              surface: AppColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked.format(context));
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    // Place is no longer a FormField (the autocomplete widget wraps a
    // plain TextField), so its emptiness can't be caught by form
    // validators. Surface a snackbar instead.
    if (_placeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your place of birth'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final updatedProfile = UserProfile(
      name: _nameController.text.trim(),
      dateOfBirth: _selectedDate,
      timeOfBirth: _selectedTime,
      placeOfBirth: _placeController.text.trim(),
    );

    await StorageService.saveProfile(updatedProfile);
    ref.read(userProfileProvider.notifier).state = updatedProfile;
    // Refresh the family-profile list provider so the home screen's
    // horizontal avatar switcher and any other consumers immediately
    // reflect the edit (the in-place update mutates the list, so we
    // re-emit it as a new list to trigger Riverpod rebuilds).
    ref.read(familyProfilesProvider.notifier).state =
        List<UserProfile>.from(StorageService.familyProfiles);
    ref.read(activeProfileIndexProvider.notifier).state =
        StorageService.activeProfileIndex;
    // Sync to cloud
    FirestoreService.syncProfile(updatedProfile);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _saveProfile,
            child: const Text(
              'Save',
              style: TextStyle(
                color: AppColors.purpleLight,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // Name
              const Text('Name', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(hintText: 'Your name'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter your name' : null,
              ),

              const SizedBox(height: 20),

              // Date of Birth
              const Text('Date of Birth', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: AppColors.textMuted, size: 18),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat('dd/MM/yyyy').format(_selectedDate),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Time of Birth
              const Text('Time of Birth (optional)', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickTime,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, color: AppColors.textMuted, size: 18),
                      const SizedBox(width: 12),
                      Text(
                        _selectedTime ?? 'Tap to select',
                        style: TextStyle(
                          color: _selectedTime != null ? AppColors.textPrimary : AppColors.textMuted,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Place of Birth — same Nominatim autocomplete as onboarding.
              // No FormField validation wrapper here — validation falls back
              // to the manual check in _saveProfile (checks placeController
              // is non-empty before submit).
              const Text('Place of Birth', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 8),
              LocationAutocompleteField(
                controller: _placeController,
                hintText: 'Search city, town or village',
              ),

              const SizedBox(height: 36),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purpleAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Save Changes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
