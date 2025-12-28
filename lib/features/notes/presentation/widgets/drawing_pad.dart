import 'package:flutter/material.dart';

class DrawingPad extends StatefulWidget {
  final Function(List<Map<String, dynamic>>) onDrawingChanged;

  const DrawingPad({super.key, required this.onDrawingChanged});

  @override
  State<DrawingPad> createState() => _DrawingPadState();
}

class _DrawingPadState extends State<DrawingPad> {
  // Each stroke is a list of points
  final List<List<Offset>> _strokes = [];
  List<Offset>? _currentStroke;

  void _startStroke(DragStartDetails details) {
    setState(() {
      _currentStroke = [details.localPosition];
      _strokes.add(_currentStroke!);
    });
  }

  void _updateStroke(DragUpdateDetails details) {
    setState(() {
      final point = details.localPosition;
      // Filter out points outside canvas roughly to avoid errors, though clipRect handles visual
      if (point.dy >= 0 && point.dx >= 0) {
         _currentStroke?.add(point);
      }
    });
  }

  void _endStroke(DragEndDetails details) {
    _currentStroke = null;
    _notifyChanges();
  }

  void _notifyChanges() {
    // Convert Offset to simple Map for JSON
    // Structure: [ {"points": [{"dx": 10, "dy": 20}, ...]}, ... ]
    List<Map<String, dynamic>> jsonStrokes = _strokes.map((stroke) {
      return {
        'points': stroke.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
      };
    }).toList();
    
    widget.onDrawingChanged(jsonStrokes);
  }

  void clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = null;
    });
    _notifyChanges();
  }
  
  void undo() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _strokes.removeLast();
      });
      _notifyChanges();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(2, 2))
              ]
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onPanStart: _startStroke,
                onPanUpdate: _updateStroke,
                onPanEnd: _endStroke,
                child: CustomPaint(
                  painter: _DrawingPainter(_strokes),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(onPressed: undo, icon: const Icon(Icons.undo), tooltip: 'Geri Al'),
            IconButton(onPressed: clear, icon: const Icon(Icons.delete_outline), tooltip: 'Temizle'),
          ],
        )
      ],
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _DrawingPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    for (var stroke in strokes) {
      if (stroke.isEmpty) continue;
      Path path = Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
