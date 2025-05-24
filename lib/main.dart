// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volet_roulant_app/providers/app_state.dart';
import 'package:volet_roulant_app/screens/home_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'dart:developer' as developer;

void main() async {
  developer.log('Starting app initialization...', name: 'Main');
  WidgetsFlutterBinding.ensureInitialized();
  try {
    developer.log('Attempting to initialize Firebase...', name: 'Main');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 10), onTimeout: () {
      throw Exception('Firebase initialization timed out after 10 seconds');
    });
    developer.log('Firebase initialized successfully', name: 'Main');
  } catch (e) {
    developer.log('Failed to initialize Firebase: $e', name: 'Main', level: 1000);
    runApp(ErrorApp(errorMessage: 'Failed to initialize Firebase: $e'));
    return;
  }
  developer.log('Running the app...', name: 'Main');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    developer.log('Building MyApp widget...', name: 'Main');
    return ChangeNotifierProvider(
      create: (context) {
        developer.log('Creating AppState instance...', name: 'Main');
        return AppState();
      },
      child: Consumer<AppState>(
        builder: (context, appState, child) {
          return MaterialApp(
            title: 'Volet Roulant App',
            theme: ThemeData.dark().copyWith(
              primaryColor: Colors.blueGrey,
              scaffoldBackgroundColor: Colors.black,
              textTheme: const TextTheme(
                bodyLarge: TextStyle(color: Colors.white),
                bodyMedium: TextStyle(color: Colors.white70),
              ),
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.blueGrey,
                elevation: 0,
              ),
            ),
            initialRoute: appState.hasFirebaseAccess ? '/home' : '/login',
            routes: {
              '/login': (context) => const LoginPage(),
              '/home': (context) => const HomePage(),
              '/profile': (context) => const ProfilePage(),
              '/details': (context) => const DetailsPage(),
            },
          );
        },
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String errorMessage;
  const ErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    developer.log('Showing ErrorApp with message: $errorMessage', name: 'Main');
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Center(
          child: Text(
            'Error: $errorMessage',
            style: const TextStyle(color: Colors.red, fontSize: 20),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      if (_isLogin) {
        await appState.signInWithEmail(_emailController.text, _passwordController.text);
      } else {
        await appState.signUpWithEmail(_emailController.text, _passwordController.text);
      }
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    developer.log('Building LoginPage...', name: 'Main');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Sign in to control your Volet Roulant',
              style: TextStyle(fontSize: 18, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade600,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              onPressed: _submit,
              child: Text(
                _isLogin ? 'Login' : 'Sign Up',
                style: const TextStyle(fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLogin = !_isLogin;
                  _errorMessage = null;
                });
              },
              child: Text(_isLogin ? 'Need an account? Sign Up' : 'Have an account? Login'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    developer.log('Building ProfilePage...', name: 'Main');
    final appState = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'User Profile\nManage your settings',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.white70),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              onPressed: () async {
                try {
                  developer.log('Attempting to sign out...', name: 'Main');
                  await appState.signOut();
                  developer.log('User signed out', name: 'Main');
                  Navigator.pushReplacementNamed(context, '/login');
                } catch (e) {
                  developer.log('Sign-out failed: $e', name: 'Main', level: 1000);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Sign-out failed: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              child: const Text(
                'Sign Out',
                style: TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade600,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              onPressed: () {
                developer.log('Clearing all schedules...', name: 'Main');
                appState.clearSchedules();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All schedules cleared'),
                    backgroundColor: Colors.teal,
                  ),
                );
              },
              child: const Text(
                'Clear All Schedules',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DetailsPage extends StatelessWidget {
  const DetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    developer.log('Building DetailsPage...', name: 'Main');
    final appState = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control Center'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Schedules',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: appState.schedules.isEmpty
                  ? const Center(
                      child: Text(
                        'No schedules available',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    )
                  : ListView.builder(
                      itemCount: appState.schedules.length,
                      itemBuilder: (context, index) {
                        final schedule = appState.schedules[index];
                        return Card(
                          color: Colors.teal.shade900,
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          child: ListTile(
                            title: Text(
                              '${schedule.day} at ${schedule.time} - ${schedule.action}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              schedule.executed ? 'Executed' : 'Pending',
                              style: TextStyle(
                                color: schedule.executed
                                    ? Colors.greenAccent
                                    : Colors.white70,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                developer.log('Deleting schedule at index $index', name: 'Main');
                                appState.removeSchedule(index);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Schedule deleted: ${schedule.day} at ${schedule.time}',
                                    ),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}