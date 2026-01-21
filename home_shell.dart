import 'package:flutter/material.dart';
import 'estado_screen.dart';
import 'ubicacion_screen.dart';
import 'ruta_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    EstadoScreen(),
    UbicacionScreen(),
    RutaScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8FB),
      body: Stack(
        children: [
          // Contenido de páginas
          Positioned.fill(
            child: IndexedStack(
              index: _currentIndex,
              children: _pages,
            ),
          ),
          // Barra inferior fija superpuesta
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              elevation: 8,
              color: Colors.transparent,
              child: SafeArea(
                top: false,
                child: Container(
                  height: 70,
                  color: const Color(0xFFF8F8FB),
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _NavItem(
                        active: _currentIndex == 0,
                        icon: Icons.local_shipping,
                        onTap: () => setState(() => _currentIndex = 0),
                      ),
                      _NavItem(
                        active: _currentIndex == 1,
                        icon: Icons.location_on,
                        onTap: () => setState(() => _currentIndex = 1),
                      ),
                      _NavItem(
                        active: _currentIndex == 2,
                        icon: Icons.alt_route,
                        onTap: () => setState(() => _currentIndex = 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final bool active;
  final IconData icon;
  final VoidCallback onTap;

  const _NavItem({
    required this.active,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (active) {
      return CircleAvatar(
        backgroundColor: const Color.fromRGBO(33, 150, 243, 1),
        child: Icon(icon, color: Colors.white),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        backgroundColor: const Color(0xFFD9D9D9),
        child: Icon(icon, color: Colors.grey),
      ),
    );
  }
}
