import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NoteCard extends StatelessWidget {
  final Map<String, dynamic> note;
  final VoidCallback? onDelete;

  const NoteCard({
    super.key,
    required this.note,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final type = note['type'];
    final content = note['content']; // JSON or String
    final bool isDrawing = type == 'drawing';
    
    // Convert int color to Color obj, default yellow/white
    final colorVal = note['bg_color'] ?? 0xFFFFF9C4; // Default yellowish sticky note
    final bgColor = Color(colorVal);

    return Transform.rotate(
      angle: 0, // In future we can add random rotation for realism: (note['id'].hashCode % 10 - 5) * 0.01
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(2), // Sticky notes usually sharp or slightly rounded
          boxShadow: [
             BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(2, 4))
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pin or Tape simulation
            Center(
              child: Container(
                width: 12, height: 12,
                decoration: const BoxDecoration(
                  color: Color(0xFFE91E63), // Pink Pin
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(height: 8),
            
            // Content
            Expanded(
              child: isDrawing 
                 ? LayoutBuilder(
                     builder: (context, constraints) {
                       return CustomPaint(
                         size: Size(constraints.maxWidth, constraints.maxHeight),
                         painter: _StaticDrawingPainter(content),
                       );
                     }
                   )
                 : Center(
                     child: Text(
                       content is String ? content : '',
                       style: GoogleFonts.permanentMarker(
                         fontSize: 16,
                         color: Colors.black87
                       ),
                       textAlign: TextAlign.center,
                     ),
                   ),
            ),
            
            // Footer (Delete)
            if (onDelete != null)
              Align(
                alignment: Alignment.bottomRight,
                child: GestureDetector(
                  onTap: onDelete,
                  child: const Icon(Icons.delete, size: 16, color: Colors.black45),
                ),
              )
          ],
        ),
      ),
    );
  }
}

class _StaticDrawingPainter extends CustomPainter {
  final dynamic contentJson; // List<dynamic> strokes

  _StaticDrawingPainter(this.contentJson);

  @override
  void paint(Canvas canvas, Size size) {
    if (contentJson is! List) return;
    final List<dynamic> strokes = contentJson as List;

    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0 // Slightly thinner for viewing
      ..style = PaintingStyle.stroke;

    // We might need to handle scaling if the drawing pad size was different 
    // but for now let's assume 1:1 or just fit in box.
    // SVG-like scaling is needed for robust implementation but let's try direct coordinates.
    // Since coordinates were local to drawing pad (0..300 approx), and this card is small (150 approx),
    // we should create a scale factor.
    
    // Heuristic: Auto-scale to fit? Or fixed size?
    // Let's assume standard note size and use scale 0.5 if it exceeds?
    // Better: Calculate bounds of drawing and scale to fit `size`.
    
    // Bounds calculation
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    
    for (var s in strokes) {
      final points = s['points'] as List;
      for (var p in points) {
        final dx = (p['dx'] as num).toDouble();
        final dy = (p['dy'] as num).toDouble();
        if (dx < minX) minX = dx;
        if (dy < minY) minY = dy;
        if (dx > maxX) maxX = dx;
        if (dy > maxY) maxY = dy;
      }
    }
    
    if (minX == double.infinity) return; // Empty

    final w = maxX - minX + 20;
    final h = maxY - minY + 20; // + padding
    
    final scaleX = size.width / w;
    final scaleY = size.height / h;
    final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 1.0); // Don't upscale too much
    
    canvas.save();
    canvas.translate(size.width/2, size.height/2); // Center
    canvas.scale(scale);
    canvas.translate(-(minX + w/2) + 10, -(minY + h/2) + 10);

    for (var s in strokes) {
      final points = s['points'] as List;
      if (points.isEmpty) continue;
      
      Path path = Path();
      path.moveTo((points[0]['dx'] as num).toDouble(), (points[0]['dy'] as num).toDouble());
      
      for (int i = 1; i < points.length; i++) {
         path.lineTo((points[i]['dx'] as num).toDouble(), (points[i]['dy'] as num).toDouble());
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
