#ifndef CVIPS_SHIM_H
#define CVIPS_SHIM_H

#include <vips/vips.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

// Hokusai's native baseline. Older libraries are rejected at compile time
// rather than failing later with missing symbols or silently different output.
#if VIPS_MAJOR_VERSION < 8 || (VIPS_MAJOR_VERSION == 8 && VIPS_MINOR_VERSION < 16)
#error "Hokusai requires libvips 8.16 or later"
#endif

/**
 * @brief Minimal C bridge that makes libvips APIs usable from Swift.
 *
 * Requires libvips 8.16 or later (see the version guard above). Wrappers
 * preserve libvips ownership and NULL semantics; validation and product policy
 * belong in the Swift layer.
 */

// Re-export commonly used libvips enums and types for Swift interop.
typedef VipsKernel VipsKernel;
typedef VipsBlendMode VipsBlendMode;
typedef VipsAlign VipsAlign;
typedef VipsAngle VipsAngle;
typedef VipsArrayDouble VipsArrayDouble;
typedef VipsInteresting VipsInteresting;
typedef VipsDirection VipsDirection;
typedef VipsAccess VipsAccess;

// MARK: - Raster Preparation for PDF

/** @brief Cast to 8-bit unsigned samples (clipping). */
static inline int swift_vips_cast_uchar(VipsImage *in, VipsImage **out) {
    return vips_cast(in, out, VIPS_FORMAT_UCHAR, NULL);
}

// MARK: - Error Handling

/**
 * @brief Copy and clear the libvips error buffer. Caller frees with g_free().
 *
 * The buffer is process-global: under concurrent failures the copied text may
 * include diagnostics from other threads, so it is detail, not identity.
 */
static inline char *swift_vips_error_copy(void) {
    return vips_error_buffer_copy();
}

// MARK: - Runtime Capabilities

/** @brief Whether libvips provides an operation with this nickname (e.g. "pdfload"). */
static inline int swift_vips_operation_exists(const char *nickname) {
    return vips_type_find("VipsOperation", nickname) != 0;
}

/**
 * @brief Encode and fully decode a tiny AV1 HEIF image.
 *
 * Returns 0 when both an AV1 encoder and decoder are usable. libheif plugins
 * are optional, so the presence of heifsave/heifload is not enough.
 */
static inline int swift_vips_avif_roundtrip_probe(void) {
    VipsImage *black = NULL;
    VipsImage *probe = NULL;
    VipsImage *decoded = NULL;
    void *buffer = NULL;
    size_t length = 0;
    double mean = 0;
    int result = -1;

    // heifsave in libvips 8.16 rejects the multiband interpretation vips_black
    // produces, so tag the probe as sRGB.
    if (vips_black(&black, 16, 16, "bands", 3, NULL)) {
        return -1;
    }
    int copied = vips_copy(black, &probe, "interpretation", VIPS_INTERPRETATION_sRGB, NULL);
    g_object_unref(black);
    if (copied) {
        return -1;
    }
    if (!vips_heifsave_buffer(probe, &buffer, &length, "compression", VIPS_FOREIGN_HEIF_COMPRESSION_AV1, NULL) &&
        !vips_heifload_buffer(buffer, length, &decoded, NULL) &&
        !vips_avg(decoded, &mean, NULL)) {
        result = 0;
    }
    if (decoded) g_object_unref(decoded);
    if (buffer) g_free(buffer);
    g_object_unref(probe);
    return result;
}

// MARK: - Evaluation Cancellation

static int swift_vips_passthrough_generate(VipsRegion *out_region, void *seq, void *a, void *b, gboolean *stop) {
    VipsRegion *input_region = (VipsRegion *) seq;
    VipsRect *rect = &out_region->valid;
    if (vips_region_prepare(input_region, rect)) {
        return -1;
    }
    return vips_region_region(out_region, input_region, rect, rect->left, rect->top);
}

/**
 * @brief Wrap `in` in a fresh pass-through image that is never shared.
 *
 * libvips caches operations process-wide, so the final image of one
 * evaluation may be the same object another evaluation uses. Setting the kill
 * flag on that shared image would cancel unrelated work. This wrapper is
 * created outside the operation cache, so killing it only stops the
 * evaluation that owns it. The wrapper keeps a reference to `in`.
 */
static inline VipsImage *swift_vips_evaluation_image(VipsImage *in) {
    VipsImage *out = vips_image_new();
    // Owned by `out`, so `in` outlives every region the wrapper creates.
    g_object_set_data_full(G_OBJECT(out), "hokusai-input", g_object_ref(in), g_object_unref);
    if (vips_image_pipelinev(out, VIPS_DEMAND_STYLE_THINSTRIP, in, NULL) ||
        vips_image_generate(out, vips_start_one, swift_vips_passthrough_generate, vips_stop_one, in, NULL)) {
        g_object_unref(out);
        return NULL;
    }
    return out;
}

typedef struct {
    volatile gint failed;
} SwiftVipsSourceProbe;

static int swift_vips_source_probe_generate(VipsRegion *out_region, void *seq, void *a, void *b, gboolean *stop) {
    VipsRegion *input_region = (VipsRegion *) seq;
    SwiftVipsSourceProbe *probe = (SwiftVipsSourceProbe *) b;
    VipsRect *rect = &out_region->valid;
    if (vips_region_prepare(input_region, rect)) {
        g_atomic_int_set(&probe->failed, 1);
        return -1;
    }
    return vips_region_region(out_region, input_region, rect, rect->left, rect->top);
}

/**
 * @brief Wrap a freshly opened source in a pass-through image that records
 * whether the source itself failed to produce pixels.
 *
 * Decoder failures (truncated or corrupt data under the chosen `fail_on`
 * policy) surface only when pixels are first read, deep inside a later
 * transform or encoder. Failures raised while preparing the wrapped source's
 * regions can only be source failures, so this lets Hokusai classify them as
 * decode errors without reading libvips' error text. The wrapper adds no
 * pixel work and keeps the input alive.
 */
static inline VipsImage *swift_vips_source_probe_image(VipsImage *in) {
    VipsImage *out = vips_image_new();
    SwiftVipsSourceProbe *probe = g_new0(SwiftVipsSourceProbe, 1);
    g_object_set_data_full(G_OBJECT(out), "hokusai-source-probe", probe, g_free);
    g_object_set_data_full(G_OBJECT(out), "hokusai-input", g_object_ref(in), g_object_unref);
    if (vips_image_pipelinev(out, VIPS_DEMAND_STYLE_ANY, in, NULL) ||
        vips_image_generate(out, vips_start_one, swift_vips_source_probe_generate, vips_stop_one, in, probe)) {
        g_object_unref(out);
        return NULL;
    }
    return out;
}

/** @brief Whether the source behind `probe_image` failed to produce pixels. */
static inline int swift_vips_source_probe_failed(VipsImage *probe_image) {
    SwiftVipsSourceProbe *probe = g_object_get_data(G_OBJECT(probe_image), "hokusai-source-probe");
    return probe != NULL && g_atomic_int_get(&probe->failed) != 0;
}

/** @brief Ask libvips workers evaluating `image` to stop as soon as possible. */
static inline void swift_vips_image_kill(VipsImage *image) {
    vips_image_set_kill(image, TRUE);
}

// MARK: - Image Loading

/**
 * @brief Open a local image with explicit decoding policy.
 *
 * `fail_on` is a VipsFailOn value. `page` selects one page when nonnegative;
 * pass -1 to omit it, because loaders without pages reject the argument.
 * `revalidate` bypasses libvips' operation cache for this open.
 */
static inline VipsImage *swift_vips_open_file(const char *path, int sequential, int fail_on, int page, int revalidate) {
    const VipsAccess access = sequential ? VIPS_ACCESS_SEQUENTIAL : VIPS_ACCESS_RANDOM;
    if (page >= 0 && revalidate) {
        return vips_image_new_from_file(path, "access", access, "fail_on", fail_on, "page", page, "revalidate", TRUE, NULL);
    }
    if (page >= 0) {
        return vips_image_new_from_file(path, "access", access, "fail_on", fail_on, "page", page, NULL);
    }
    if (revalidate) {
        return vips_image_new_from_file(path, "access", access, "fail_on", fail_on, "revalidate", TRUE, NULL);
    }
    return vips_image_new_from_file(path, "access", access, "fail_on", fail_on, NULL);
}

/* vips_image_new_from_buffer() does not copy the bytes it is given; the caller
 * would have to keep them alive until the image and its whole pipeline are
 * closed. Swift callers pass pointers that are only valid inside
 * Data.withUnsafeBytes, so this wrapper copies the bytes into a VipsBlob
 * (freed by libvips when the last pipeline reference drops) and loads through
 * a VipsSource. */

/** @brief Open encoded bytes (copied) with explicit decoding policy; `page` as in swift_vips_open_file. */
static inline VipsImage *swift_vips_open_buffer(const void *buf, size_t size, int sequential, int fail_on, int page) {
    VipsBlob *blob = vips_blob_copy(buf, size);
    if (blob == NULL) {
        return NULL;
    }
    VipsSource *source = vips_source_new_from_blob(blob);
    vips_area_unref(VIPS_AREA(blob)); /* the source holds its own reference */
    if (source == NULL) {
        return NULL;
    }
    const VipsAccess access = sequential ? VIPS_ACCESS_SEQUENTIAL : VIPS_ACCESS_RANDOM;
    VipsImage *image = page >= 0
        ? vips_image_new_from_source(source, "", "access", access, "fail_on", fail_on, "page", page, NULL)
        : vips_image_new_from_source(source, "", "access", access, "fail_on", fail_on, NULL);
    g_object_unref(source); /* the image holds its own reference */
    return image;
}

/**
 * @brief Open a JPEG file, letting the decoder shrink it by `shrink` (2, 4 or 8).
 *
 * Only call this for a source whose loader is already known to be a JPEG
 * loader: other loaders reject the `shrink` argument.
 */
static inline VipsImage *swift_vips_open_file_shrink(const char *path, int sequential, int fail_on, int shrink, int revalidate) {
    const VipsAccess access = sequential ? VIPS_ACCESS_SEQUENTIAL : VIPS_ACCESS_RANDOM;
    if (revalidate) {
        return vips_image_new_from_file(path, "access", access, "fail_on", fail_on, "shrink", shrink, "revalidate", TRUE, NULL);
    }
    return vips_image_new_from_file(path, "access", access, "fail_on", fail_on, "shrink", shrink, NULL);
}

/** @brief As swift_vips_open_buffer, for a JPEG source shrunk by the decoder. */
static inline VipsImage *swift_vips_open_buffer_shrink(const void *buf, size_t size, int sequential, int fail_on, int shrink) {
    VipsBlob *blob = vips_blob_copy(buf, size);
    if (blob == NULL) {
        return NULL;
    }
    VipsSource *source = vips_source_new_from_blob(blob);
    vips_area_unref(VIPS_AREA(blob));
    if (source == NULL) {
        return NULL;
    }
    const VipsAccess access = sequential ? VIPS_ACCESS_SEQUENTIAL : VIPS_ACCESS_RANDOM;
    VipsImage *image = vips_image_new_from_source(source, "", "access", access, "fail_on", fail_on, "shrink", shrink, NULL);
    g_object_unref(source);
    return image;
}

/** @brief The number of pages libvips reports for an image (1 when the loader has no pages). */
static inline int swift_vips_image_n_pages(VipsImage *image) {
    return vips_image_get_n_pages(image);
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

// MARK: - Effects (modern evaluator)

static inline int swift_vips_gaussblur_full(VipsImage *in, VipsImage **out, double sigma, int precision, double min_ampl) {
    return vips_gaussblur(in, out, sigma, "precision", (VipsPrecision) precision, "min_ampl", min_ampl, NULL);
}

/** @brief Unsharp mask with every libvips control: x1 flat/jaggy threshold, y2/y3 limits, m1/m2 slopes. */
static inline int swift_vips_sharpen_full(
    VipsImage *in, VipsImage **out, double sigma, double x1, double y2, double y3, double m1, double m2
) {
    return vips_sharpen(in, out, "sigma", sigma, "x1", x1, "y2", y2, "y3", y3, "m1", m1, "m2", m2, NULL);
}

/** @brief The value below which `percent` percent of an 8- or 16-bit single-band image's pixels lie. */
static inline int swift_vips_percent(VipsImage *in, double percent, int *threshold) {
    return vips_percent(in, percent, threshold, NULL);
}

static inline int swift_vips_min(VipsImage *in, double *out) {
    return vips_min(in, out, NULL);
}

static inline int swift_vips_max(VipsImage *in, double *out) {
    return vips_max(in, out, NULL);
}

static inline int swift_vips_linear_array(VipsImage *in, VipsImage **out, const double *a, const double *b, int n) {
    return vips_linear(in, out, a, b, n, NULL);
}

/** @brief out = (in / max) ^ (1 / exponent) * max. */
static inline int swift_vips_gamma(VipsImage *in, VipsImage **out, double exponent) {
    return vips_gamma(in, out, "exponent", exponent, NULL);
}

static inline int swift_vips_invert(VipsImage *in, VipsImage **out) {
    return vips_invert(in, out, NULL);
}

static inline int swift_vips_median(VipsImage *in, VipsImage **out, int size) {
    return vips_median(in, out, size, NULL);
}

static inline int swift_vips_hist_local(VipsImage *in, VipsImage **out, int width, int height, int max_slope) {
    return vips_hist_local(in, out, width, height, "max_slope", max_slope, NULL);
}

static inline int swift_vips_moreeq_const1(VipsImage *in, VipsImage **out, double c) {
    return vips_moreeq_const1(in, out, c, NULL);
}

static inline int swift_vips_premultiply(VipsImage *in, VipsImage **out) {
    return vips_premultiply(in, out, NULL);
}

static inline int swift_vips_unpremultiply(VipsImage *in, VipsImage **out) {
    return vips_unpremultiply(in, out, NULL);
}

static inline int swift_vips_cast(VipsImage *in, VipsImage **out, int format) {
    return vips_cast(in, out, (VipsBandFormat) format, NULL);
}

// MARK: - Geometry (modern evaluator)

/// Embeds `in` in a larger canvas. `background` is only read for
/// VIPS_EXTEND_BACKGROUND and may be NULL for the other modes; unlike
/// `swift_vips_embed` this passes `extend`, so the background actually applies.
static inline int swift_vips_embed_extend(
    VipsImage *in,
    VipsImage **out,
    int x,
    int y,
    int width,
    int height,
    VipsExtend extend,
    VipsArrayDouble *background
) {
    if (background != NULL) {
        return vips_embed(in, out, x, y, width, height, "extend", extend, "background", background, NULL);
    }
    return vips_embed(in, out, x, y, width, height, "extend", extend, NULL);
}

/// Returns a new reference to the named interpolator, or NULL if unknown.
/// The caller releases it with g_object_unref.
static inline VipsInterpolate *swift_vips_interpolate_new(const char *nickname) {
    return vips_interpolate_new(nickname);
}

static inline int swift_vips_rotate(
    VipsImage *in,
    VipsImage **out,
    double angle,
    VipsArrayDouble *background,
    VipsInterpolate *interpolate
) {
    return vips_rotate(in, out, angle, "background", background, "interpolate", interpolate, NULL);
}

/// General 2x2 affine transform. `oarea` is four ints (left, top, width,
/// height) or NULL to use libvips' computed output area.
static inline int swift_vips_affine(
    VipsImage *in,
    VipsImage **out,
    double a, double b, double c, double d,
    VipsInterpolate *interpolate,
    VipsExtend extend,
    VipsArrayDouble *background,
    double idx, double idy, double odx, double ody,
    const int *oarea
) {
    VipsArrayInt *area = oarea != NULL ? vips_array_int_new(oarea, 4) : NULL;
    int result;
    if (area != NULL) {
        result = vips_affine(in, out, a, b, c, d,
            "interpolate", interpolate, "extend", extend, "background", background,
            "idx", idx, "idy", idy, "odx", odx, "ody", ody, "oarea", area, NULL);
        vips_area_unref(VIPS_AREA(area));
    } else {
        result = vips_affine(in, out, a, b, c, d,
            "interpolate", interpolate, "extend", extend, "background", background,
            "idx", idx, "idy", idy, "odx", odx, "ody", ody, NULL);
    }
    return result;
}

/// The Magic Kernel resize kernels exist in headers from libvips 8.15, but
/// Hokusai only offers them on 8.17+. Returns the VipsKernel value, or -1
/// when this build cannot provide `which` (0 = mks2013, 1 = mks2021).
static inline int swift_vips_kernel_mks(int which) {
#if (VIPS_MAJOR_VERSION > 8) || (VIPS_MAJOR_VERSION == 8 && VIPS_MINOR_VERSION >= 17)
    if (vips_version(0) > 8 || (vips_version(0) == 8 && vips_version(1) >= 17)) {
        return which == 0 ? (int) VIPS_KERNEL_MKS2013 : (int) VIPS_KERNEL_MKS2021;
    }
#endif
    (void) which;
    return -1;
}

/// Reads one pixel into `values` (capacity `capacity`); returns the band
/// count, or -1 on failure.
static inline int swift_vips_getpoint(VipsImage *in, int x, int y, double *values, int capacity) {
    double *vector = NULL;
    int n = 0;
    if (vips_getpoint(in, &vector, &n, x, y, NULL) != 0) {
        return -1;
    }
    int copied = n < capacity ? n : capacity;
    for (int i = 0; i < copied; i++) {
        values[i] = vector[i];
    }
    g_free(vector);
    return n;
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
    // Forward full layout and RGBA controls to libvips text rendering.
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
    // Include a font-file override only when the caller supplied one.
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

/**
 * @brief Copy an integer-array metadata field (for example animation `delay`) into `out`.
 *
 * Returns the number of elements the field holds, or -1 when it is absent or
 * not an integer array. At most `capacity` elements are copied, so callers
 * compare the result with `capacity` to detect truncation.
 */
static inline int swift_vips_image_get_int_array_field(VipsImage *in, const char *name, int *out, int capacity) {
    int count = 0;
    int *values = NULL;
    if (vips_image_get_typeof(in, name) == 0 || vips_image_get_array_int(in, name, &values, &count) != 0) {
        return -1;
    }
    for (int index = 0; index < count && index < capacity; index++) {
        out[index] = values[index];
    }
    return count;
}

/** @brief Bits in one sample of a VipsBandFormat. */
static inline int swift_vips_format_bits(int format) {
    return (int) vips_format_sizeof((VipsBandFormat) format) * 8;
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

/** @brief HEIF-container save with an explicit codec: AV1 (AVIF) when `av1` is nonzero, else HEVC (HEIC). */
static inline int swift_vips_heifsave(VipsImage *in, const char *filename, int quality, int lossless, int effort, int strip, int av1) {
    return vips_heifsave(in, filename, "Q", quality, "lossless", lossless, "effort", effort, "strip", strip,
        "compression", av1 ? VIPS_FOREIGN_HEIF_COMPRESSION_AV1 : VIPS_FOREIGN_HEIF_COMPRESSION_HEVC, NULL);
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

/**
 * @brief Buffer variant of swift_vips_heifsave. The codec must be explicit:
 * a buffer has no filename suffix, and libvips otherwise defaults to HEVC.
 */
static inline int swift_vips_heifsave_buffer(VipsImage *in, void **buf, size_t *len, int quality, int lossless, int effort, int strip, int av1) {
    return vips_heifsave_buffer(in, buf, len, "Q", quality, "lossless", lossless, "effort", effort, "strip", strip,
        "compression", av1 ? VIPS_FOREIGN_HEIF_COMPRESSION_AV1 : VIPS_FOREIGN_HEIF_COMPRESSION_HEVC, NULL);
}

static inline int swift_vips_gifsave_buffer(VipsImage *in, void **buf, size_t *len) {
    return vips_gifsave_buffer(in, buf, len, NULL);
}

// MARK: - Output Metadata

/** @brief Whether the image carries a metadata field with this name. */
static inline int swift_vips_image_has_field(VipsImage *in, const char *name) {
    return vips_image_get_typeof(in, name) != 0;
}

/** @brief Remove a metadata field from a private copy. Returns nonzero if it existed. */
static inline int swift_vips_image_remove_field(VipsImage *in, const char *name) {
    return vips_image_remove(in, name);
}

/** @brief A new image sharing the pixels of `in`, safe to edit the metadata of. */
static inline int swift_vips_copy_private(VipsImage *in, VipsImage **out) {
    return vips_copy(in, out, NULL);
}

/** @brief A new image with the given resolution in pixels per millimetre. */
static inline int swift_vips_copy_with_resolution(VipsImage *in, VipsImage **out, double xres, double yres) {
    return vips_copy(in, out, "xres", xres, "yres", yres, NULL);
}

// MARK: - Encoder Targets

/*
 * `keep` is a VipsForeignKeep bit set naming the metadata families to retain.
 * Every modern encoder writes through a VipsTarget, so one option mapping
 * serves the memory and file sinks (and future streams) identically. A target
 * has no filename, so codec choices that libvips would otherwise infer from a
 * suffix (AVIF versus HEIC) are always passed explicitly.
 */

/** @brief Encode as JPEG into `target`. */
static inline int swift_vips_jpegsave_target(VipsImage *in, VipsTarget *target, int quality, int interlace, int keep) {
    return vips_jpegsave_target(in, target, "Q", quality, "interlace", interlace, "keep", keep, NULL);
}

/** @brief Encode as PNG into `target`; `interlace` selects Adam7 interlacing. */
static inline int swift_vips_pngsave_target(VipsImage *in, VipsTarget *target, int compression, int interlace, int keep) {
    return vips_pngsave_target(in, target, "compression", compression, "interlace", interlace, "keep", keep, NULL);
}

/** @brief Encode as WebP into `target`. */
static inline int swift_vips_webpsave_target(VipsImage *in, VipsTarget *target, int quality, int lossless, int effort, int keep) {
    return vips_webpsave_target(in, target, "Q", quality, "lossless", lossless, "effort", effort, "keep", keep, NULL);
}

/** @brief Encode into a HEIF container with an explicit codec: AV1 (AVIF) when `av1` is nonzero, else HEVC (HEIC). */
static inline int swift_vips_heifsave_target(VipsImage *in, VipsTarget *target, int quality, int lossless, int effort, int keep, int av1) {
    return vips_heifsave_target(in, target, "Q", quality, "lossless", lossless, "effort", effort, "keep", keep,
        "compression", av1 ? VIPS_FOREIGN_HEIF_COMPRESSION_AV1 : VIPS_FOREIGN_HEIF_COMPRESSION_HEVC, NULL);
}

/** @brief A target that collects encoded bytes in memory. */
static inline VipsTarget *swift_vips_memory_target_new(void) {
    return vips_target_new_to_memory();
}

/**
 * @brief Take ownership of the bytes an ended memory target collected; free with g_free().
 *
 * Savers end their target, after which the bytes live in its `blob` property.
 * This takes them exactly as libvips' own *save_buffer functions do, by
 * detaching the blob's free function, so no copy is made. Returns NULL when
 * the target holds no data.
 */
static inline unsigned char *swift_vips_memory_target_steal(VipsTarget *target, size_t *length) {
    VipsBlob *blob = NULL;
    *length = 0;
    g_object_get(target, "blob", &blob, NULL);
    if (blob == NULL) {
        return NULL;
    }
    VipsArea *area = VIPS_AREA(blob);
    unsigned char *data = (unsigned char *) area->data;
    *length = area->length;
    area->free_fn = NULL; /* the caller now owns the bytes */
    vips_area_unref(area);
    return data;
}

/**
 * State for a Hokusai-owned file target.
 *
 * The file is opened by the first write, so a pipeline that fails before
 * producing any output never touches the destination. Write failures record
 * their errno here, which is how Hokusai tells a destination I/O failure from
 * an encoder failure without reading libvips' error text.
 */
typedef struct {
    char *path;
    int fd;          /* -1 until the first write opens the file */
    int error;       /* errno of the first failure, else 0 */
    int is_regular;  /* the opened file is a regular file, safe to unlink on failure */
    gint64 written;
} SwiftVipsFileSink;

static inline SwiftVipsFileSink *swift_vips_file_sink_new(const char *path) {
    SwiftVipsFileSink *sink = g_new0(SwiftVipsFileSink, 1);
    sink->path = g_strdup(path);
    sink->fd = -1;
    return sink;
}

static inline gint64 swift_vips_file_sink_written(const SwiftVipsFileSink *sink) {
    return sink->written;
}

static inline int swift_vips_file_sink_error(const SwiftVipsFileSink *sink) {
    return sink->error;
}

static gint64 swift_vips_file_sink_write(VipsTargetCustom *target, const void *data, gint64 length, void *user_data) {
    SwiftVipsFileSink *sink = (SwiftVipsFileSink *) user_data;
    if (sink->error != 0) {
        return -1;
    }
    if (sink->fd < 0) {
        int flags = O_WRONLY | O_CREAT | O_TRUNC;
#ifdef O_CLOEXEC
        flags |= O_CLOEXEC;
#endif
        sink->fd = open(sink->path, flags, 0666);
        if (sink->fd < 0) {
            sink->error = errno;
            return -1;
        }
        struct stat info;
        sink->is_regular = fstat(sink->fd, &info) == 0 && S_ISREG(info.st_mode);
    }
    const char *cursor = (const char *) data;
    gint64 remaining = length;
    while (remaining > 0) {
        ssize_t count = write(sink->fd, cursor, (size_t) remaining);
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            sink->error = errno;
            return -1;
        }
        cursor += count;
        remaining -= count;
        sink->written += count;
    }
    return length;
}

/** @brief A target that writes to `sink`. The caller keeps `sink` alive until the target is released. */
static inline VipsTarget *swift_vips_file_target_new(SwiftVipsFileSink *sink) {
    VipsTargetCustom *target = vips_target_custom_new();
    g_signal_connect(target, "write", G_CALLBACK(swift_vips_file_sink_write), sink);
    return VIPS_TARGET(target);
}

/**
 * @brief Finish a file sink and release it.
 *
 * On success the file is closed, and a failing close is reported. On failure
 * a regular file this sink opened is closed and removed so no partial image
 * is left behind; other kinds of file (devices, pipes) are only closed.
 * Returns the errno of the first failure, or 0.
 */
static inline int swift_vips_file_sink_finish(SwiftVipsFileSink *sink, int succeeded) {
    if (sink->fd >= 0) {
        if (close(sink->fd) != 0 && sink->error == 0) {
            sink->error = errno;
        }
        if ((!succeeded || sink->error != 0) && sink->is_regular) {
            unlink(sink->path);
        }
    }
    int error = sink->error;
    g_free(sink->path);
    g_free(sink);
    return error;
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

/** @brief Blends `n` images (base first) in one call; `mode`, `x` and `y` hold n - 1 entries. */
static inline int swift_vips_composite_array(
    VipsImage **in,
    VipsImage **out,
    int n,
    int *mode,
    const int *x,
    const int *y,
    VipsInterpretation space
) {
    VipsArrayInt *xs = vips_array_int_new(x, n - 1);
    VipsArrayInt *ys = vips_array_int_new(y, n - 1);
    int result = vips_composite(in, out, n, mode, "x", xs, "y", ys, "compositing_space", space, NULL);
    vips_area_unref(VIPS_AREA(xs));
    vips_area_unref(VIPS_AREA(ys));
    return result;
}

/** @brief Repeats an image `across` x `down` times; lazy, no pixels are copied. */
static inline int swift_vips_replicate(VipsImage *in, VipsImage **out, int across, int down) {
    return vips_replicate(in, out, across, down, NULL);
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
// These wrappers expose the vips_thumbnail family for shrink-on-load workflows.
// A non-positive height becomes VIPS_MAX_COORD: unlike an unset height, that
// preserves aspect ratio instead of limiting output to a width-by-width square.
// `VIPS_INTERESTING_NONE` and `no_rotate == 0` retain libvips defaults.

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
