import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Test Target Flutter Web',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        '/about': (context) => const AboutPage(),
        '/contact': (context) => const ContactPage(),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Test Target'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/'),
            child: const Text('Home', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/about'),
            child: const Text('About', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/contact'),
            child: const Text('Contact', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Welcome to Test Target',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              'This is a Flutter web application for integration testing.',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('About Us'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/'),
            child: const Text('Home', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/about'),
            child: const Text('About', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/contact'),
            child: const Text('Contact', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'About Us',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              'This is the about page for testing purposes.',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSubmitted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isSubmitted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Contact Us'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/'),
            child: const Text('Home', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/about'),
            child: const Text('About', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/contact'),
            child: const Text('Contact', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(16.0),
          child: _isSubmitted
              ? const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 64,
                      key: Key('success-icon'),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Thank you! Your message has been sent.',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                      key: Key('success-message'),
                    ),
                  ],
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Contact Us',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        key: const Key('name-input'),
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Your Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('email-input'),
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Your Email',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('message-input'),
                        controller: _messageController,
                        decoration: const InputDecoration(
                          labelText: 'Your Message',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 4,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your message';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: const Key('submit-button'),
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                        ),
                        child: const Text(
                          'Send Message',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
