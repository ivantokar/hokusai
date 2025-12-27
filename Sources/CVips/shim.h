#ifndef CVIPS_SHIM_H
#define CVIPS_SHIM_H

#include <vips/vips.h>

// Export commonly used vips enums and types for Swift
typedef VipsKernel VipsKernel;
typedef VipsBlendMode VipsBlendMode;
typedef VipsAlign VipsAlign;
typedef VipsAngle VipsAngle;
typedef VipsArrayDouble VipsArrayDouble;
typedef VipsInteresting VipsInteresting;
typedef VipsDirection VipsDirection;

// MARK: - Image Loading

static inline VipsImage *swift_vips_image_new_from_file(const char *path) {
    return vips_image_new_from_file(path, NULL);
}

static inline VipsImage *swift_vips_image_new_from_buffer(const void *buf, size_t size) {
    return vips_image_new_from_buffer(buf, size, "", NULL);
}

static inline int swift_vips_copy(VipsImage *in, VipsImage **out) {
    return vips_copy(in, out, NULL);
}

static inline int swift_vips_jpegload(const char *filename, VipsImage **out) {
    return vips_jpegload(filename, out, NULL);
}

static inline int swift_vips_pngload(const char *filename, VipsImage **out) {
    return vips_pngload(filename, out, NULL);
}

static inline int swift_vips_webpload(const char *filename, VipsImage **out) {
    return vips_webpload(filename, out, NULL);
}

static inline int swift_vips_gifload(const char *filename, VipsImage **out) {
    return vips_gifload(filename, out, NULL);
}

static inline int swift_vips_tiffload(const char *filename, VipsImage **out) {
    return vips_tiffload(filename, out, NULL);
}

static inline int swift_vips_svgload(const char *filename, VipsImage **out) {
    return vips_svgload(filename, out, NULL);
}

static inline int swift_vips_pdfload(const char *filename, VipsImage **out) {
    return vips_pdfload(filename, out, NULL);
}

static inline int swift_vips_heifload(const char *filename, VipsImage **out) {
    return vips_heifload(filename, out, NULL);
}

static inline int swift_vips_resize(VipsImage *in, VipsImage **out, double hscale, double vscale, VipsKernel kernel) {
    return vips_resize(in, out, hscale, "vscale", vscale, "kernel", kernel, NULL);
}

static inline int swift_vips_embed(
    VipsImage *in,
    VipsImage **out,
    int x,
    int y,
    int width,
    int height,
    VipsArrayDouble *background
) {
    return vips_embed(in, out, x, y, width, height, "background", background, NULL);
}

static inline int swift_vips_rot(VipsImage *in, VipsImage **out, VipsAngle angle) {
    return vips_rot(in, out, angle, NULL);
}

static inline int swift_vips_flip(VipsImage *in, VipsImage **out, VipsDirection direction) {
    return vips_flip(in, out, direction, NULL);
}

static inline int swift_vips_autorot(VipsImage *in, VipsImage **out) {
    return vips_autorot(in, out, NULL);
}

static inline int swift_vips_similarity(VipsImage *in, VipsImage **out, double angle) {
    return vips_similarity(in, out, "angle", angle, NULL);
}

static inline int swift_vips_similarity_background(VipsImage *in, VipsImage **out, double angle, VipsArrayDouble *background) {
    return vips_similarity(in, out, "angle", angle, "background", background, NULL);
}

static inline int swift_vips_text(VipsImage **out, const char *text, const char *font, int dpi, VipsAlign align) {
    return vips_text(out, text, "font", font, "dpi", dpi, "align", align, NULL);
}

static inline int swift_vips_find_trim(
    VipsImage *in,
    int *left,
    int *top,
    int *width,
    int *height,
    double threshold
) {
    return vips_find_trim(in, left, top, width, height, "threshold", threshold, NULL);
}

static inline int swift_vips_linear1(VipsImage *in, VipsImage **out, double a, double b) {
    return vips_linear1(in, out, a, b, NULL);
}

static inline int swift_vips_addalpha(VipsImage *in, VipsImage **out) {
    return vips_addalpha(in, out, NULL);
}

static inline int swift_vips_bandjoin_const(VipsImage *in, VipsImage **out, const double *c, int n) {
    return vips_bandjoin_const(in, out, c, n, NULL);
}

static inline int swift_vips_bandjoin(VipsImage **in, VipsImage **out, int n) {
    return vips_bandjoin(in, out, n, NULL);
}

static inline int swift_vips_flatten(VipsImage *in, VipsImage **out, VipsArrayDouble *background) {
    return vips_flatten(in, out, "background", background, NULL);
}

static inline int swift_vips_colourspace(VipsImage *in, VipsImage **out, VipsInterpretation space) {
    return vips_colourspace(in, out, space, NULL);
}

static inline int swift_vips_jpegsave(VipsImage *in, const char *filename, int quality, int interlace, int strip) {
    return vips_jpegsave(in, filename, "Q", quality, "interlace", interlace, "strip", strip, NULL);
}

static inline int swift_vips_pngsave(VipsImage *in, const char *filename, int compression, int interlace) {
    return vips_pngsave(in, filename, "compression", compression, "interlace", interlace, NULL);
}

static inline int swift_vips_webpsave(VipsImage *in, const char *filename, int quality, int lossless, int effort) {
    return vips_webpsave(in, filename, "Q", quality, "lossless", lossless, "effort", effort, NULL);
}

static inline int swift_vips_tiffsave(VipsImage *in, const char *filename, int compression) {
    return vips_tiffsave(in, filename, "compression", compression, NULL);
}

static inline int swift_vips_heifsave(VipsImage *in, const char *filename, int quality, int lossless, int effort) {
    return vips_heifsave(in, filename, "Q", quality, "lossless", lossless, "effort", effort, NULL);
}

static inline int swift_vips_gifsave(VipsImage *in, const char *filename) {
    return vips_gifsave(in, filename, NULL);
}

static inline int swift_vips_jpegsave_buffer(VipsImage *in, void **buf, size_t *len, int quality) {
    return vips_jpegsave_buffer(in, buf, len, "Q", quality, NULL);
}

static inline int swift_vips_pngsave_buffer(VipsImage *in, void **buf, size_t *len, int compression) {
    return vips_pngsave_buffer(in, buf, len, "compression", compression, NULL);
}

static inline int swift_vips_webpsave_buffer(VipsImage *in, void **buf, size_t *len, int quality, int lossless) {
    return vips_webpsave_buffer(in, buf, len, "Q", quality, "lossless", lossless, NULL);
}

static inline int swift_vips_tiffsave_buffer(VipsImage *in, void **buf, size_t *len) {
    return vips_tiffsave_buffer(in, buf, len, NULL);
}

static inline int swift_vips_heifsave_buffer(VipsImage *in, void **buf, size_t *len, int quality) {
    return vips_heifsave_buffer(in, buf, len, "Q", quality, NULL);
}

static inline int swift_vips_gifsave_buffer(VipsImage *in, void **buf, size_t *len) {
    return vips_gifsave_buffer(in, buf, len, NULL);
}

// MARK: - Composite Operations

static inline int swift_vips_composite2(
    VipsImage *base,
    VipsImage *overlay,
    VipsImage **out,
    VipsBlendMode mode
) {
    VipsImage *in[2] = {base, overlay};
    int modes[1] = {mode};
    return vips_composite(in, out, 2, modes, 1, NULL);
}

// MARK: - Array Helpers

static inline VipsArrayDouble* swift_vips_array_double_new(const double *array, int n) {
    return vips_array_double_new(array, n);
}

// MARK: - Crop Operations

static inline int swift_vips_extract_area(
    VipsImage *in,
    VipsImage **out,
    int left,
    int top,
    int width,
    int height
) {
    return vips_extract_area(in, out, left, top, width, height, NULL);
}

static inline int swift_vips_smartcrop(
    VipsImage *in,
    VipsImage **out,
    int width,
    int height,
    VipsInteresting interesting
) {
    return vips_smartcrop(in, out, width, height, "interesting", interesting, NULL);
}

// MARK: - Enum Helpers

static inline const char* swift_vips_interpretation_nick(VipsInterpretation interpretation) {
    return vips_enum_nick(VIPS_TYPE_INTERPRETATION, interpretation);
}

#endif /* CVIPS_SHIM_H */
