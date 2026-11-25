import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:oktoast/oktoast.dart';
import 'package:provider/provider.dart';
import 'package:retroshare/common/show_dialog.dart';
import 'package:retroshare/model/http_exception.dart';
import 'package:retroshare/provider/auth.dart';
import 'package:retroshare/provider/identity.dart';
import 'package:retroshare/common/rs_tokens.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  SignUpScreenState createState() => SignUpScreenState();
}

enum PasswordError { correct, notTheSame, tooShort }

class SignUpScreenState extends State<SignUpScreen> {
  TextEditingController usernameController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  TextEditingController repeatPasswordController = TextEditingController();
  TextEditingController nodeNameController = TextEditingController();

  bool isUsernameCorrect = true;
  bool isNodeNameCorrect = true;
  PasswordError passwordError = PasswordError.correct;

  @override
  void initState() {
    super.initState();
    isUsernameCorrect = true;
    isNodeNameCorrect = true;
    passwordError = PasswordError.correct;
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    repeatPasswordController.dispose();
    nodeNameController.dispose();
    super.dispose();
  }

  Future<void> createAccount() async {
    var success = true;
    setState(() {
      isUsernameCorrect = usernameController.text.trim().length >= 3;
      isNodeNameCorrect = nodeNameController.text.trim().isNotEmpty;
      passwordError = PasswordError.correct;
    });
    if (!isUsernameCorrect || !isNodeNameCorrect) success = false;
    if (passwordController.text != repeatPasswordController.text) {
      setState(() {
        passwordError = PasswordError.notTheSame;
      });
      success = false;
    }
    if (passwordController.text.length < 3) {
      setState(() {
        passwordError = PasswordError.tooShort;
      });
      success = false;
    }

    if (!success) return;

    unawaited(
      Navigator.pushNamed(
        context,
        '/',
        arguments: {
          'statusText': 'Creating account...\nThis could take minutes',
          'isLoading': true,
          'spinner': true,
        },
      ),
    );
    try {
      final accountSignup =
          Provider.of<AccountCredentials>(context, listen: false);
      await accountSignup
          .signup(
        usernameController.text,
        passwordController.text,
        nodeNameController.text.trim(),
      )
          .then((value) {
        final ids = Provider.of<Identities>(context, listen: false);
        ids.fetchOwnidenities().then((value) {
          ids.ownIdentity.isEmpty
              ? Navigator.pushReplacementNamed(
                  context,
                  '/create_identity',
                  arguments: true,
                )
              : Navigator.pushReplacementNamed(context, '/home');
        });
      });
    } on HttpException {
      const errorMessage = 'Authentication failed';
      await errorShowDialog(errorMessage, 'Something went wrong', context);
    } catch (e) {
      debugPrint('Error creating account: $e');
      await errorShowDialog(
        'Retroshare Service Down',
        'Try to restart the app Again!',
        context,
      );
    }
  }

  Widget _buildLogo() {
    return Hero(
      tag: 'logo',
      child: Image.asset(
        'assets/rs-logo.png',
        height: 250,
        width: 250,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        height: 40,
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            border: InputBorder.none,
            icon: Icon(
              icon,
              color: Theme.of(context).hintColor,
              size: 22,
            ),
            hintText: hintText,
          ),
          style: Theme.of(context).textTheme.bodyLarge,
          obscureText: obscureText,
        ),
      ),
    );
  }

  Widget _buildUsernameField() {
    return _buildTextField(
      controller: usernameController,
      hintText: 'Profile name (you)',
      icon: Icons.person_outline,
    );
  }

  Widget _buildPasswordField() {
    return _buildTextField(
      controller: passwordController,
      hintText: 'Password',
      icon: Icons.lock_outline,
      obscureText: true,
    );
  }

  Widget _buildRepeatPasswordField() {
    return _buildTextField(
      controller: repeatPasswordController,
      hintText: 'Repeat password',
      icon: Icons.lock_outline,
      obscureText: true,
    );
  }

  Widget _buildNodeNameField() {
    return _buildTextField(
      controller: nodeNameController,
      hintText: 'Node name (this device)',
      icon: Icons.smartphone,
    );
  }

  Widget _buildErrorText(String message) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(left: 52, top: 2, bottom: 8),
        child: Text(
          message,
          style: const TextStyle(color: Colors.red, fontSize: 12),
          textAlign: TextAlign.left,
        ),
      ),
    );
  }

  Widget _buildUsernameError() {
    if (!isUsernameCorrect) {
      return _buildErrorText('Profile name is too short');
    }
    return const SizedBox(height: 10);
  }

  Widget _buildNodeNameError() {
    if (!isNodeNameCorrect) {
      return _buildErrorText('Give this node a name');
    }
    return const SizedBox(height: 10);
  }

  Widget _buildPasswordError() {
    if (passwordError == PasswordError.tooShort) {
      return _buildErrorText('Password is too short');
    }
    return const SizedBox(height: 10);
  }

  Widget _buildRepeatPasswordError() {
    if (passwordError == PasswordError.notTheSame) {
      return _buildErrorText('Passwords do not match');
    }
    return const SizedBox(height: 10);
  }

  Widget _buildImportButton(BuildContext context) {
    return TextButton(
      onPressed: () => _showImportDialog(context),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.file_download,
              color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            'Import an existing profile',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    final screenContext = context;
    final certController = TextEditingController();
    final passController = TextEditingController();
    var isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Import a profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Import an exported RetroShare profile (.asc) and create a new node for it on this device.',
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['asc'],
                    );
                    if (result != null) {
                      final file = File(result.files.single.path!);
                      final content = await file.readAsString();
                      certController.text = content;
                    }
                  },
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Choose Profile File (.asc)'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: certController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Paste exported RetroShare profile here...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nodeNameController,
                  decoration: const InputDecoration(
                    hintText: 'Node name (this device)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Profile password',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (certController.text.isEmpty ||
                          passController.text.isEmpty ||
                          nodeNameController.text.trim().isEmpty) {
                        showToast('Please fill all fields');
                        return;
                      }
                      setState(() => isLoading = true);
                      try {
                        final authProvider = Provider.of<AccountCredentials>(
                            context,
                            listen: false);
                        final rawContent = certController.text.trim();

                        await authProvider.importIdentityAndCreateLocation(
                          rawContent,
                          passController.text,
                          nodeName: nodeNameController.text.trim(),
                        );

                        if (!context.mounted) return;
                        Navigator.pop(context);
                        if (!screenContext.mounted) return;

                        final identities = Provider.of<Identities>(
                          screenContext,
                          listen: false,
                        )..authToken = authProvider.authtoken;
                        await identities.fetchOwnidenities();
                        if (!screenContext.mounted) return;

                        showToast('Profile imported successfully');
                        if (identities.ownIdentity.isEmpty) {
                          await Navigator.of(screenContext)
                              .pushReplacementNamed(
                            '/create_identity',
                            arguments: true,
                          );
                        } else {
                          await Navigator.of(screenContext)
                              .pushReplacementNamed('/home');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showToast('Import failed: $e');
                        }
                      } finally {
                        if (context.mounted) {
                          setState(() => isLoading = false);
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Import'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateAccountButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      onPressed: createAccount,
      child: Ink(
        decoration: BoxDecoration(
          gradient: context.rs.actionGradient,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          alignment: Alignment.center,
          child: const Text(
            'Create account',
            style: TextStyle(
              fontSize: 20,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _buildLogo(),
                _buildUsernameField(),
                _buildUsernameError(),
                _buildNodeNameField(),
                _buildNodeNameError(),
                _buildPasswordField(),
                _buildPasswordError(),
                _buildRepeatPasswordField(),
                _buildRepeatPasswordError(),
                const SizedBox(height: 10),
                _buildCreateAccountButton(),
                const SizedBox(height: 10),
                _buildImportButton(context),
                const SizedBox(height: 70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
