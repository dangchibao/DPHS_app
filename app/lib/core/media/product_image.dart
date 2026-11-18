import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../local_service.dart';
import 'media_service.dart';

class ProductImage extends StatefulWidget {
  const ProductImage({
    super.key,
    required this.service,
    this.reference,
    required this.fallback,
  });
  final LocalService service;
  final String? reference;
  final Widget fallback;
  @override
  State<ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends State<ProductImage> {
  Future<Uint8List?>? image;
  bool missing = false, loading = false;
  @override
  void initState() {
    super.initState();
    load();
    widget.service.syncEngine?.addListener(refresh);
  }

  @override
  void dispose() {
    widget.service.syncEngine?.removeListener(refresh);
    super.dispose();
  }

  @override
  void didUpdateWidget(ProductImage old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference) {
      missing = false;
      load();
    }
  }

  void refresh() {
    if (mounted &&
        widget.reference != null &&
        missing &&
        !loading &&
        widget.service.syncEngine?.mediaEnabled == true) {
      setState(load);
    }
  }

  void load() {
    loading = true;
    image = widget.service
        .productImage(widget.reference)
        .then((bytes) {
          missing = bytes == null;
          return bytes;
        })
        .catchError((Object _) {
          missing = true;
          return null;
        })
        .whenComplete(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: image,
    builder: (context, snapshot) => snapshot.data == null
        ? widget.fallback
        : Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => widget.fallback,
          ),
  );
}
