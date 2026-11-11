import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/date_utils.dart';

/// Tarjeta de producto compartida por Ventas y Menú del día.
class ProductoCatalogoCard extends StatelessWidget {
  const ProductoCatalogoCard({
    super.key,
    required this.nombre,
    required this.categoria,
    required this.precio,
    required this.color,
    required this.mensaje,
    this.imagen,
    this.onTap,
    this.habilitado = true,
    this.esDirecto = false,
    this.stock,
    this.accion,
  });

  final Uint8List? imagen;
  final String nombre;
  final String categoria;
  final double precio;
  final int color;
  final String mensaje;
  final VoidCallback? onTap;
  final bool habilitado;
  final bool esDirecto;
  final double? stock;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texto = habilitado ? scheme.onSurface : scheme.onSurfaceVariant;
    return Opacity(
      opacity: habilitado ? 1 : 0.55,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 92,
                      width: double.infinity,
                      child: imagen != null
                          ? Image.memory(
                              imagen!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : Container(
                              color: Color(color).withValues(alpha: 0.10),
                              child: Icon(
                                esDirecto
                                    ? Icons.local_drink_outlined
                                    : Icons.restaurant,
                                size: 34,
                                color: Color(color),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Color(color),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          categoria,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      ?accion,
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700, color: texto),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney(precio),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: habilitado ? scheme.primary : texto,
                    ),
                  ),
                  if (stock != null && esDirecto)
                    Text(
                      'Stock: ${_formatQty(stock!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: habilitado ? scheme.onSurfaceVariant : texto,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        habilitado
                            ? Icons.add_circle_outline
                            : Icons.info_outline,
                        size: 18,
                        color: habilitado
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          mensaje,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: habilitado
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatQty(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    final dos = value.toStringAsFixed(2);
    if ((double.parse(dos) - value).abs() < 0.0000001) return dos;
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
