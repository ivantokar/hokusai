#ifndef CVIPS_SHIM_H
#define CVIPS_SHIM_H

#include <vips/vips.h>
#include <cairo/cairo-pdf.h>

/**
 * @brief PURPOSE: Thin C bridge that exposes libvips APIs to Swift.
 * CONSTRAINTS:
 * - Requires libvips >= 8.9 (vips_source_new_from_blob, vips_image_new_from_source,
 *   vips_thumbnail_source, vips_error_buffer_copy).
 * - Keep wrappers minimal and side-effect equivalent to libvips calls.
 * - Avoid policy/business logic in this layer.
 * AI HINTS:
 * - Add new wrappers only when Swift interop requires it.
 * - Preserve ownership/NULL semantics from underlying libvips APIs.
 */

// PURPOSE: Export commonly used vips enums and types for Swift
typedef VipsKernel VipsKernel;
typedef VipsBlendMode VipsBlendMode;
typedef VipsAlign VipsAlign;
typedef VipsAngle VipsAngle;
typedef VipsArrayDouble VipsArrayDouble;
typedef VipsInteresting VipsInteresting;
typedef VipsDirection VipsDirection;
typedef VipsAccess VipsAccess;

// MARK: - Cairo PDF Output

typedef struct {
    GByteArray *bytes;
} SwiftVipsPDFBuffer;

static inline cairo_status_t swift_vips_pdf_write(void *closure, const unsigned char *data, unsigned int length) {
    SwiftVipsPDFBuffer *buffer = closure;
    g_byte_array_append(buffer->bytes, data, length);
    return CAIRO_STATUS_SUCCESS;
}

/** @brief Rasterize a vips image to a single-page Cairo PDF buffer. */
static inline int swift_vips_pdfsave_buffer(
    VipsImage *in,
    void **out,
    size_t *length,
    double page_width,
    double page_height,
    double image_x,
    double image_y,
    double image_width,
    double image_height
) {
#if CAIRO_HAS_PDF_SURFACE
    VipsImage *srgb = NULL;
    VipsImage *uchar = NULL;
    void *pixels = NULL;
    unsigned char *cairo_pixels = NULL;
    cairo_surface_t *image_surface = NULL;
    cairo_surface_t *pdf_surface = NULL;
    cairo_t *context = NULL;
    SwiftVipsPDFBuffer buffer = { .bytes = g_byte_array_new() };
    int result = -1;

    if (buffer.bytes == NULL ||
        vips_colourspace(in, &srgb, VIPS_INTERPRETATION_sRGB, NULL) != 0 ||
        vips_cast(srgb, &uchar, VIPS_FORMAT_UCHAR, NULL) != 0) {
        goto done;
    }

    const int width = vips_image_get_width(uchar);
    const int height = vips_image_get_height(uchar);
    const int bands = vips_image_get_bands(uchar);
    if (width <= 0 || height <= 0 || (bands != 3 && bands != 4)) {
        vips_error("hokusai-pdf", "PDF output requires an RGB or RGBA image");
        goto done;
    }
    size_t input_length = 0;
    pixels = vips_image_write_to_memory(uchar, &input_length);
    const size_t pixel_count = (size_t) width * (size_t) height;
    if (pixels == NULL || pixel_count > G_MAXSIZE / 4) {
        goto done;
    }
    cairo_pixels = g_malloc(pixel_count * 4);
    if (cairo_pixels == NULL) {
        goto done;
    }
    const unsigned char *source = pixels;
    for (size_t index = 0; index < pixel_count; index++) {
        const unsigned char red = source[index * bands];
        const unsigned char green = source[index * bands + 1];
        const unsigned char blue = source[index * bands + 2];
        const unsigned char alpha = bands == 4 ? source[index * bands + 3] : 255;
        cairo_pixels[index * 4] = (unsigned char) ((blue * alpha + 127) / 255);
        cairo_pixels[index * 4 + 1] = (unsigned char) ((green * alpha + 127) / 255);
        cairo_pixels[index * 4 + 2] = (unsigned char) ((red * alpha + 127) / 255);
        cairo_pixels[index * 4 + 3] = alpha;
    }
    image_surface = cairo_image_surface_create_for_data(cairo_pixels, CAIRO_FORMAT_ARGB32, width, height, width * 4);
    pdf_surface = cairo_pdf_surface_create_for_stream(swift_vips_pdf_write, &buffer, page_width, page_height);
    context = cairo_create(pdf_surface);
    if (cairo_surface_status(image_surface) != CAIRO_STATUS_SUCCESS ||
        cairo_surface_status(pdf_surface) != CAIRO_STATUS_SUCCESS ||
        cairo_status(context) != CAIRO_STATUS_SUCCESS) {
        vips_error("hokusai-pdf", "could not create Cairo PDF surface");
        goto done;
    }
    cairo_save(context);
    cairo_translate(context, image_x, image_y);
    cairo_scale(context, image_width / width, image_height / height);
    cairo_set_source_surface(context, image_surface, 0, 0);
    cairo_paint(context);
    cairo_restore(context);
    cairo_show_page(context);
    cairo_surface_finish(pdf_surface);
    if (cairo_surface_status(pdf_surface) != CAIRO_STATUS_SUCCESS) {
        vips_error("hokusai-pdf", "Cairo could not finalize PDF output");
        goto done;
    }
    *out = g_memdup2(buffer.bytes->data, buffer.bytes->len);
    *length = buffer.bytes->len;
    result = *out == NULL && *length > 0 ? -1 : 0;

done:
    if (context) cairo_destroy(context);
    if (pdf_surface) cairo_surface_destroy(pdf_surface);
    if (image_surface) cairo_surface_destroy(image_surface);
    if (cairo_pixels) g_free(cairo_pixels);
    if (pixels) g_free(pixels);
    if (uchar) g_object_unref(uchar);
    if (srgb) g_object_unref(srgb);
    if (buffer.bytes) g_byte_array_unref(buffer.bytes);
    return result;
#else
    vips_error("hokusai-pdf", "Cairo was built without PDF surface support");
    return -1;
#endif
}

// MARK: - Error Handling

/** @brief Copy and atomically clear the libvips error buffer. Caller frees with g_free(). */
static inline char *swift_vips_error_copy(void) {
    return vips_error_buffer_copy();
}

// MARK: - Image Loading

/** @brief Load image from path and return owned VipsImage pointer. */
static inline VipsImage *swift_vips_image_new_from_file(const char *path) {
    return vips_image_new_from_file(path, NULL);
}

/** @brief Load image from path with sequential (streaming) access. */
static inline VipsImage *swift_vips_image_new_from_file_sequential(const char *path) {
    return vips_image_new_from_file(path, "access", VIPS_ACCESS_SEQUENTIAL, NULL);
}

/* vips_image_new_from_buffer() does not copy the bytes it is given; the caller
 * would have to keep them alive until the image and its whole pipeline are
 * closed. Swift callers pass pointers that are only valid inside
 * Data.withUnsafeBytes, so the buffer wrappers below copy the bytes into a
 * VipsBlob (freed by libvips when the last pipeline reference drops) and load
 * through a VipsSource. */
static inline VipsImage *swift_vips_image_new_from_buffer_with_access(const void *buf, size_t size, VipsAccess access) {
    VipsBlob *blob = vips_blob_copy(buf, size);
    if (blob == NULL) {
        return NULL;
    }
    VipsSource *source = vips_source_new_from_blob(blob);
    vips_area_unref(VIPS_AREA(blob)); /* the source holds its own reference */
    if (source == NULL) {
        return NULL;
    }
    VipsImage *image = vips_image_new_from_source(source, "", "access", access, NULL);
    g_object_unref(source); /* the image holds its own reference */
    return image;
}

/** @brief Load image from encoded bytes (copied) and return owned VipsImage pointer. */
static inline VipsImage *swift_vips_image_new_from_buffer(const void *buf, size_t size) {
    return swift_vips_image_new_from_buffer_with_access(buf, size, VIPS_ACCESS_RANDOM);
}

/** @brief Load image from encoded bytes (copied) with sequential (streaming) access. */
static inline VipsImage *swift_vips_image_new_from_buffer_sequential(const void *buf, size_t size) {
    return swift_vips_image_new_from_buffer_with_access(buf, size, VIPS_ACCESS_SEQUENTIAL);
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

static inline int swift_vips_text_full(
    VipsImage **out,
    const char *text,
    const char *font,
    int width,
    int height,
    int dpi,
    VipsAlign align,
    int spacing,
    int rgba
) {
    // PURPOSE: Render text with explicit layout parameters and RGBA output.
    return vips_text(
        out,
        text,
        "font", font,
        "width", width,
        "height", height,
        "dpi", dpi,
        "align", align,
        "spacing", spacing,
        "rgba", rgba,
        NULL
    );
}

static inline int swift_vips_text_full_fontfile(
    VipsImage **out,
    const char *text,
    const char *font,
    const char *fontfile,
    int width,
    int height,
    int dpi,
    VipsAlign align,
    int spacing,
    int rgba
) {
    // PURPOSE: Render text with optional explicit font file override.
    if (fontfile && fontfile[0] != '\0') {
        return vips_text(
            out,
            text,
            "font", font,
            "fontfile", fontfile,
            "width", width,
            "height", height,
            "dpi", dpi,
            "align", align,
            "spacing", spacing,
            "rgba", rgba,
            NULL
        );
    }

    return swift_vips_text_full(out, text, font, width, height, dpi, align, spacing, rgba);
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

static inline int swift_vips_gaussblur(VipsImage *in, VipsImage **out, double sigma) {
    return vips_gaussblur(in, out, sigma, NULL);
}

static inline int swift_vips_sharpen(VipsImage *in, VipsImage **out, double sigma) {
    return vips_sharpen(in, out, "sigma", sigma, NULL);
}

static inline int swift_vips_hist_norm(VipsImage *in, VipsImage **out) {
    return vips_hist_norm(in, out, NULL);
}

static inline int swift_vips_addalpha(VipsImage *in, VipsImage **out) {
    return vips_addalpha(in, out, NULL);
}

static inline int swift_vips_bandjoin_const(VipsImage *in, VipsImage **out, double *c, int n) {
    return vips_bandjoin_const(in, out, c, n, NULL);
}

static inline int swift_vips_bandjoin(VipsImage **in, VipsImage **out, int n) {
    return vips_bandjoin(in, out, n, NULL);
}

// MARK: - Metadata Helpers

/** @brief Read integer metadata field if present; return -1 when absent. */
static inline int swift_vips_image_get_int_field(VipsImage *in, const char *name, int *out) {
    if (vips_image_get_typeof(in, name) == 0) {
        return -1;
    }
    return vips_image_get_int(in, name, out);
}

/** @brief Copy a binary metadata field into caller-owned memory. */
static inline void *swift_vips_image_get_blob_copy(VipsImage *in, const char *name, size_t *length) {
    const void *data = NULL;
    size_t size = 0;
    if (vips_image_get_typeof(in, name) == 0 ||
        vips_image_get_blob(in, name, &data, &size) != 0 || data == NULL) {
        return NULL;
    }
    void *copy = g_malloc(size);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, data, size);
    *length = size;
    return copy;
}

/** @brief Read double metadata field if present; return -1 when absent. */
static inline int swift_vips_image_get_double_field(VipsImage *in, const char *name, double *out) {
    if (vips_image_get_typeof(in, name) == 0) {
        return -1;
    }
    return vips_image_get_double(in, name, out);
}

static inline const char *swift_vips_image_get_string_field(VipsImage *in, const char *name) {
    const char *value = NULL;
    if (vips_image_get_typeof(in, name) == 0) {
        return NULL;
    }
    if (vips_image_get_string(in, name, &value) != 0) {
        return NULL;
    }
    return value;
}

static inline char **swift_vips_image_get_fields(VipsImage *in) {
    return vips_image_get_fields(in);
}

static inline char *swift_vips_image_get_as_string(VipsImage *in, const char *name) {
    char *out = NULL;
    if (vips_image_get_as_string(in, name, &out) != 0) {
        return NULL;
    }
    return out;
}

static inline void swift_vips_g_strfreev(char **str_array) {
    g_strfreev(str_array);
}

static inline void swift_vips_g_free(void *ptr) {
    g_free(ptr);
}

static inline int swift_vips_image_get_interpretation(VipsImage *in) {
    return (int) in->Type;
}

static inline int swift_vips_image_get_band_format(VipsImage *in) {
    return (int) in->BandFmt;
}

static inline int swift_vips_image_get_coding(VipsImage *in) {
    return (int) in->Coding;
}

static inline double swift_vips_image_get_xres(VipsImage *in) {
    return in->Xres;
}

static inline double swift_vips_image_get_yres(VipsImage *in) {
    return in->Yres;
}

static inline const char *swift_vips_interpretation_nick(int value) {
    return vips_enum_nick(VIPS_TYPE_INTERPRETATION, value);
}

static inline const char *swift_vips_band_format_nick(int value) {
    return vips_enum_nick(VIPS_TYPE_BAND_FORMAT, value);
}

static inline const char *swift_vips_coding_nick(int value) {
    return vips_enum_nick(VIPS_TYPE_CODING, value);
}

static inline int swift_vips_flatten(VipsImage *in, VipsImage **out, VipsArrayDouble *background) {
    return vips_flatten(in, out, "background", background, NULL);
}

static inline int swift_vips_colourspace(VipsImage *in, VipsImage **out, VipsInterpretation space) {
    return vips_colourspace(in, out, space, NULL);
}

static inline int swift_vips_colourspace_bw(VipsImage *in, VipsImage **out) {
    return vips_colourspace(in, out, VIPS_INTERPRETATION_B_W, NULL);
}

static inline int swift_vips_colourspace_srgb(VipsImage *in, VipsImage **out) {
    return vips_colourspace(in, out, VIPS_INTERPRETATION_sRGB, NULL);
}

/** @brief Convert luminance to an sRGB tint; output is an opaque RGB image. */
static inline int swift_vips_tint(VipsImage *in, VipsImage **out, double red, double green, double blue) {
    VipsImage *grey = NULL;
    VipsImage *rgb = NULL;
    double scale[] = { red / 255.0, green / 255.0, blue / 255.0 };
    double offset[] = { 0, 0, 0 };
    if (vips_colourspace(in, &grey, VIPS_INTERPRETATION_B_W, NULL) != 0) {
        return -1;
    }
    if (vips_colourspace(grey, &rgb, VIPS_INTERPRETATION_sRGB, NULL) != 0) {
        g_object_unref(grey);
        return -1;
    }
    int result = vips_linear(rgb, out, scale, offset, 3, NULL);
    g_object_unref(rgb);
    g_object_unref(grey);
    return result;
}

static inline int swift_vips_jpegsave(VipsImage *in, const char *filename, int quality, int interlace, int strip) {
    return vips_jpegsave(in, filename, "Q", quality, "interlace", interlace, "strip", strip, NULL);
}

static inline int swift_vips_pngsave(VipsImage *in, const char *filename, int compression, int interlace, int strip) {
    return vips_pngsave(in, filename, "compression", compression, "interlace", interlace, "strip", strip, NULL);
}

static inline int swift_vips_webpsave(VipsImage *in, const char *filename, int quality, int lossless, int effort, int strip) {
    return vips_webpsave(in, filename, "Q", quality, "lossless", lossless, "effort", effort, "strip", strip, NULL);
}

static inline int swift_vips_tiffsave(VipsImage *in, const char *filename, int compression) {
    return vips_tiffsave(in, filename, "compression", compression, NULL);
}

static inline int swift_vips_heifsave(VipsImage *in, const char *filename, int quality, int lossless, int effort, int strip) {
    return vips_heifsave(in, filename, "Q", quality, "lossless", lossless, "effort", effort, "strip", strip, NULL);
}

static inline int swift_vips_gifsave(VipsImage *in, const char *filename) {
    return vips_gifsave(in, filename, NULL);
}

static inline int swift_vips_jpegsave_buffer(VipsImage *in, void **buf, size_t *len, int quality, int strip) {
    return vips_jpegsave_buffer(in, buf, len, "Q", quality, "strip", strip, NULL);
}

static inline int swift_vips_pngsave_buffer(VipsImage *in, void **buf, size_t *len, int compression, int strip) {
    return vips_pngsave_buffer(in, buf, len, "compression", compression, "strip", strip, NULL);
}

static inline int swift_vips_webpsave_buffer(VipsImage *in, void **buf, size_t *len, int quality, int lossless, int effort, int strip) {
    return vips_webpsave_buffer(in, buf, len, "Q", quality, "lossless", lossless, "effort", effort, "strip", strip, NULL);
}

static inline int swift_vips_concurrency_get(void) {
    return vips_concurrency_get();
}

static inline void swift_vips_concurrency_set(int concurrency) {
    vips_concurrency_set(concurrency);
}

static inline int swift_vips_tiffsave_buffer(VipsImage *in, void **buf, size_t *len) {
    return vips_tiffsave_buffer(in, buf, len, NULL);
}

static inline int swift_vips_heifsave_buffer(VipsImage *in, void **buf, size_t *len, int quality, int strip) {
    return vips_heifsave_buffer(in, buf, len, "Q", quality, "strip", strip, NULL);
}

static inline int swift_vips_gifsave_buffer(VipsImage *in, void **buf, size_t *len) {
    return vips_gifsave_buffer(in, buf, len, NULL);
}

// MARK: - Composite Operations

static inline int swift_vips_composite2(
    VipsImage *base,
    VipsImage *overlay,
    VipsImage **out,
    VipsBlendMode mode,
    int x,
    int y
) {
    return vips_composite2(base, overlay, out, mode, "x", x, "y", y, NULL);
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

static inline int swift_vips_extract_band(
    VipsImage *in,
    VipsImage **out,
    int band,
    int n
) {
    return vips_extract_band(in, out, band, "n", n, NULL);
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

// MARK: - Thumbnail Operations
// PURPOSE: Expose vips_thumbnail family for shrink-on-load workflows.
// CONSTRAINTS:
//   - height <= 0 means no height bound. VIPS_MAX_COORD is passed explicitly
//     because vips_thumbnail defaults an unset height to `width`, which would
//     bound the output to a square instead of preserving the aspect ratio.
//   - crop == VIPS_INTERESTING_NONE and no_rotate == 0 match the libvips defaults.

/** @brief Thumbnail from file path. Enables shrink-on-load for formats that support it. */
static inline int swift_vips_thumbnail(
    const char *filename,
    VipsImage **out,
    int width,
    int height,
    VipsInteresting crop,
    int no_rotate
) {
    return vips_thumbnail(filename, out, width,
        "height", height > 0 ? height : VIPS_MAX_COORD,
        "crop", crop,
        "no-rotate", no_rotate,
        NULL);
}

/** @brief Thumbnail from in-memory buffer (copied; see buffer-loading note above). */
static inline int swift_vips_thumbnail_buffer(
    const void *buf,
    size_t len,
    VipsImage **out,
    int width,
    int height,
    VipsInteresting crop,
    int no_rotate
) {
    VipsBlob *blob = vips_blob_copy(buf, len);
    if (blob == NULL) {
        return -1;
    }
    VipsSource *source = vips_source_new_from_blob(blob);
    vips_area_unref(VIPS_AREA(blob)); /* the source holds its own reference */
    if (source == NULL) {
        return -1;
    }
    int result = vips_thumbnail_source(source, out, width,
        "height", height > 0 ? height : VIPS_MAX_COORD,
        "crop", crop,
        "no-rotate", no_rotate,
        NULL);
    g_object_unref(source); /* the output image holds its own reference */
    return result;
}

/** @brief Thumbnail from an already-loaded VipsImage. No shrink-on-load benefit; use for images already in memory. */
static inline int swift_vips_thumbnail_image(
    VipsImage *in,
    VipsImage **out,
    int width,
    int height,
    VipsInteresting crop,
    int no_rotate
) {
    return vips_thumbnail_image(in, out, width,
        "height", height > 0 ? height : VIPS_MAX_COORD,
        "crop", crop,
        "no-rotate", no_rotate,
        NULL);
}

#endif /* CVIPS_SHIM_H */
