import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/auth_validators.dart';
import '../../providers/auth_provider.dart';

class PersonalDetailsScreen extends StatefulWidget {
  const PersonalDetailsScreen({super.key});

  @override
  State<PersonalDetailsScreen> createState() => _PersonalDetailsScreenState();
}

class _PersonalDetailsScreenState extends State<PersonalDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _locationController;
  late final TextEditingController _dietController;
  late final TextEditingController _bioController;
  DateTime? _dateOfBirth;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser!;
    _nameController = TextEditingController(text: user.name);
    _phoneController = TextEditingController(text: user.phoneNumber ?? '');
    _locationController = TextEditingController(text: user.location ?? '');
    _dietController = TextEditingController(text: user.dietaryPreference ?? '');
    _bioController = TextEditingController(text: user.bio ?? '');
    _dateOfBirth = user.dateOfBirth;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _dietController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(today.year - 18),
      firstDate: DateTime(1900),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: 'Select date of birth',
    );
    if (selected != null && mounted) {
      setState(() => _dateOfBirth = selected);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final user = auth.currentUser!;
    final updated = user.copyWith(
      name: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      dateOfBirth: _dateOfBirth,
      location: _locationController.text.trim(),
      dietaryPreference: _dietController.text.trim(),
      bio: _bioController.text.trim(),
    );

    final saved = await auth.updateProfile(updated);
    if (!mounted) return;

    if (saved) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Personal details saved.')));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage ?? 'Could not save your profile.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.bgDark : AppTheme.bgLight,
      appBar: AppBar(title: const Text('Personal Details')),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
          children: [
            Text(
              'Keep your profile up to date',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'These details personalize your CulinaryAI experience and appear on your profile.',
              style: TextStyle(
                color: isDark
                    ? AppTheme.textDarkSecondary
                    : AppTheme.textLightSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: AuthValidators.name,
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: user.email,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.email_outlined),
                helperText: 'Your sign-in email cannot be changed here.',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(
                labelText: 'Phone number (optional)',
                prefixIcon: Icon(Icons.phone_outlined),
                hintText: '+92 300 1234567',
              ),
              validator: AuthValidators.phone,
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date of birth (optional)',
                  prefixIcon: Icon(Icons.cake_outlined),
                  suffixIcon: Icon(Icons.calendar_month_outlined),
                ),
                child: Text(
                  _dateOfBirth == null
                      ? 'Select date'
                      : DateFormat('d MMMM yyyy').format(_dateOfBirth!),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _locationController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.addressCity],
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'City or location (optional)',
                prefixIcon: Icon(Icons.location_on_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _dietController,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Food preference (optional)',
                prefixIcon: Icon(Icons.restaurant_outlined),
                hintText: 'e.g. Halal, vegetarian, high-protein',
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _bioController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 3,
              maxLines: 5,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'About you (optional)',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_rounded),
                hintText: 'Tell us a little about your cooking style.',
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: auth.isProfileSaving ? null : _save,
              icon: auth.isProfileSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.3,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(auth.isProfileSaving ? 'Saving...' : 'Save Details'),
            ),
          ],
        ),
      ),
    );
  }
}
