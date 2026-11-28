import 'package:image/image.dart' as img;

/// [image] turned as its EXIF orientation says, without EXIF data.
img.Image uprightPixels(img.Image image) =>
    img.bakeOrientation(image)..exif = img.ExifData();
