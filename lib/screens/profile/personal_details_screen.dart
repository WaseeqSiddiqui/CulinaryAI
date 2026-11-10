import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Personal details')),
      body: AppPageBody(
        maxWidth: 760,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              const PageIntro(
                eyebrow: 'A LITTLE ABOUT YOU',
                title: 'Your kitchen, your story.',
                subtitle: 'Keep your details up to date and make CulinaryAI feel more like you.',
              ),
              const SizedBox(height: 26),
              FormSection(
                title: 'The essentials',
                children: [
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    validator: AuthValidators.name,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: user.email,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                      helperText: 'Your sign-in email stays the same.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FormSection(
                title: 'Stay connected',
                description: 'These details are optional.',
                children: [
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    validator: AuthValidators.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+92 300 1234567',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _locationController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.addressCity],
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'City or location',
                      prefixIcon: Icon(Icons.location_on_outlined),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date of birth',
                        prefixIcon: Icon(Icons.cake_outlined),
                        suffixIcon: Icon(Icons.calendar_month_outlined),
                      ),
                      child: Text(
                        _dateOfBirth == null
                            ? 'Select a date'
                            : DateFormat('d MMMM yyyy').format(_dateOfBirth!),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FormSection(
                title: 'At home in the kitchen',
                description: 'Tell us what you enjoy.',
                children: [
                  TextFormField(
                    controller: _dietController,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Food preference',
                      hintText: 'e.g. Halal, vegetarian, high-protein',
                      prefixIcon: Icon(Icons.restaurant_outlined),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _bioController,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 240,
                    decoration: const InputDecoration(
                      labelText: 'About you',
                      alignLabelWithHint: true,
                      hintText: 'A little about your cooking style…',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: AppPageBody(
          maxWidth: 760,
          shrinkWrap: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: FilledButton.icon(
              onPressed: auth.isProfileSaving ? null : _save,
              icon: auth.isProfileSaving
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(auth.isProfileSaving ? 'Saving…' : 'Save details'),
            ),
          ),
        ),
      ),
    );
  }
}
